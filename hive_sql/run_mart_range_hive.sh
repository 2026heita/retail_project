#!/bin/bash
set -Eeuo pipefail

# =====================================================
# File: run_mart_range_hive.sh
# Purpose: Execute DWS/ADS range processing
# Usage:
#   HIVE_DATABASE=retail_canonical \
#   bash run_mart_range_hive.sh 2009-12-01 2009-12-31
# Args:
#   $1 - start_dt (required)
#   $2 - end_dt (required)
# Environment:
#   HIVE_DATABASE      Target database, default: default
#   MAP_MEMORY_MB      Mapper memory, default: 2048
#   MAP_JAVA_XMX       Mapper JVM heap, default: 1536m
#   REDUCE_MEMORY_MB   Reducer memory, default: 2048
#   REDUCE_JAVA_XMX    Reducer JVM heap, default: 1536m
#   TASK_TIMEOUT_MS    Task timeout, default: 3600000
# =====================================================

START_DT="${1:-}"
END_DT="${2:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Database configuration
HIVE_DATABASE="${HIVE_DATABASE:-default}"

# Resource configuration
MAP_MEMORY_MB="${MAP_MEMORY_MB:-2048}"
MAP_JAVA_XMX="${MAP_JAVA_XMX:-1536m}"
REDUCE_MEMORY_MB="${REDUCE_MEMORY_MB:-2048}"
REDUCE_JAVA_XMX="${REDUCE_JAVA_XMX:-1536m}"
TASK_TIMEOUT_MS="${TASK_TIMEOUT_MS:-3600000}"

# --- Validate dates ---
if [ -z "${START_DT}" ] || [ -z "${END_DT}" ]; then
    echo "ERROR: start_dt and end_dt are required."
    echo "Usage: bash run_mart_range_hive.sh YYYY-MM-DD YYYY-MM-DD"
    exit 1
fi

if ! date -d "${START_DT}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid start_dt: ${START_DT}"
    exit 1
fi

if ! date -d "${END_DT}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid end_dt: ${END_DT}"
    exit 1
fi

START_DT="$(date -d "${START_DT}" +%F)"
END_DT="$(date -d "${END_DT}" +%F)"

# Validate start_dt <= end_dt
if [[ "${START_DT}" > "${END_DT}" ]]; then
    echo "ERROR: start_dt must be <= end_dt"
    echo "start_dt: ${START_DT}"
    echo "end_dt: ${END_DT}"
    exit 1
fi

# --- Export for sub-scripts ---
export HIVE_DATABASE
export START_DT
export END_DT

# --- Helper: run a single Hive SQL file ---
run_hive_sql() {
    local step_name="$1"
    local sql_file="$2"
    local start_ts end_ts elapsed

    echo "========================================"
    echo "${step_name}"
    echo "SQL: ${sql_file}"
    echo "start_dt: ${START_DT}"
    echo "end_dt: ${END_DT}"
    echo "database: ${HIVE_DATABASE}"
    echo "========================================"

    if [ ! -f "${sql_file}" ]; then
        echo "ERROR: SQL file not found: ${sql_file}"
        exit 1
    fi

    start_ts="$(date +%s)"

    if hive \
        --database "${HIVE_DATABASE}" \
        --hiveconf start_dt="${START_DT}" \
        --hiveconf end_dt="${END_DT}" \
        --hiveconf mapreduce.map.memory.mb="${MAP_MEMORY_MB}" \
        --hiveconf mapreduce.map.java.opts="-Xmx${MAP_JAVA_XMX}" \
        --hiveconf mapreduce.reduce.memory.mb="${REDUCE_MEMORY_MB}" \
        --hiveconf mapreduce.reduce.java.opts="-Xmx${REDUCE_JAVA_XMX}" \
        --hiveconf mapreduce.task.timeout="${TASK_TIMEOUT_MS}" \
        -f "${sql_file}"
    then
        end_ts="$(date +%s)"
        elapsed=$((end_ts - start_ts))
        echo "SUCCESS: ${step_name} completed in ${elapsed}s"
    else
        end_ts="$(date +%s)"
        elapsed=$((end_ts - start_ts))
        echo "ERROR: failed at ${step_name}, elapsed=${elapsed}s"
        echo "ERROR SQL: ${sql_file}"
        exit 1
    fi
}

echo "========================================"
echo "Start DWS/ADS range processing"
echo "start_dt: ${START_DT}"
echo "end_dt: ${END_DT}"
echo "database: ${HIVE_DATABASE}"
echo "base_dir: ${BASE_DIR}"
echo "map_memory_mb: ${MAP_MEMORY_MB}"
echo "reduce_memory_mb: ${REDUCE_MEMORY_MB}"
echo "========================================"

# --- Step 1: DWS customer value ---
run_hive_sql "[1/7] Build DWS customer value" \
    "${BASE_DIR}/03_dws_customer_value_hive.sql"

# --- Step 2: DWS sales summary ---
run_hive_sql "[2/7] Build DWS sales summary" \
    "${BASE_DIR}/04_dws_sales_summary_hive.sql"

# --- Step 3: ADS high-value contribution ---
run_hive_sql "[3/7] Build ADS high-value contribution" \
    "${BASE_DIR}/05_ads_high_value_customer_sales_contribution_hive.sql"

# --- Step 4: ADS customer level distribution ---
run_hive_sql "[4/7] Build ADS customer level distribution" \
    "${BASE_DIR}/06_ads_customer_level_distribution_hive.sql"

# --- Step 5: ADS country sales rank ---
run_hive_sql "[5/7] Build ADS country sales rank" \
    "${BASE_DIR}/07_ads_country_sales_rank_hive.sql"

# --- Step 6: ADS customer preference ---
run_hive_sql "[6/7] Build ADS customer preference" \
    "${BASE_DIR}/08_ads_high_value_customer_preference_hive.sql"

# --- Step 7: Range validation ---
run_hive_sql "[7/7] Run DWS/ADS range validation" \
    "${BASE_DIR}/33_dws_ads_range_validation_hive.sql"

echo "========================================"
echo "DWS/ADS range processing completed successfully"
echo "start_dt: ${START_DT}"
echo "end_dt: ${END_DT}"
echo "database: ${HIVE_DATABASE}"
echo "========================================"
