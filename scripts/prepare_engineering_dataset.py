#!/usr/bin/env python3
"""
Generate a reproducible engineering-scale retail dataset from Online Retail II.

This script produces a verifiable, provenance-tracked CSV for ETL/partition/
scheduling stress tests. It is designed for engineering validation, not for
creating new independent business transactions.

Key design decisions:
- Reads text columns explicitly as string type (dtype=str) to avoid
  CustomerID float64/StringArray errors.
- Writes to a temporary file first, then atomically replaces the target.
- Preserves original transaction dates by default (no forced date shift).
- Does NOT default to compressing all data into a single date.
- Automatically generates a JSON manifest with checksums and row counts.
- Default output filename: retail_engineering_reproducible_3x.csv
  (never overwrites the existing legacy data/generated/retail.csv by default).
- Default output contains the original 8 business columns only.
- Lineage columns (source_copy_id, source_row_id) are opt-in via
  --add-lineage-columns. When enabled, the Hive source table DDL must be
  updated to include these extra columns before loading.
- Includes a minimal self-test (--self-test) that runs on a small inline
  sample without requiring external files.

Recommended default usage:
  python scripts/prepare_engineering_dataset.py \
    --input data/raw/online_retail_II.csv \
    --output data/generated/retail_engineering_reproducible_3x.csv \
    --copies 3 \
    --normalize-whitespace

Optional: shift dates and add lineage columns (requires Hive DDL update):
  python scripts/prepare_engineering_dataset.py \
    --input data/raw/online_retail_II.csv \
    --output data/generated/retail_engineering_reproducible_3x.csv \
    --copies 3 \
    --normalize-whitespace \
    --shift-years 17 \
    --add-lineage-columns

Run minimal self-test:
  python scripts/prepare_engineering_dataset.py --self-test
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import pandas as pd


DEFAULT_DATE_COLUMN = "InvoiceDate"
TEXT_COLUMNS = ("Invoice", "StockCode", "Description", "Customer ID", "Country")
DEFAULT_ENCODING = "latin-1"
DEFAULT_CHUNKSIZE = 100_000
DEFAULT_OUTPUT_NAME = "retail_engineering_reproducible_3x.csv"

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------


def sha256_file(path: Path, block_size: int = 1024 * 1024) -> str:
    """Compute SHA-256 hex digest of a file."""
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while block := fh.read(block_size):
            digest.update(block)
    return digest.hexdigest()


def normalize_text_columns(frame: pd.DataFrame) -> pd.DataFrame:
    """Trim surrounding whitespace in text columns; preserve missing values."""
    for col in TEXT_COLUMNS:
        if col in frame.columns:
            mask = frame[col].notna()
            frame.loc[mask, col] = frame.loc[mask, col].astype(str).str.strip()
    return frame


def shift_dates(frame: pd.DataFrame, date_column: str, years: int) -> pd.DataFrame:
    """Shift every timestamp in *date_column* by *years* years.

    Raises ValueError if any value cannot be parsed.
    """
    if years == 0:
        return frame

    parsed = pd.to_datetime(frame[date_column], errors="coerce")
    invalid_count = int(parsed.isna().sum())
    if invalid_count:
        raise ValueError(
            f"{date_column!r} contains {invalid_count} unparseable values; "
            "refusing to shift dates silently."
        )

    shifted = parsed + pd.DateOffset(years=years)
    frame[date_column] = shifted.dt.strftime("%Y-%m-%d %H:%M:%S")
    return frame


def iter_chunks(
    input_path: Path,
    *,
    chunksize: int,
    encoding: str,
) -> Iterable[pd.DataFrame]:
    """Yield DataFrames chunk-by-chunk, with all columns read as string."""
    yield from pd.read_csv(
        input_path,
        chunksize=chunksize,
        dtype=str,               # <-- explicit string type to avoid float64 issues
        low_memory=False,
        encoding=encoding,
    )


def count_rows(input_path: Path, *, chunksize: int, encoding: str) -> int:
    """Count total rows in a CSV (streaming, memory-efficient)."""
    total = 0
    for chunk in iter_chunks(input_path, chunksize=chunksize, encoding=encoding):
        total += len(chunk)
    return total


# ---------------------------------------------------------------------------
# Core generation logic
# ---------------------------------------------------------------------------


def build_dataset(args: argparse.Namespace) -> dict:
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    manifest_path = (
        Path(args.manifest).expanduser().resolve()
        if args.manifest
        else output_path.with_suffix(output_path.suffix + ".manifest.json")
    )

    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    if args.copies < 1:
        raise ValueError("--copies must be at least 1")
    if input_path == output_path:
        raise ValueError("Input and output paths must be different")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    source_sha256 = sha256_file(input_path)
    source_rows = count_rows(
        input_path,
        chunksize=args.chunksize,
        encoding=args.encoding,
    )

    if output_path.exists() and not args.overwrite:
        raise FileExistsError(
            f"Output already exists: {output_path}. Use --overwrite to replace it."
        )

    # Write to a temporary file first, then atomically replace.
    tmp_fd, tmp_path = tempfile.mkstemp(
        suffix=".csv",
        prefix=".prepare_engineering_",
        dir=str(output_path.parent),
    )
    os.close(tmp_fd)
    tmp_file = Path(tmp_path)

    try:
        wrote_header = False
        output_rows = 0
        global_source_row_id = 0

        for copy_id in range(1, args.copies + 1):
            global_source_row_id = 0

            for frame in iter_chunks(
                input_path,
                chunksize=args.chunksize,
                encoding=args.encoding,
            ):
                frame = frame.copy()

                if args.normalize_whitespace:
                    frame = normalize_text_columns(frame)

                if args.shift_years:
                    if args.date_column not in frame.columns:
                        raise KeyError(
                            f"Date column {args.date_column!r} not found. "
                            f"Available columns: {list(frame.columns)}"
                        )
                    frame = shift_dates(frame, args.date_column, args.shift_years)

                if args.add_lineage_columns:
                    row_count = len(frame)
                    frame["source_copy_id"] = copy_id
                    frame["source_row_id"] = range(
                        global_source_row_id + 1,
                        global_source_row_id + row_count + 1,
                    )
                    global_source_row_id += row_count

                mode = "w" if not wrote_header else "a"
                frame.to_csv(
                    tmp_file,
                    mode=mode,
                    index=False,
                    header=not wrote_header,
                    encoding="utf-8",
                    lineterminator="\n",
                )
                wrote_header = True
                output_rows += len(frame)

        expected_rows = source_rows * args.copies
        if output_rows != expected_rows:
            raise RuntimeError(
                f"Row-count mismatch: wrote {output_rows}, expected {expected_rows}"
            )

        # Atomic replace: rename temp file to target path.
        tmp_file.replace(output_path)

    except Exception:
        # Clean up temp file on any failure.
        if tmp_file.exists():
            tmp_file.unlink()
        raise

    output_sha256 = sha256_file(output_path)

    manifest = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "profile": "engineering_legacy_3x",
        "purpose": (
            "Engineering-scale validation for ETL, partitioning, scheduling, "
            "idempotent reruns, and data-quality checks. Expanded rows are not "
            "independent real-world transactions. This profile preserves the "
            "historical engineering regression baseline."
        ),
        "source": {
            "dataset": "Online Retail II",
            "direct_download_source": "Kaggle: mashlyn/online-retail-ii-uci",
            "upstream_source": "UCI Machine Learning Repository",
            "input_path": str(input_path),
            "sha256": source_sha256,
            "rows": source_rows,
            "encoding": args.encoding,
        },
        "generation": {
            "copies": args.copies,
            "normalize_whitespace": args.normalize_whitespace,
            "date_column": args.date_column,
            "shift_years": args.shift_years,
            "add_lineage_columns": args.add_lineage_columns,
            "chunksize": args.chunksize,
            "note": (
                "Original dates are preserved by default (shift_years=0). "
                "Date shift is opt-in via --shift-years."
            ),
        },
        "output": {
            "path": str(output_path),
            "sha256": output_sha256,
            "rows": output_rows,
            "encoding": "utf-8",
        },
    }

    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return manifest


# ---------------------------------------------------------------------------
# Minimal self-test
# ---------------------------------------------------------------------------


SELF_TEST_CSV = (
    "Invoice,StockCode,Description,Quantity,InvoiceDate,Price,Customer ID,Country\n"
    "536365,85123A,WHITE HANGING HEART T-LIGHT HOLDER,6,2010-12-01 08:26,2.55,17850.0,United Kingdom\n"
    "536366,22633,HAND WARMER UNION JACK,6,2010-12-01 08:28,1.85,17850,United Kingdom\n"
    "C536367,ABC,,0,2010-12-01 08:30,0.00,,United Kingdom\n"
)


def run_self_test() -> int:
    """Minimal self-test using inline CSV data. No external files required.

    Tests two scenarios:
    1. Default mode: 8 business columns only, no lineage columns
    2. Lineage mode: 8 business columns + source_copy_id + source_row_id
    """
    test_dir = Path(tempfile.mkdtemp(prefix="prepare_engineering_self_test_"))
    try:
        input_csv = test_dir / "test_input.csv"
        input_csv.write_text(SELF_TEST_CSV, encoding="utf-8")

        # Test 1: Default mode (no lineage columns)
        print("Running self-test 1: default mode (no lineage columns)...")
        output_csv1 = test_dir / "test_output_default.csv"
        manifest_csv1 = test_dir / "test_output_default.csv.manifest.json"

        args1 = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv1),
            copies=2,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,
            add_lineage_columns=False,
            manifest=str(manifest_csv1),
            overwrite=False,
        )

        manifest1 = build_dataset(args1)

        assert output_csv1.exists(), "Output CSV not created (default mode)"
        assert manifest_csv1.exists(), "Manifest not created (default mode)"

        output_rows1 = manifest1["output"]["rows"]
        assert output_rows1 == 6, f"Expected 6 rows (3 source × 2 copies), got {output_rows1}"

        # Verify no lineage columns in default mode
        df1 = pd.read_csv(output_csv1, dtype=str)
        assert "source_copy_id" not in df1.columns, "source_copy_id should NOT exist in default mode"
        assert "source_row_id" not in df1.columns, "source_row_id should NOT exist in default mode"

        # Verify original 8 columns exist
        expected_cols = {"Invoice", "StockCode", "Description", "Quantity", "InvoiceDate", "Price", "Customer ID", "Country"}
        actual_cols = set(df1.columns)
        assert actual_cols == expected_cols, f"Expected columns {expected_cols}, got {actual_cols}"

        # Verify Customer ID can be empty (row 3 has empty Customer ID)
        assert df1["Customer ID"].isna().any() or (df1["Customer ID"] == "").any(), "Customer ID should allow empty values"

        print("Self-test 1 PASSED: default mode")

        # Test 2: Lineage mode (with source_copy_id and source_row_id)
        print("Running self-test 2: lineage mode (with lineage columns)...")
        output_csv2 = test_dir / "test_output_lineage.csv"
        manifest_csv2 = test_dir / "test_output_lineage.csv.manifest.json"

        args2 = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv2),
            copies=2,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,
            add_lineage_columns=True,
            manifest=str(manifest_csv2),
            overwrite=False,
        )

        manifest2 = build_dataset(args2)

        assert output_csv2.exists(), "Output CSV not created (lineage mode)"
        assert manifest_csv2.exists(), "Manifest not created (lineage mode)"

        output_rows2 = manifest2["output"]["rows"]
        assert output_rows2 == 6, f"Expected 6 rows (3 source × 2 copies), got {output_rows2}"

        # Verify lineage columns exist
        df2 = pd.read_csv(output_csv2, dtype=str)
        assert "source_copy_id" in df2.columns, "source_copy_id column missing in lineage mode"
        assert "source_row_id" in df2.columns, "source_row_id column missing in lineage mode"

        print("Self-test 2 PASSED: lineage mode")

        print("\nALL SELF-TESTS PASSED")
        print("\nDefault mode manifest:")
        print(json.dumps(manifest1, ensure_ascii=False, indent=2))
        print("\nLineage mode manifest:")
        print(json.dumps(manifest2, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        print(f"SELF-TEST FAILED: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1
    finally:
        shutil.rmtree(test_dir, ignore_errors=True)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a reproducible engineering-scale Online Retail II CSV."
    )
    parser.add_argument(
        "--input",
        help="Path to canonical source CSV (required unless --self-test)",
    )
    parser.add_argument(
        "--output",
        help=(
            f"Path to generated CSV (default: data/generated/{DEFAULT_OUTPUT_NAME}). "
            "Never defaults to the existing legacy data/generated/retail.csv."
        ),
    )
    parser.add_argument(
        "--copies",
        type=int,
        default=3,
        help="Number of complete source copies to write (default: 3)",
    )
    parser.add_argument(
        "--encoding",
        default=DEFAULT_ENCODING,
        help=f"Source CSV encoding (default: {DEFAULT_ENCODING})",
    )
    parser.add_argument(
        "--chunksize",
        type=int,
        default=DEFAULT_CHUNKSIZE,
        help=f"Rows per processing chunk (default: {DEFAULT_CHUNKSIZE})",
    )
    parser.add_argument(
        "--date-column",
        default=DEFAULT_DATE_COLUMN,
        help=f"Transaction date column (default: {DEFAULT_DATE_COLUMN})",
    )
    parser.add_argument(
        "--shift-years",
        type=int,
        default=0,
        help=(
            "Shift every timestamp by this many years while preserving relative "
            "time order (default: 0, preserve original dates)"
        ),
    )
    parser.add_argument(
        "--normalize-whitespace",
        action="store_true",
        help="Trim surrounding whitespace in text columns",
    )
    parser.add_argument(
        "--add-lineage-columns",
        action="store_true",
        help=(
            "Append source_copy_id and source_row_id columns. "
            "WARNING: When enabled, the Hive source table DDL must be updated "
            "to include these extra columns before loading."
        ),
    )
    parser.add_argument(
        "--manifest",
        help="Optional manifest JSON path; defaults beside output",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace an existing output file",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run a minimal self-test using inline data (no external files needed)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.self_test:
        return run_self_test()

    if not args.input:
        print("ERROR: --input is required (or use --self-test)", file=sys.stderr)
        return 1

    if not args.output:
        args.output = os.path.join("data", "generated", DEFAULT_OUTPUT_NAME)

    try:
        manifest = build_dataset(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())