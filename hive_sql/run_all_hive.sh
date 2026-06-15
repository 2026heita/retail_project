#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_all_hive.sh
# 功能: 按业务日期执行 Hive 主链路（ODS -> DWD -> 质量日志 -> DWS -> ADS -> 结果校验）
# 用法:
#   bash run_all_hive.sh 2026-04-08
#
# 说明:
#   1. 这是项目主执行脚本，保留 00-09 的 ODS-DWD-DWS-ADS 主链路口径。
#   2. 10_check_ods_retail_hive.sql 是 ODS 入仓校验，安排在 ODS 加载后执行。
#   3. 每一步执行前检查 SQL 文件是否存在，每一步执行后检查返回状态。
#   4. DWD 加载完成后写入 quality_log_hive，记录数据质量检查结果。
#   5. 如果 quality_log_hive 中存在 FAIL，则立即退出，避免错误数据进入 DWS / ADS。
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$BIZDATE" ]; then
  echo "ERROR: bizdate is required."
  echo "Usage: bash run_all_hive.sh 2026-04-08"
  exit 1
fi

if ! date -d "$BIZDATE" +%F >/dev/null 2>&1; then
  echo "ERROR: invalid bizdate: $BIZDATE"
  echo "Usage: bash run_all_hive.sh 2026-04-08"
  exit 1
fi

BIZDATE="$(date -d "$BIZDATE" +%F)"

run_hive_sql() {
  local STEP_NAME="$1"
  local SQL_FILE="$2"

  echo "========================================"
  echo "$STEP_NAME"
  echo "SQL: $SQL_FILE"
  echo "bizdate: ${BIZDATE}"
  echo "========================================"

  if [ ! -f "$SQL_FILE" ]; then
    echo "ERROR: SQL file not found: $SQL_FILE"
    exit 1
  fi

  if ! hive --hiveconf bizdate="${BIZDATE}" -f "$SQL_FILE"; then
    echo "ERROR: failed at $STEP_NAME"
    echo "ERROR SQL: $SQL_FILE"
    exit 1
  fi
}

check_quality_log() {
  echo "========================================"
  echo "[QUALITY CHECK] Check quality_log_hive"
  echo "bizdate: ${BIZDATE}"
  echo "========================================"

  local FAILED_COUNT

  FAILED_COUNT=$(
    hive -S --hiveconf bizdate="${BIZDATE}" -e "
      SELECT COUNT(1)
      FROM quality_log_hive
      WHERE dt='${BIZDATE}'
        AND check_status='FAIL';
    " | grep -E '^[0-9]+$' | tail -n 1
  )

  if [ -z "${FAILED_COUNT}" ]; then
    echo "ERROR: failed to read quality check result from quality_log_hive."
    exit 1
  fi

  if [ "${FAILED_COUNT}" -ne 0 ]; then
    echo "ERROR: data quality check failed."
    echo "ERROR: failed_count=${FAILED_COUNT}"
    echo "Please check table quality_log_hive where dt='${BIZDATE}'."
    exit 1
  fi

  echo "Data quality check passed."
}

echo "========================================"
echo "Start Hive main warehouse job"
echo "bizdate: ${BIZDATE}"
echo "base_dir: ${BASE_DIR}"
echo "========================================"

run_hive_sql "[01/14] Create ODS table" \
  "$BASE_DIR/00_ods_retail_hive.sql"

run_hive_sql "[02/14] Load ODS partition" \
  "$BASE_DIR/00_load_ods_retail_hive.sql"

run_hive_sql "[03/14] Check ODS partition" \
  "$BASE_DIR/10_check_ods_retail_hive.sql"

run_hive_sql "[04/14] Create DWD table" \
  "$BASE_DIR/01_dwd_retail_clean_hive.sql"

run_hive_sql "[05/14] Load DWD partition" \
  "$BASE_DIR/02_load_dwd_retail_clean_hive.sql"

run_hive_sql "[06/14] Create quality log table" \
  "$BASE_DIR/23_quality_log_hive.sql"

run_hive_sql "[07/14] Load quality log" \
  "$BASE_DIR/24_load_quality_log_hive.sql"

check_quality_log

run_hive_sql "[08/14] Build DWS customer value" \
  "$BASE_DIR/03_dws_customer_value_hive.sql"

run_hive_sql "[09/14] Build DWS sales summary" \
  "$BASE_DIR/04_dws_sales_summary_hive.sql"

run_hive_sql "[10/14] Build ADS high value customer contribution" \
  "$BASE_DIR/05_ads_high_value_customer_sales_contribution_hive.sql"

run_hive_sql "[11/14] Build ADS customer level distribution" \
  "$BASE_DIR/06_ads_customer_level_distribution_hive.sql"

run_hive_sql "[12/14] Build ADS country sales rank" \
  "$BASE_DIR/07_ads_country_sales_rank_hive.sql"

run_hive_sql "[13/14] Build ADS high value customer preference" \
  "$BASE_DIR/08_ads_high_value_customer_preference_hive.sql"

run_hive_sql "[14/14] Check Hive result" \
  "$BASE_DIR/09_check_hive_result.sql"

echo "========================================"
echo "Hive main warehouse job finished successfully"
echo "bizdate: ${BIZDATE}"
echo "========================================"