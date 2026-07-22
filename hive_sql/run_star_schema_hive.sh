#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_star_schema_hive.sh
# 功能: 构建指定业务日期的星型模型，并执行质量门禁
# 用法:
#   bash run_star_schema_hive.sh 2026-04-08
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_star_schema_hive.sh YYYY-MM-DD"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

run_hive_sql() {
    local step_name="$1"
    local sql_file="$2"
    local sql_path="${BASE_DIR}/${sql_file}"

    if [ ! -f "${sql_path}" ]; then
        echo "ERROR: SQL file not found: ${sql_path}"
        exit 1
    fi

    echo
    echo "========================================"
    echo "${step_name}"
    echo "SQL: ${sql_file}"
    echo "bizdate: ${BIZDATE}"
    echo "========================================"

    if ! hive \
        --hiveconf bizdate="${BIZDATE}" \
        -f "${sql_path}"; then
        echo "ERROR: ${step_name} failed."
        echo "ERROR SQL: ${sql_path}"
        exit 1
    fi
}

echo "========================================"
echo "Start star schema pipeline"
echo "bizdate: ${BIZDATE}"
echo "========================================"

run_hive_sql "[01/13] Create SCD2 user dimension" \
    "11_dim_user_scd2_hive.sql"

run_hive_sql "[02/13] Load SCD2 user dimension partition" \
    "12_load_dim_user_scd2_hive.sql"

run_hive_sql "[03/13] Create product dimension" \
    "13_dim_product_hive.sql"

run_hive_sql "[04/13] Load product dimension partition" \
    "14_load_dim_product_hive.sql"

run_hive_sql "[05/13] Create date dimension" \
    "19_dim_date_hive.sql"

run_hive_sql "[06/13] Load date dimension partition" \
    "22_load_dim_date_hive.sql"

run_hive_sql "[07/13] Create geography dimension" \
    "20_dim_geo_hive.sql"

run_hive_sql "[08/13] Load geography dimension partition" \
    "21_load_dim_geo_hive.sql"

run_hive_sql "[09/13] Create order fact table" \
    "15_fact_order_hive.sql"

run_hive_sql "[10/13] Load order fact partition" \
    "16_load_fact_order_hive.sql"

run_hive_sql "[11/13] Create star DWS customer value table" \
    "17_dws_customer_value_star_hive.sql"

run_hive_sql "[12/13] Load star DWS customer value partition" \
    "18_load_dws_customer_value_star_hive.sql"

echo
echo "========================================"
echo "[13/13] Run star schema quality gate"
echo "bizdate: ${BIZDATE}"
echo "========================================"

if [ ! -f "${BASE_DIR}/run_star_quality_gate_hive.sh" ]; then
    echo "ERROR: quality gate script not found:"
    echo "${BASE_DIR}/run_star_quality_gate_hive.sh"
    exit 1
fi

if ! bash "${BASE_DIR}/run_star_quality_gate_hive.sh" "${BIZDATE}"; then
    echo "ERROR: star schema pipeline blocked by quality gate."
    exit 1
fi

echo
echo "========================================"
echo "Star schema pipeline completed successfully."
echo "bizdate: ${BIZDATE}"
echo "========================================"
