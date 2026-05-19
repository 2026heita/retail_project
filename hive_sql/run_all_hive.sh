#!/bin/bash

# =====================================================
# 文件名: run_all_hive.sh
# 功能: 按业务日期执行 Hive 主链路（ODS -> DWD -> DWS -> ADS -> 结果校验）
# 用法:
#   sh run_all_hive.sh 2026-04-08
#
# 说明:
#   1. 这是项目主执行脚本，保留 00-09 的 ODS-DWD-DWS-ADS 主链路口径。
#   2. 10_check_ods_retail_hive.sql 是 ODS 入仓校验，安排在 ODS 加载后执行。
#   3. 每一步执行前检查 SQL 文件是否存在，每一步执行后检查返回状态。
#   4. 任一步骤失败时立即退出，避免错误数据继续向下游扩散。
# =====================================================

BIZDATE=$1
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$BIZDATE" ]; then
  echo "ERROR: bizdate is required."
  echo "Usage: sh run_all_hive.sh 2026-04-08"
  exit 1
fi

if ! date -d "$BIZDATE" +%F >/dev/null 2>&1; then
  echo "ERROR: invalid bizdate: $BIZDATE"
  echo "Usage: sh run_all_hive.sh 2026-04-08"
  exit 1
fi

BIZDATE="$(date -d "$BIZDATE" +%F)"

run_hive_sql() {
  STEP_NAME=$1
  SQL_FILE=$2

  echo "========================================"
  echo "$STEP_NAME"
  echo "SQL: $SQL_FILE"
  echo "bizdate: ${BIZDATE}"
  echo "========================================"

  if [ ! -f "$SQL_FILE" ]; then
    echo "ERROR: SQL file not found: $SQL_FILE"
    exit 1
  fi

  hive --hiveconf bizdate="${BIZDATE}" -f "$SQL_FILE"

  if [ $? -ne 0 ]; then
    echo "ERROR: failed at $STEP_NAME"
    echo "ERROR SQL: $SQL_FILE"
    exit 1
  fi
}

echo "========================================"
echo "Start Hive main warehouse job"
echo "bizdate: ${BIZDATE}"
echo "base_dir: ${BASE_DIR}"
echo "========================================"

run_hive_sql "[01/12] Create ODS table" \
  "$BASE_DIR/00_ods_retail_hive.sql"

run_hive_sql "[02/12] Load ODS partition" \
  "$BASE_DIR/00_load_ods_retail_hive.sql"

run_hive_sql "[03/12] Check ODS partition" \
  "$BASE_DIR/10_check_ods_retail_hive.sql"

run_hive_sql "[04/12] Create DWD table" \
  "$BASE_DIR/01_dwd_retail_clean_hive.sql"

run_hive_sql "[05/12] Load DWD partition" \
  "$BASE_DIR/02_load_dwd_retail_clean_hive.sql"

run_hive_sql "[06/12] Build DWS customer value" \
  "$BASE_DIR/03_dws_customer_value_hive.sql"

run_hive_sql "[07/12] Build DWS sales summary" \
  "$BASE_DIR/04_dws_sales_summary_hive.sql"

run_hive_sql "[08/12] Build ADS high value customer contribution" \
  "$BASE_DIR/05_ads_high_value_customer_sales_contribution_hive.sql"

run_hive_sql "[09/12] Build ADS customer level distribution" \
  "$BASE_DIR/06_ads_customer_level_distribution_hive.sql"

run_hive_sql "[10/12] Build ADS country sales rank" \
  "$BASE_DIR/07_ads_country_sales_rank_hive.sql"

run_hive_sql "[11/12] Build ADS high value customer preference" \
  "$BASE_DIR/08_ads_high_value_customer_preference_hive.sql"

run_hive_sql "[12/12] Check Hive result" \
  "$BASE_DIR/09_check_hive_result.sql"

echo "========================================"
echo "Hive main warehouse job finished successfully"
echo "bizdate: ${BIZDATE}"
echo "========================================"
