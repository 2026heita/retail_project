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
- Default output filename is dynamically generated based on profile:
  - canonical: retail_canonical.csv
  - engineering_reproducible: retail_engineering_reproducible_<copies>x.csv
- Default output contains the original 8 business columns only.
- Lineage columns (source_copy_id, source_row_id) are opt-in via
  --add-lineage-columns. When enabled, the Hive source table DDL must be
  updated to include these extra columns before loading.
- Includes a minimal self-test (--self-test) that runs on a small inline
  sample without requiring external files.

Profile rules:
- canonical: copies=1, shift_years=0, no normalize-whitespace, no lineage columns
  Output is byte-level copy of source, SHA256 must match.
- engineering_reproducible: allows copies and optional date shift
- synthetic_multiday: removed from valid profiles (historical data only)

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
import re
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

# For testing rollback mechanism
_TEST_COMMIT_FAILURE_AFTER_CSV = False
_TEST_GENERATION_FAILURE = False

# Profile definitions
# Note: engineering_legacy_3x is reserved for describing existing historical 3.2M files,
# not for generating new datasets. Use engineering_reproducible for new generations.
# synthetic_multiday is removed from valid profiles (historical data only, documented in README)
VALID_PROFILES = ("canonical", "engineering_reproducible")

PROFILE_METADATA = {
    "canonical": {
        "purpose": (
            "Original UCI Online Retail II dataset (1,067,371 rows, 2009-2011). "
            "Used for business metric definition and standard data validation. "
            "Dates are preserved as-is from the source. "
            "Output is byte-level copy, SHA256 matches source."
        ),
        "limitations": (
            "This is the original public dataset. Do not claim it represents "
            "real enterprise business data."
        ),
    },
    "engineering_reproducible": {
        "purpose": (
            "Engineering-scale validation for ETL, partitioning, scheduling, "
            "idempotent reruns, and data-quality checks. Expanded rows are not "
            "independent real-world transactions."
        ),
        "limitations": (
            "This profile uses copies of source data with optional date shift. "
            "Do not present results as real business outcomes."
        ),
    },
}


# ---------------------------------------------------------------------------
# Date parsing utilities
# ---------------------------------------------------------------------------


def parse_invoice_date(date_str: str) -> datetime | None:
    """Parse InvoiceDate with explicit format detection.

    Supported formats (based on actual CSV audit):
    - yyyy-MM-dd H:mm:ss (primary, all 1,067,371 rows)
    - yyyy-MM-dd H:mm (without seconds)
    - d/M/yyyy H:mm:ss (day/month format)
    - d/M/yyyy H:mm (day/month without seconds)

    Returns None if parsing fails.
    """
    if not date_str or not isinstance(date_str, str):
        return None

    date_str = date_str.strip()
    if not date_str:
        return None

    # Try yyyy-MM-dd H:mm:ss (primary format)
    if re.match(r"^\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}:\d{2}$", date_str):
        try:
            return datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return None

    # Try yyyy-MM-dd H:mm (without seconds)
    if re.match(r"^\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}$", date_str):
        try:
            return datetime.strptime(date_str, "%Y-%m-%d %H:%M")
        except ValueError:
            return None

    # Try d/M/yyyy H:mm:ss (day/month format)
    if re.match(r"^\d{1,2}/\d{1,2}/\d{4} \d{1,2}:\d{2}:\d{2}$", date_str):
        try:
            return datetime.strptime(date_str, "%d/%m/%Y %H:%M:%S")
        except ValueError:
            return None

    # Try d/M/yyyy H:mm (day/month without seconds)
    if re.match(r"^\d{1,2}/\d{1,2}/\d{4} \d{1,2}:\d{2}$", date_str):
        try:
            return datetime.strptime(date_str, "%d/%m/%Y %H:%M")
        except ValueError:
            return None

    # Unknown format
    return None


def parse_date_column(series: pd.Series) -> tuple[pd.Series, int, int]:
    """Parse a date column using explicit format detection.

    Returns:
        - parsed_dates: pd.Series of datetime objects (NaT for failures)
        - parseable_count: number of successfully parsed dates
        - unparseable_count: number of failed parses
    """
    parsed = series.apply(parse_invoice_date)
    parsed_dates = pd.to_datetime(parsed, errors="coerce")

    parseable_mask = parsed_dates.notna()
    parseable_count = int(parseable_mask.sum())
    unparseable_count = int((~parseable_mask).sum())

    return parsed_dates, parseable_count, unparseable_count


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

    Uses unified date parsing function.
    Raises ValueError if any value cannot be parsed.
    """
    if years == 0:
        return frame

    parsed_dates, parseable_count, unparseable_count = parse_date_column(
        frame[date_column]
    )

    if unparseable_count > 0:
        raise ValueError(
            f"{date_column!r} contains {unparseable_count} unparseable values; "
            "refusing to shift dates silently."
        )

    shifted = parsed_dates + pd.DateOffset(years=years)
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


def get_default_output_name(profile: str, copies: int) -> str:
    """Generate default output filename based on profile."""
    if profile == "canonical":
        return "retail_canonical.csv"
    elif profile == "engineering_reproducible":
        return f"retail_engineering_reproducible_{copies}x.csv"
    else:
        raise ValueError(f"Unknown profile: {profile}")


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

    # Profile validation
    profile = getattr(args, "profile", "engineering_reproducible")

    if profile == "canonical":
        if args.copies != 1:
            raise ValueError(
                f"canonical profile requires copies=1, got copies={args.copies}"
            )
        if args.shift_years != 0:
            raise ValueError(
                f"canonical profile requires shift_years=0, got shift_years={args.shift_years}"
            )
        if args.normalize_whitespace:
            raise ValueError(
                "canonical profile forbids --normalize-whitespace; "
                "output must be byte-level copy of source"
            )
        if args.add_lineage_columns:
            raise ValueError(
                "canonical profile forbids --add-lineage-columns; "
                "output must be byte-level copy of source"
            )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    source_sha256 = sha256_file(input_path)
    source_rows = count_rows(
        input_path,
        chunksize=args.chunksize,
        encoding=args.encoding,
    )

    # Check if either output file exists
    csv_exists = output_path.exists()
    manifest_exists = manifest_path.exists()

    if (csv_exists or manifest_exists) and not args.overwrite:
        existing = []
        if csv_exists:
            existing.append(str(output_path))
        if manifest_exists:
            existing.append(str(manifest_path))
        raise FileExistsError(
            f"Output file(s) already exist: {', '.join(existing)}. "
            f"Use --overwrite to replace them."
        )

    # Write CSV to a temporary file
    csv_tmp_fd, csv_tmp_path = tempfile.mkstemp(
        suffix=".csv",
        prefix=".prepare_engineering_csv_",
        dir=str(output_path.parent),
    )
    os.close(csv_tmp_fd)
    csv_tmp_file = Path(csv_tmp_path)

    # Write manifest to a temporary file
    manifest_tmp_fd, manifest_tmp_path = tempfile.mkstemp(
        suffix=".manifest.json",
        prefix=".prepare_engineering_manifest_",
        dir=str(manifest_path.parent),
    )
    os.close(manifest_tmp_fd)
    manifest_tmp_file = Path(manifest_tmp_path)

    try:
        # For canonical profile: byte-level copy
        if profile == "canonical":
            # Test hook: simulate generation failure
            if _TEST_GENERATION_FAILURE:
                raise RuntimeError("Simulated generation failure")

            # Byte-level copy to temp file
            shutil.copy2(input_path, csv_tmp_file)
            output_rows = source_rows
            output_sha256 = source_sha256

            # Date statistics for manifest (parse source dates)
            source_earliest_date = None
            source_latest_date = None
            source_parseable_rows = 0
            source_unparseable_rows = 0

            for frame in iter_chunks(
                input_path,
                chunksize=args.chunksize,
                encoding=args.encoding,
            ):
                if args.date_column in frame.columns:
                    parsed_dates, parseable_count, unparseable_count = parse_date_column(
                        frame[args.date_column]
                    )
                    source_parseable_rows += parseable_count
                    source_unparseable_rows += unparseable_count

                    parseable_mask = parsed_dates.notna()
                    if parseable_mask.any():
                        chunk_min = parsed_dates[parseable_mask].min()
                        chunk_max = parsed_dates[parseable_mask].max()

                        if source_earliest_date is None or chunk_min < source_earliest_date:
                            source_earliest_date = chunk_min
                        if source_latest_date is None or chunk_max > source_latest_date:
                            source_latest_date = chunk_max

            # Output dates are same as source for canonical
            output_earliest_date = source_earliest_date
            output_latest_date = source_latest_date

        else:
            # For engineering_reproducible: process data
            wrote_header = False
            output_rows = 0
            global_source_row_id = 0

            # Date range statistics
            source_earliest_date = None
            source_latest_date = None
            source_parseable_rows = 0
            source_unparseable_rows = 0
            output_earliest_date = None
            output_latest_date = None

            # Test hook: simulate generation failure
            if _TEST_GENERATION_FAILURE:
                raise RuntimeError("Simulated generation failure")

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

                    # Collect source date statistics (only on first copy to avoid duplication)
                    if copy_id == 1 and args.date_column in frame.columns:
                        parsed_dates, parseable_count, unparseable_count = parse_date_column(
                            frame[args.date_column]
                        )
                        source_parseable_rows += parseable_count
                        source_unparseable_rows += unparseable_count

                        parseable_mask = parsed_dates.notna()
                        if parseable_mask.any():
                            chunk_min = parsed_dates[parseable_mask].min()
                            chunk_max = parsed_dates[parseable_mask].max()

                            if source_earliest_date is None or chunk_min < source_earliest_date:
                                source_earliest_date = chunk_min
                            if source_latest_date is None or chunk_max > source_latest_date:
                                source_latest_date = chunk_max

                    if args.shift_years:
                        if args.date_column not in frame.columns:
                            raise KeyError(
                                f"Date column {args.date_column!r} not found. "
                                f"Available columns: {list(frame.columns)}"
                            )
                        frame = shift_dates(frame, args.date_column, args.shift_years)

                    # Collect output date statistics (only on first copy to avoid duplication)
                    if copy_id == 1 and args.date_column in frame.columns:
                        output_parsed, _, _ = parse_date_column(frame[args.date_column])
                        output_parseable = output_parsed.notna()

                        if output_parseable.any():
                            out_chunk_min = output_parsed[output_parseable].min()
                            out_chunk_max = output_parsed[output_parseable].max()

                            if output_earliest_date is None or out_chunk_min < output_earliest_date:
                                output_earliest_date = out_chunk_min
                            if output_latest_date is None or out_chunk_max > output_latest_date:
                                output_latest_date = out_chunk_max

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
                        csv_tmp_file,
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

            # CSV written successfully, compute SHA256
            output_sha256 = sha256_file(csv_tmp_file)

        # Prepare manifest
        profile_meta = PROFILE_METADATA.get(profile, PROFILE_METADATA["engineering_reproducible"])

        # Format date range for manifest
        source_date_range = {}
        if source_earliest_date is not None:
            source_date_range["earliest_invoice_date"] = source_earliest_date.strftime("%Y-%m-%d")
        if source_latest_date is not None:
            source_date_range["latest_invoice_date"] = source_latest_date.strftime("%Y-%m-%d")
        source_date_range["parseable_date_rows"] = source_parseable_rows
        source_date_range["unparseable_date_rows"] = source_unparseable_rows

        output_date_range = {}
        if output_earliest_date is not None:
            output_date_range["earliest_invoice_date"] = output_earliest_date.strftime("%Y-%m-%d")
        if output_latest_date is not None:
            output_date_range["latest_invoice_date"] = output_latest_date.strftime("%Y-%m-%d")

        manifest = {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "profile": profile,
            "purpose": profile_meta["purpose"],
            "limitations": profile_meta["limitations"],
            "source": {
                "dataset": "Online Retail II",
                "direct_download_source": "Kaggle: mashlyn/online-retail-ii-uci",
                "upstream_source": "UCI Machine Learning Repository",
                "input_path": str(input_path),
                "sha256": source_sha256,
                "rows": source_rows,
                "encoding": args.encoding,
                **source_date_range,
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
                    "Date shift is optional via --shift-years."
                ),
            },
            "output": {
                "path": str(output_path),
                "sha256": output_sha256,
                "rows": output_rows,
                "encoding": "utf-8",
                **output_date_range,
            },
        }

        # Write manifest to temp file
        manifest_tmp_file.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        # NOW backup old files (after successful generation)
        csv_backup = None
        manifest_backup = None

        if args.overwrite:
            try:
                if csv_exists:
                    csv_backup_fd, csv_backup_path = tempfile.mkstemp(
                        suffix=".csv.backup",
                        prefix=".prepare_engineering_",
                        dir=str(output_path.parent),
                    )
                    os.close(csv_backup_fd)
                    csv_backup = Path(csv_backup_path)
                    shutil.copy2(output_path, csv_backup)

                if manifest_exists:
                    manifest_backup_fd, manifest_backup_path = tempfile.mkstemp(
                        suffix=".manifest.json.backup",
                        prefix=".prepare_engineering_",
                        dir=str(manifest_path.parent),
                    )
                    os.close(manifest_backup_fd)
                    manifest_backup = Path(manifest_backup_path)
                    shutil.copy2(manifest_path, manifest_backup)
            except Exception as e:
                # Clean up any backups that were created
                if csv_backup and csv_backup.exists():
                    csv_backup.unlink()
                if manifest_backup and manifest_backup.exists():
                    manifest_backup.unlink()
                # Clean up temp files
                if csv_tmp_file.exists():
                    csv_tmp_file.unlink()
                if manifest_tmp_file.exists():
                    manifest_tmp_file.unlink()
                raise RuntimeError(f"Failed to create backups: {e}")

        # Rollback-safe replacement
        try:
            # Test hook: simulate failure after CSV replacement
            if _TEST_COMMIT_FAILURE_AFTER_CSV:
                csv_tmp_file.replace(output_path)
                raise RuntimeError("Simulated manifest commit failure")

            # Replace files
            csv_tmp_file.replace(output_path)
            manifest_tmp_file.replace(manifest_path)

            # Success: delete backups
            if csv_backup and csv_backup.exists():
                csv_backup.unlink()
            if manifest_backup and manifest_backup.exists():
                manifest_backup.unlink()

        except Exception as e:
            # Rollback: restore to pre-execution state
            # If file existed before: restore from backup
            # If file did not exist before: delete the new file
            if csv_backup and csv_backup.exists():
                # File existed before, restore from backup
                if output_path.exists():
                    output_path.unlink()
                shutil.copy2(csv_backup, output_path)
                csv_backup.unlink()
            elif not csv_exists and output_path.exists():
                # File did not exist before, delete the new file
                output_path.unlink()

            if manifest_backup and manifest_backup.exists():
                # File existed before, restore from backup
                if manifest_path.exists():
                    manifest_path.unlink()
                shutil.copy2(manifest_backup, manifest_path)
                manifest_backup.unlink()
            elif not manifest_exists and manifest_path.exists():
                # File did not exist before, delete the new file
                manifest_path.unlink()

            # Clean up temp files if they still exist
            if csv_tmp_file.exists():
                csv_tmp_file.unlink()
            if manifest_tmp_file.exists():
                manifest_tmp_file.unlink()

            raise RuntimeError(f"Failed to commit files, rolled back to previous state: {e}")

    except Exception as e:
        # Clean up temp files on any failure
        if csv_tmp_file.exists():
            csv_tmp_file.unlink()
        if manifest_tmp_file.exists():
            manifest_tmp_file.unlink()
        raise

    return manifest


# ---------------------------------------------------------------------------
# Minimal self-test
# ---------------------------------------------------------------------------


SELF_TEST_CSV = (
    "Invoice,StockCode,Description,Quantity,InvoiceDate,Price,Customer ID,Country\n"
    "536365,85123A,WHITE HANGING HEART T-LIGHT HOLDER,6,2010-12-01 08:26:00,2.55,17850.0,United Kingdom\n"
    "536366,22633,HAND WARMER UNION JACK,6,2010-12-01 08:28,1.85,17850,United Kingdom\n"
    "C536367,ABC,,0,1/12/2010 08:30:00,0.00,,United Kingdom\n"
)


def run_self_test() -> int:
    """Minimal self-test using inline CSV data. No external files required.

    Tests multiple scenarios including canonical byte-level copy, date parsing, and rollback.
    """
    test_dir = Path(tempfile.mkdtemp(prefix="prepare_engineering_self_test_"))
    try:
        input_csv = test_dir / "test_input.csv"
        input_csv.write_text(SELF_TEST_CSV, encoding="utf-8")

        # Test 1: Default mode (no lineage columns)
        print("Running self-test 1: default mode (no lineage columns)...")
        output_csv1 = test_dir / "test_outputDefault.csv"
        manifest_csv1 = test_dir / "test_outputDefault.csv.manifest.json"

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
            profile="engineering_reproducible",
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
            profile="engineering_reproducible",
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

        # Test 3: Profile canonical (byte-level copy)
        print("Running self-test 3: profile canonical (byte-level copy)...")
        output_csv3 = test_dir / "retail_canonical.csv"
        manifest_csv3 = test_dir / "retail_canonical.csv.manifest.json"

        args3 = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv3),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=False,
            add_lineage_columns=False,
            manifest=str(manifest_csv3),
            overwrite=False,
            profile="canonical",
        )

        manifest3 = build_dataset(args3)

        assert output_csv3.exists(), "Output CSV not created (canonical profile)"
        assert manifest_csv3.exists(), "Manifest not created (canonical profile)"

        output_rows3 = manifest3["output"]["rows"]
        assert output_rows3 == 3, f"Expected 3 rows (3 source × 1 copy), got {output_rows3}"

        # Verify SHA256 matches source (byte-level copy)
        source_sha = sha256_file(input_csv)
        output_sha = sha256_file(output_csv3)
        assert source_sha == output_sha, f"Canonical SHA256 mismatch: source={source_sha}, output={output_sha}"

        # Verify manifest uses canonical profile metadata
        assert manifest3["profile"] == "canonical", "Manifest profile should be 'canonical'"
        assert "Original UCI Online Retail II dataset" in manifest3["purpose"], "Canonical purpose metadata incorrect"
        assert "Do not claim it represents real enterprise business data" in manifest3["limitations"], "Canonical limitations metadata incorrect"

        # Verify date range in manifest
        assert "earliest_invoice_date" in manifest3["source"], "Missing earliest_invoice_date in manifest"
        assert "latest_invoice_date" in manifest3["source"], "Missing latest_invoice_date in manifest"
        assert manifest3["source"]["earliest_invoice_date"] == "2010-12-01", f"Expected 2010-12-01, got {manifest3['source']['earliest_invoice_date']}"
        assert manifest3["source"]["latest_invoice_date"] == "2010-12-01", f"Expected 2010-12-01, got {manifest3['source']['latest_invoice_date']}"
        assert manifest3["source"]["parseable_date_rows"] == 3, f"Expected 3 parseable rows, got {manifest3['source']['parseable_date_rows']}"
        assert manifest3["source"]["unparseable_date_rows"] == 0, f"Expected 0 unparseable rows, got {manifest3['source']['unparseable_date_rows']}"

        print("Self-test 3 PASSED: profile canonical (byte-level copy)")

        # Test 4: canonical with copies=3 should fail
        print("Running self-test 4: canonical with copies=3 should fail...")
        output_csv4 = test_dir / "test_output_canonical_invalid.csv"
        manifest_csv4 = test_dir / "test_output_canonical_invalid.csv.manifest.json"

        args4 = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv4),
            copies=3,  # Invalid for canonical
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=False,
            add_lineage_columns=False,
            manifest=str(manifest_csv4),
            overwrite=False,
            profile="canonical",
        )

        try:
            build_dataset(args4)
            raise AssertionError("canonical with copies=3 should have raised ValueError")
        except ValueError as exc:
            assert "copies=1" in str(exc), f"Expected copies=1 error, got: {exc}"
        print("Self-test 4 PASSED: canonical with copies=3 rejected")

        # Test 5: canonical with shift_years!=0 should fail
        print("Running self-test 5: canonical with shift_years!=0 should fail...")
        output_csv5 = test_dir / "test_output_canonical_shift.csv"
        manifest_csv5 = test_dir / "test_output_canonical_shift.csv.manifest.json"

        args5 = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv5),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=17,  # Invalid for canonical
            normalize_whitespace=False,
            add_lineage_columns=False,
            manifest=str(manifest_csv5),
            overwrite=False,
            profile="canonical",
        )

        try:
            build_dataset(args5)
            raise AssertionError("canonical with shift_years=17 should have raised ValueError")
        except ValueError as exc:
            assert "shift_years=0" in str(exc), f"Expected shift_years=0 error, got: {exc}"
        print("Self-test 5 PASSED: canonical with shift_years!=0 rejected")

        # Test 6: canonical with normalize_whitespace should fail
        print("Running self-test 6: canonical with normalize_whitespace should fail...")
        output_csv6 = test_dir / "test_output_canonical_normalize.csv"
        manifest_csv6 = test_dir / "test_output_canonical_normalize.csv.manifest.json"

        args6 = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv6),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,  # Invalid for canonical
            add_lineage_columns=False,
            manifest=str(manifest_csv6),
            overwrite=False,
            profile="canonical",
        )

        try:
            build_dataset(args6)
            raise AssertionError("canonical with normalize_whitespace should have raised ValueError")
        except ValueError as exc:
            assert "normalize-whitespace" in str(exc), f"Expected normalize-whitespace error, got: {exc}"
        print("Self-test 6 PASSED: canonical with normalize_whitespace rejected")

        # Test 7: Manifest commit failure rollback
        print("Running self-test 7: manifest commit failure rollback...")
        output_csv7 = test_dir / "test_output_rollback.csv"
        manifest_csv7 = test_dir / "test_output_rollback.csv.manifest.json"

        # Create initial files
        args7_init = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv7),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,
            add_lineage_columns=False,
            manifest=str(manifest_csv7),
            overwrite=False,
            profile="engineering_reproducible",
        )
        build_dataset(args7_init)

        # Record original content
        original_csv_content = output_csv7.read_bytes()
        original_manifest_content = manifest_csv7.read_bytes()

        # Enable test hook to simulate failure
        global _TEST_COMMIT_FAILURE_AFTER_CSV
        _TEST_COMMIT_FAILURE_AFTER_CSV = True

        try:
            args7_overwrite = argparse.Namespace(
                input=str(input_csv),
                output=str(output_csv7),
                copies=2,  # Different to verify rollback
                encoding="utf-8",
                chunksize=2,
                date_column=DEFAULT_DATE_COLUMN,
                shift_years=0,
                normalize_whitespace=True,
                add_lineage_columns=False,
                manifest=str(manifest_csv7),
                overwrite=True,
                profile="engineering_reproducible",
            )

            try:
                build_dataset(args7_overwrite)
                raise AssertionError("Should have raised RuntimeError due to simulated failure")
            except RuntimeError as exc:
                assert "Simulated manifest commit failure" in str(exc)

            # Verify rollback: files should be restored to original state
            assert output_csv7.exists(), "CSV should exist after rollback"
            assert manifest_csv7.exists(), "Manifest should exist after rollback"

            restored_csv_content = output_csv7.read_bytes()
            restored_manifest_content = manifest_csv7.read_bytes()

            assert restored_csv_content == original_csv_content, "CSV should be restored to original"
            assert restored_manifest_content == original_manifest_content, "Manifest should be restored to original"

            # Verify no residual temp files or backups
            temp_files = list(test_dir.glob(".prepare_engineering_*"))
            assert len(temp_files) == 0, f"No temp files should remain, found: {temp_files}"

            print("Self-test 7 PASSED: manifest commit failure rollback")
        finally:
            _TEST_COMMIT_FAILURE_AFTER_CSV = False

        # Test 8: Reject overwrite when either file exists
        print("Running self-test 8: reject overwrite when either file exists...")

        # Test 8a: Only CSV exists
        output_csv8a = test_dir / "test_output_no_overwrite_csv.csv"
        manifest_csv8a = test_dir / "test_output_no_overwrite_csv.csv.manifest.json"
        output_csv8a.write_text("dummy", encoding="utf-8")

        args8a = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv8a),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,
            add_lineage_columns=False,
            manifest=str(manifest_csv8a),
            overwrite=False,
            profile="engineering_reproducible",
        )

        try:
            build_dataset(args8a)
            raise AssertionError("Should have raised FileExistsError when only CSV exists")
        except FileExistsError as exc:
            assert "already exist" in str(exc)

        # Test 8b: Only manifest exists
        output_csv8b = test_dir / "test_output_no_overwrite_manifest.csv"
        manifest_csv8b = test_dir / "test_output_no_overwrite_manifest.csv.manifest.json"
        manifest_csv8b.write_text("{}", encoding="utf-8")

        args8b = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv8b),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,
            add_lineage_columns=False,
            manifest=str(manifest_csv8b),
            overwrite=False,
            profile="engineering_reproducible",
        )

        try:
            build_dataset(args8b)
            raise AssertionError("Should have raised FileExistsError when only manifest exists")
        except FileExistsError as exc:
            assert "already exist" in str(exc)

        # Test 8c: Both files exist
        output_csv8c = test_dir / "test_output_no_overwrite_both.csv"
        manifest_csv8c = test_dir / "test_output_no_overwrite_both.csv.manifest.json"
        output_csv8c.write_text("dummy", encoding="utf-8")
        manifest_csv8c.write_text("{}", encoding="utf-8")

        args8c = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv8c),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,
            add_lineage_columns=False,
            manifest=str(manifest_csv8c),
            overwrite=False,
            profile="engineering_reproducible",
        )

        try:
            build_dataset(args8c)
            raise AssertionError("Should have raised FileExistsError when both files exist")
        except FileExistsError as exc:
            assert "already exist" in str(exc)

        print("Self-test 8 PASSED: reject overwrite when either file exists")

        # Test 9: First-time generation with manifest commit failure
        print("Running self-test 9: first-time generation with manifest commit failure...")
        output_csv9 = test_dir / "test_output_first_time.csv"
        manifest_csv9 = test_dir / "test_output_first_time.csv.manifest.json"

        # Ensure files do not exist
        if output_csv9.exists():
            output_csv9.unlink()
        if manifest_csv9.exists():
            manifest_csv9.unlink()

        # Enable test hook to simulate failure (global already declared in test 7)
        _TEST_COMMIT_FAILURE_AFTER_CSV = True

        try:
            args9 = argparse.Namespace(
                input=str(input_csv),
                output=str(output_csv9),
                copies=1,
                encoding="utf-8",
                chunksize=2,
                date_column=DEFAULT_DATE_COLUMN,
                shift_years=0,
                normalize_whitespace=True,
                add_lineage_columns=False,
                manifest=str(manifest_csv9),
                overwrite=False,
                profile="engineering_reproducible",
            )

            try:
                build_dataset(args9)
                raise AssertionError("Should have raised RuntimeError due to simulated failure")
            except RuntimeError as exc:
                assert "Simulated manifest commit failure" in str(exc)

            # Verify rollback: files should not exist
            assert not output_csv9.exists(), "CSV should not exist after rollback"
            assert not manifest_csv9.exists(), "Manifest should not exist after rollback"

            # Verify no residual temp files or backups
            temp_files = list(test_dir.glob(".prepare_engineering_*"))
            assert len(temp_files) == 0, f"No temp files should remain, found: {temp_files}"

            print("Self-test 9 PASSED: first-time generation with manifest commit failure")
        finally:
            _TEST_COMMIT_FAILURE_AFTER_CSV = False

        # Test 10: Generation failure with existing files
        print("Running self-test 10: generation failure with existing files...")
        output_csv10 = test_dir / "test_output_gen_failure.csv"
        manifest_csv10 = test_dir / "test_output_gen_failure.csv.manifest.json"

        # Create initial files
        args10_init = argparse.Namespace(
            input=str(input_csv),
            output=str(output_csv10),
            copies=1,
            encoding="utf-8",
            chunksize=2,
            date_column=DEFAULT_DATE_COLUMN,
            shift_years=0,
            normalize_whitespace=True,
            add_lineage_columns=False,
            manifest=str(manifest_csv10),
            overwrite=False,
            profile="engineering_reproducible",
        )
        build_dataset(args10_init)

        # Record original content
        original_csv10 = output_csv10.read_bytes()
        original_manifest10 = manifest_csv10.read_bytes()

        # Enable test hook to simulate generation failure
        global _TEST_GENERATION_FAILURE
        _TEST_GENERATION_FAILURE = True

        try:
            args10_overwrite = argparse.Namespace(
                input=str(input_csv),
                output=str(output_csv10),
                copies=2,
                encoding="utf-8",
                chunksize=2,
                date_column=DEFAULT_DATE_COLUMN,
                shift_years=0,
                normalize_whitespace=True,
                add_lineage_columns=False,
                manifest=str(manifest_csv10),
                overwrite=True,
                profile="engineering_reproducible",
            )

            try:
                build_dataset(args10_overwrite)
                raise AssertionError("Should have raised RuntimeError due to generation failure")
            except RuntimeError as exc:
                assert "Simulated generation failure" in str(exc)

            # Verify original files unchanged
            assert output_csv10.exists(), "CSV should still exist"
            assert manifest_csv10.exists(), "Manifest should still exist"

            restored_csv10 = output_csv10.read_bytes()
            restored_manifest10 = manifest_csv10.read_bytes()

            assert restored_csv10 == original_csv10, "CSV should be unchanged"
            assert restored_manifest10 == original_manifest10, "Manifest should be unchanged"

            # Verify no residual temp files or backups
            temp_files = list(test_dir.glob(".prepare_engineering_*"))
            assert len(temp_files) == 0, f"No temp files should remain, found: {temp_files}"

            print("Self-test 10 PASSED: generation failure with existing files")
        finally:
            _TEST_GENERATION_FAILURE = False

        print("\nALL SELF-TESTS PASSED")
        print("\nDefault mode manifest:")
        print(json.dumps(manifest1, ensure_ascii=False, indent=2))
        print("\nLineage mode manifest:")
        print(json.dumps(manifest2, ensure_ascii=False, indent=2))
        print("\nCanonical mode manifest:")
        print(json.dumps(manifest3, ensure_ascii=False, indent=2))
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
            "Path to generated CSV. Default is dynamically generated based on profile: "
            "canonical -> retail_canonical.csv, "
            "engineering_reproducible -> retail_engineering_reproducible_<copies>x.csv. "
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
        "--profile",
        choices=VALID_PROFILES,
        default="engineering_reproducible",
        help=(
            "Data profile to generate. Determines purpose and limitations in manifest. "
            f"Valid values: {', '.join(VALID_PROFILES)} (default: engineering_reproducible)"
        ),
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
        help="Trim surrounding whitespace in text columns (forbidden for canonical)",
    )
    parser.add_argument(
        "--add-lineage-columns",
        action="store_true",
        help=(
            "Append source_copy_id and source_row_id columns. "
            "WARNING: When enabled, the Hive source table DDL must be updated "
            "to include these extra columns before loading. "
            "Forbidden for canonical profile."
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
        profile = getattr(args, "profile", "engineering_reproducible")
        args.output = os.path.join(
            "data", "generated", get_default_output_name(profile, args.copies)
        )

    try:
        manifest = build_dataset(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
