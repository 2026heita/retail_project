#!/bin/bash

# =====================================================
# 文件名: run_all_hive.sh
# 功能: 按业务日期执行 Hive ODS / DWD / DWS / ADS / 结果校验完整链路
# 用法:
#   sh run_all_hive.sh 2026-04-08
# =====================================================

BIZDATE=$1

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$BIZDATE" ]; then
  echo "ERROR: bizdate is required."
  echo "Usage: sh run_all_hive.sh 2026-04-08"
  exit 1
fi

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
echo "Start Hive migration job"
echo "bizdate: ${BIZDATE}"
echo "base_dir: ${BASE_DIR}"
echo "========================================"

run_hive_sql "[1/10] Run ODS table creation" \
  "$BASE_DIR/00_ods_retail_hive.sql"

run_hive_sql "[2/10] Run DWD table creation" \
  "$BASE_DIR/01_dwd_retail_clean_hive.sql"

run_hive_sql "[3/10] Run DWD data loading" \
  "$BASE_DIR/02_load_dwd_retail_clean_hive.sql"

run_hive_sql "[4/10] Run DWS customer value" \
  "$BASE_DIR/03_dws_customer_value_hive.sql"

run_hive_sql "[5/10] Run DWS sales summary" \
  "$BASE_DIR/04_dws_sales_summary_hive.sql"

run_hive_sql "[6/10] Run ADS high value customer contribution" \
  "$BASE_DIR/05_ads_high_value_customer_sales_contribution_hive.sql"

run_hive_sql "[7/10] Run ADS customer level distribution" \
  "$BASE_DIR/06_ads_customer_level_distribution_hive.sql"

run_hive_sql "[8/10] Run ADS country sales rank" \
  "$BASE_DIR/07_ads_country_sales_rank_hive.sql"

run_hive_sql "[9/10] Run ADS high value customer preference" \
  "$BASE_DIR/08_ads_high_value_customer_preference_hive.sql"

run_hive_sql "[10/10] Run Hive result check" \
  "$BASE_DIR/09_check_hive_result.sql"

echo "========================================"
echo "Hive migration job finished successfully"
echo "bizdate: ${BIZDATE}"
echo "========================================"