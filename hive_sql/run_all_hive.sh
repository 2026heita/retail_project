#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_all_hive.sh
# 功能: 按业务日期执行 Hive 完整主链路
# 流程:
#   源表 -> ODS Raw -> Reject/正常 ODS
#   -> ODS 入仓完整性门禁 -> ODS 内容质量检查
#   -> DWD -> DWD质量门禁
#   -> DWS -> ADS -> 结果质量门禁
#   -> 星型模型 -> 星型质量门禁
#   -> 结果展示
# 用法:
#   bash run_all_hive.sh 2026-04-08
#
# 可选环境变量:
#   HIVE_DATABASE  目标数据库，默认 default
#   BATCH_DT       ODS Raw 批次号，默认等于 BIZDATE
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 可选环境变量
HIVE_DATABASE="${HIVE_DATABASE:-default}"
BATCH_DT="${BATCH_DT:-${BIZDATE}}"
START_DT="${START_DT:-${BIZDATE}}"
END_DT="${END_DT:-${BIZDATE}}"
RUN_STAR="${RUN_STAR:-1}"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_all_hive.sh 2026-04-08"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    echo "Usage: bash run_all_hive.sh 2026-04-08"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

# 导出环境变量供子脚本使用
export HIVE_DATABASE
export BATCH_DT

run_hive_sql() {
    local step_name="$1"
    local sql_file="$2"

    echo "========================================"
    echo "${step_name}"
    echo "SQL: ${sql_file}"
    echo "bizdate: ${BIZDATE}"
    echo "batch_dt: ${BATCH_DT}"
    echo "database: ${HIVE_DATABASE}"
    echo "========================================"

    if [ ! -f "${sql_file}" ]; then
        echo "ERROR: SQL file not found: ${sql_file}"
        exit 1
    fi

    if ! hive \
        --database "${HIVE_DATABASE}" \
        --hiveconf bizdate="${BIZDATE}" \
        --hiveconf batch_dt="${BATCH_DT}" \
        --hiveconf start_dt="${START_DT}" \
        --hiveconf end_dt="${END_DT}" \
        -f "${sql_file}"
    then
        echo "ERROR: failed at ${step_name}"
        echo "ERROR SQL: ${sql_file}"
        exit 1
    fi
}

run_dwd_quality_gate() {
    local gate_script="${BASE_DIR}/run_quality_gate_hive.sh"

    echo "========================================"
    echo "[11/20] Run DWD quality gate"
    echo "script: ${gate_script}"
    echo "bizdate: ${BIZDATE}"
    echo "========================================"

    if [ ! -f "${gate_script}" ]; then
        echo "ERROR: DWD quality gate script not found: ${gate_script}"
        exit 1
    fi

    if ! bash "${gate_script}" "${BIZDATE}"; then
        echo "ERROR: DWD quality gate failed."
        echo "Stop downstream tasks."
        exit 1
    fi
}

run_result_quality_gate() {
    local gate_script="${BASE_DIR}/run_result_quality_gate_hive.sh"

    echo "========================================"
    echo "[18/20] Run DWS/ADS result quality gate"
    echo "script: ${gate_script}"
    echo "bizdate: ${BIZDATE}"
    echo "========================================"

    if [ ! -f "${gate_script}" ]; then
        echo "ERROR: result quality gate script not found: ${gate_script}"
        exit 1
    fi

    if ! bash "${gate_script}" "${BIZDATE}"; then
        echo "ERROR: DWS/ADS result quality gate failed."
        echo "Stop star schema tasks."
        exit 1
    fi
}

run_star_schema() {
    local star_script="${BASE_DIR}/run_star_schema_hive.sh"

    echo "========================================"
    echo "[19/20] Build and validate star schema"
    echo "script: ${star_script}"
    echo "bizdate: ${BIZDATE}"
    echo "========================================"

    if [ ! -f "${star_script}" ]; then
        echo "ERROR: star schema script not found: ${star_script}"
        exit 1
    fi

    if ! bash "${star_script}" "${BIZDATE}"; then
        echo "ERROR: star schema pipeline failed or was blocked."
        exit 1
    fi
}

echo "========================================"
echo "Start Hive complete warehouse job"
echo "bizdate: ${BIZDATE}"
echo "batch_dt: ${BATCH_DT}"
echo "database: ${HIVE_DATABASE}"
echo "base_dir: ${BASE_DIR}"
echo "========================================"

run_hive_sql "[01/20] Create ODS Raw table" \
    "${BASE_DIR}/00_ods_retail_raw_hive.sql"

run_hive_sql "[02/20] Create ODS Reject table" \
    "${BASE_DIR}/00_ods_retail_reject_hive.sql"

run_hive_sql "[03/20] Create normal ODS table" \
    "${BASE_DIR}/00_ods_retail_hive.sql"

run_hive_sql "[04/20] Load ODS Raw partition" \
    "${BASE_DIR}/00_load_ods_retail_raw_hive.sql"

run_hive_sql "[05/20] Load ODS Reject partition" \
    "${BASE_DIR}/00_load_ods_retail_reject_hive.sql"

run_hive_sql "[06/20] Load normal ODS partition" \
    "${BASE_DIR}/00_load_ods_retail_hive.sql"

run_hive_sql "[07/20] Run ODS ingestion quality gate" \
    "${BASE_DIR}/10_check_ods_ingestion_hive.sql"

run_hive_sql "[08/20] Check ODS data content" \
    "${BASE_DIR}/10_check_ods_retail_hive.sql"

run_hive_sql "[09/20] Create DWD table" \
    "${BASE_DIR}/01_dwd_retail_clean_hive.sql"

run_hive_sql "[10/20] Load DWD partition" \
    "${BASE_DIR}/02_load_dwd_retail_clean_hive.sql"

run_dwd_quality_gate

run_hive_sql "[12/20] Build DWS customer value" \
    "${BASE_DIR}/03_dws_customer_value_hive.sql"

run_hive_sql "[13/20] Build DWS sales summary" \
    "${BASE_DIR}/04_dws_sales_summary_hive.sql"

run_hive_sql "[14/20] Build ADS high-value contribution" \
    "${BASE_DIR}/05_ads_high_value_customer_sales_contribution_hive.sql"

run_hive_sql "[15/20] Build ADS customer-level distribution" \
    "${BASE_DIR}/06_ads_customer_level_distribution_hive.sql"

run_hive_sql "[16/20] Build ADS country sales rank" \
    "${BASE_DIR}/07_ads_country_sales_rank_hive.sql"

run_hive_sql "[17/20] Build ADS customer preference" \
    "${BASE_DIR}/08_ads_high_value_customer_preference_hive.sql"

run_result_quality_gate

if [ "${RUN_STAR}" = "1" ]; then
    run_star_schema
else
    echo "========================================"
    echo "[19/20] Skip star schema"
    echo "RUN_STAR=${RUN_STAR}"
    echo "========================================"
fi

run_hive_sql "[20/20] Display warehouse results" \
    "${BASE_DIR}/09_check_hive_result.sql"

echo "========================================"
echo "Hive complete warehouse job finished successfully"
echo "bizdate: ${BIZDATE}"
echo "========================================"
