#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_daily_hive_profiled.sh
# 功能:
#   1. 执行日常 Hive 数仓完整链路
#   2. 跳过已经完成的一次性独立建表步骤
#   3. 默认跳过详细样例展示，减少无意义扫描和终端输出
#   4. 记录每个任务和总链路耗时，定位真正瓶颈
#
# 用法:
#   完整日常链路:
#     bash run_daily_hive_profiled.sh 2026-04-08
#
#   从某阶段开始，用于修改后局部重跑:
#     bash run_daily_hive_profiled.sh 2026-04-08 dwd
#     bash run_daily_hive_profiled.sh 2026-04-08 mart
#     bash run_daily_hive_profiled.sh 2026-04-08 star
#
# 可选环境变量:
#   RUN_REPORTS=1  执行详细 ODS 检查和最终结果展示，默认 0
#   RUN_STAR=0     临时跳过星型模型，默认 1
# =====================================================

BIZDATE="${1:-}"
START_STAGE="${2:-ods}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${BASE_DIR}/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/logs"
RUN_REPORTS="${RUN_REPORTS:-0}"
RUN_STAR="${RUN_STAR:-1}"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_daily_hive_profiled.sh YYYY-MM-DD [ods|dwd|mart|star|report]"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

case "${START_STAGE}" in
    ods)    START_STAGE_NO=1 ;;
    dwd)    START_STAGE_NO=2 ;;
    mart)   START_STAGE_NO=3 ;;
    star)   START_STAGE_NO=4 ;;
    report) START_STAGE_NO=5 ;;
    *)
        echo "ERROR: invalid start stage: ${START_STAGE}"
        echo "Allowed: ods | dwd | mart | star | report"
        exit 1
        ;;
esac

BIZDATE="$(date -d "${BIZDATE}" +%F)"
RUN_ID="$(date '+%Y%m%d_%H%M%S')"
mkdir -p "${LOG_DIR}"

TIMING_FILE="${LOG_DIR}/hive_timing_${BIZDATE}_${RUN_ID}.tsv"
RUN_LOG="${LOG_DIR}/hive_run_${BIZDATE}_${RUN_ID}.log"

printf "step\tseconds\tstatus\n" > "${TIMING_FILE}"

TOTAL_START="$(date +%s)"

record_timing() {
    local step_name="$1"
    local seconds="$2"
    local status="$3"
    printf "%s\t%s\t%s\n" "${step_name}" "${seconds}" "${status}" >> "${TIMING_FILE}"
}

run_hive_sql() {
    local step_name="$1"
    local sql_file="$2"
    local start_ts end_ts elapsed

    if [ ! -f "${sql_file}" ]; then
        echo "ERROR: SQL file not found: ${sql_file}" | tee -a "${RUN_LOG}"
        record_timing "${step_name}" "0" "FAILED_FILE_NOT_FOUND"
        exit 1
    fi

    echo | tee -a "${RUN_LOG}"
    echo "========================================" | tee -a "${RUN_LOG}"
    echo "${step_name}" | tee -a "${RUN_LOG}"
    echo "SQL: ${sql_file}" | tee -a "${RUN_LOG}"
    echo "bizdate: ${BIZDATE}" | tee -a "${RUN_LOG}"
    echo "========================================" | tee -a "${RUN_LOG}"

    start_ts="$(date +%s)"

    if hive \
        --hiveconf bizdate="${BIZDATE}" \
        -f "${sql_file}" 2>&1 | tee -a "${RUN_LOG}"
    then
        end_ts="$(date +%s)"
        elapsed=$((end_ts - start_ts))
        record_timing "${step_name}" "${elapsed}" "SUCCESS"
        echo "STEP SUCCESS: ${elapsed}s" | tee -a "${RUN_LOG}"
    else
        end_ts="$(date +%s)"
        elapsed=$((end_ts - start_ts))
        record_timing "${step_name}" "${elapsed}" "FAILED"
        echo "ERROR: failed at ${step_name}, elapsed=${elapsed}s" | tee -a "${RUN_LOG}"
        exit 1
    fi
}

run_shell_task() {
    local step_name="$1"
    local script_file="$2"
    local start_ts end_ts elapsed

    if [ ! -f "${script_file}" ]; then
        echo "ERROR: script not found: ${script_file}" | tee -a "${RUN_LOG}"
        record_timing "${step_name}" "0" "FAILED_FILE_NOT_FOUND"
        exit 1
    fi

    echo | tee -a "${RUN_LOG}"
    echo "========================================" | tee -a "${RUN_LOG}"
    echo "${step_name}" | tee -a "${RUN_LOG}"
    echo "Script: ${script_file}" | tee -a "${RUN_LOG}"
    echo "bizdate: ${BIZDATE}" | tee -a "${RUN_LOG}"
    echo "========================================" | tee -a "${RUN_LOG}"

    start_ts="$(date +%s)"

    if bash "${script_file}" "${BIZDATE}" 2>&1 | tee -a "${RUN_LOG}"
    then
        end_ts="$(date +%s)"
        elapsed=$((end_ts - start_ts))
        record_timing "${step_name}" "${elapsed}" "SUCCESS"
        echo "STEP SUCCESS: ${elapsed}s" | tee -a "${RUN_LOG}"
    else
        end_ts="$(date +%s)"
        elapsed=$((end_ts - start_ts))
        record_timing "${step_name}" "${elapsed}" "FAILED"
        echo "ERROR: failed at ${step_name}, elapsed=${elapsed}s" | tee -a "${RUN_LOG}"
        exit 1
    fi
}

echo "========================================" | tee -a "${RUN_LOG}"
echo "Start profiled Hive daily warehouse job" | tee -a "${RUN_LOG}"
echo "bizdate: ${BIZDATE}" | tee -a "${RUN_LOG}"
echo "start_stage: ${START_STAGE}" | tee -a "${RUN_LOG}"
echo "run_reports: ${RUN_REPORTS}" | tee -a "${RUN_LOG}"
echo "run_star: ${RUN_STAR}" | tee -a "${RUN_LOG}"
echo "timing_file: ${TIMING_FILE}" | tee -a "${RUN_LOG}"
echo "========================================" | tee -a "${RUN_LOG}"


# -----------------------------------------------------
# Stage 1: ODS
# 已存在的表不在日常任务中重复单独执行建表脚本
# -----------------------------------------------------
if [ "${START_STAGE_NO}" -le 1 ]; then
    run_hive_sql "01_load_ods_raw" \
        "${BASE_DIR}/00_load_ods_retail_raw_hive.sql"

    run_hive_sql "02_load_ods_reject" \
        "${BASE_DIR}/00_load_ods_retail_reject_hive.sql"

    run_hive_sql "03_load_ods_normal" \
        "${BASE_DIR}/00_load_ods_retail_hive.sql"

    run_hive_sql "04_ods_ingestion_gate" \
        "${BASE_DIR}/10_check_ods_ingestion_hive.sql"

    if [ "${RUN_REPORTS}" = "1" ]; then
        run_hive_sql "05_ods_detailed_report" \
            "${BASE_DIR}/10_check_ods_retail_hive.sql"
    fi
fi


# -----------------------------------------------------
# Stage 2: DWD
# -----------------------------------------------------
if [ "${START_STAGE_NO}" -le 2 ]; then
    run_hive_sql "06_load_dwd" \
        "${BASE_DIR}/02_load_dwd_retail_clean_hive.sql"

    run_shell_task "07_dwd_quality_gate" \
        "${BASE_DIR}/run_quality_gate_hive.sh"
fi


# -----------------------------------------------------
# Stage 3: DWS / ADS
# -----------------------------------------------------
if [ "${START_STAGE_NO}" -le 3 ]; then
    run_hive_sql "08_build_dws_customer_value" \
        "${BASE_DIR}/03_dws_customer_value_hive.sql"

    run_hive_sql "09_build_dws_sales_summary" \
        "${BASE_DIR}/04_dws_sales_summary_hive.sql"

    run_hive_sql "10_build_ads_high_value_contribution" \
        "${BASE_DIR}/05_ads_high_value_customer_sales_contribution_hive.sql"

    run_hive_sql "11_build_ads_customer_level_distribution" \
        "${BASE_DIR}/06_ads_customer_level_distribution_hive.sql"

    run_hive_sql "12_build_ads_country_sales_rank" \
        "${BASE_DIR}/07_ads_country_sales_rank_hive.sql"

    run_hive_sql "13_build_ads_customer_preference" \
        "${BASE_DIR}/08_ads_high_value_customer_preference_hive.sql"

    run_shell_task "14_result_quality_gate" \
        "${BASE_DIR}/run_result_quality_gate_hive.sh"
fi


# -----------------------------------------------------
# Stage 4: Star schema
# -----------------------------------------------------
if [ "${START_STAGE_NO}" -le 4 ] && [ "${RUN_STAR}" = "1" ]; then
    run_shell_task "15_star_schema_pipeline" \
        "${BASE_DIR}/run_star_schema_hive.sh"
fi


# -----------------------------------------------------
# Stage 5: Optional report
# -----------------------------------------------------
if [ "${RUN_REPORTS}" = "1" ] && [ "${START_STAGE_NO}" -le 5 ]; then
    run_hive_sql "16_final_result_report" \
        "${BASE_DIR}/09_check_hive_result.sql"
fi


TOTAL_END="$(date +%s)"
TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))
record_timing "TOTAL_PIPELINE" "${TOTAL_ELAPSED}" "SUCCESS"

echo | tee -a "${RUN_LOG}"
echo "========================================" | tee -a "${RUN_LOG}"
echo "Hive daily warehouse job finished successfully" | tee -a "${RUN_LOG}"
echo "total_seconds: ${TOTAL_ELAPSED}" | tee -a "${RUN_LOG}"
echo "timing_file: ${TIMING_FILE}" | tee -a "${RUN_LOG}"
echo "run_log: ${RUN_LOG}" | tee -a "${RUN_LOG}"
echo "========================================" | tee -a "${RUN_LOG}"

echo
echo "耗时汇总（从慢到快）:"
if command -v column >/dev/null 2>&1; then
    {
        head -n 1 "${TIMING_FILE}"
        tail -n +2 "${TIMING_FILE}" | sort -t $'\t' -k2,2nr
    } | column -t -s $'\t'
else
    head -n 1 "${TIMING_FILE}"
    tail -n +2 "${TIMING_FILE}" | sort -t $'\t' -k2,2nr
fi
