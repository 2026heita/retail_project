#!/bin/bash
set -Eeuo pipefail

# =====================================================
# File: run_canonical_ods_load.sh
# Purpose: One-time canonical ODS full load
# Usage:
#   bash run_canonical_ods_load.sh 2026-08-04 retail_canonical
# Args:
#   $1 - batch_dt (required, e.g. 2026-08-04)
#   $2 - database (optional, default: retail_canonical)
# =====================================================

BATCH_DT="${1:-}"
HIVE_DATABASE="${2:-retail_canonical}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Validate batch_dt ---
if [ -z "${BATCH_DT}" ]; then
    echo "ERROR: batch_dt is required."
    echo "Usage: bash run_canonical_ods_load.sh YYYY-MM-DD [database]"
    exit 1
fi

if ! date -d "${BATCH_DT}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid batch_dt: ${BATCH_DT}"
    exit 1
fi

BATCH_DT="$(date -d "${BATCH_DT}" +%F)"

# --- Normalize database name to lowercase and reject default ---
HIVE_DATABASE="$(echo "${HIVE_DATABASE}" | tr '[:upper:]' '[:lower:]')"

if [ "${HIVE_DATABASE}" = "default" ]; then
    echo "ERROR: database cannot be 'default'."
    echo "This script is for canonical data only."
    echo "Use a dedicated database like 'retail_canonical'."
    exit 1
fi

# --- Export for sub-scripts ---
export HIVE_DATABASE
export BATCH_DT

# --- Helper: run a single Hive SQL file ---
run_hive_sql() {
    local step_name="$1"
    local sql_file="$2"

    echo "========================================"
    echo "${step_name}"
    echo "SQL: ${sql_file}"
    echo "batch_dt: ${BATCH_DT}"
    echo "database: ${HIVE_DATABASE}"
    echo "========================================"

    if [ ! -f "${sql_file}" ]; then
        echo "ERROR: SQL file not found: ${sql_file}"
        exit 1
    fi

    if ! hive \
        --database "${HIVE_DATABASE}" \
        --hiveconf batch_dt="${BATCH_DT}" \
        --hiveconf bizdate="${BATCH_DT}" \
        -f "${sql_file}"; then
        echo "ERROR: failed at ${step_name}"
        echo "ERROR SQL: ${sql_file}"
        exit 1
    fi
}

# --- Pre-flight: verify database exists ---
echo "========================================"
echo "Start canonical ODS full load"
echo "batch_dt: ${BATCH_DT}"
echo "database: ${HIVE_DATABASE}"
echo "base_dir: ${BASE_DIR}"
echo "========================================"

echo "Verifying database exists: ${HIVE_DATABASE}"
if ! hive -S -e "DESCRIBE DATABASE ${HIVE_DATABASE};" >/dev/null 2>&1; then
    echo "ERROR: database does not exist: ${HIVE_DATABASE}"
    exit 1
fi

# --- Pre-flight: verify retail source table exists ---
echo "Verifying retail source table exists in: ${HIVE_DATABASE}"
if ! hive -S --database "${HIVE_DATABASE}" -e "DESCRIBE retail;" >/dev/null 2>&1; then
    echo "ERROR: retail source table does not exist in: ${HIVE_DATABASE}"
    exit 1
fi

# --- Step 1: Create ODS Raw table ---
run_hive_sql "[1/7] Create ODS Raw table" \
    "${BASE_DIR}/00_ods_retail_raw_hive.sql"

# --- Step 2: Create ODS Reject table ---
run_hive_sql "[2/7] Create ODS Reject table" \
    "${BASE_DIR}/00_ods_retail_reject_hive.sql"

# --- Step 3: Create normal ODS table ---
run_hive_sql "[3/7] Create normal ODS table" \
    "${BASE_DIR}/00_ods_retail_hive.sql"

# --- Step 4: Load ODS Raw (once) ---
run_hive_sql "[4/7] Load ODS Raw partition" \
    "${BASE_DIR}/00_load_ods_retail_raw_hive.sql"

# --- Step 5: Load ODS Reject (once) ---
run_hive_sql "[5/7] Load ODS Reject partition" \
    "${BASE_DIR}/00_load_ods_retail_reject_hive.sql"

# --- Step 6: Load all business dates via dynamic partition (once) ---
run_hive_sql "[6/7] Load all dates to normal ODS (dynamic partition)" \
    "${BASE_DIR}/00_load_ods_retail_all_dates_hive.sql"

# --- Step 7: Run canonical quality check ---
run_hive_sql "[7/7] Run canonical batch quality check" \
    "${BASE_DIR}/10_check_ods_canonical_batch_hive.sql"

echo "========================================"
echo "Canonical ODS full load completed successfully"
echo "batch_dt: ${BATCH_DT}"
echo "database: ${HIVE_DATABASE}"
echo "========================================"
