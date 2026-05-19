#!/bin/bash
set -e

# 用法：sh hive_sql/run_idempotency_check_hive.sh 2026-04-03
# 作用：先查询指定 bizdate 的核心表行数，再重跑 run_all_hive.sh，最后再次查询并输出前后对照结果。

BIZDATE=$1
if [ -z "$BIZDATE" ]; then
  echo "Usage: sh run_idempotency_check_hive.sh <bizdate>"
  echo "Example: sh run_idempotency_check_hive.sh 2026-04-03"
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RUN_ALL="$SCRIPT_DIR/run_all_hive.sh"

if [ ! -f "$RUN_ALL" ]; then
  echo "ERROR: run_all_hive.sh not found in $SCRIPT_DIR"
  exit 1
fi

query_count() {
  local table_name=$1
  hive -S -e "SELECT COUNT(*) FROM ${table_name} WHERE dt='${BIZDATE}';" | tr -d '[:space:]'
}

print_line() {
  local table_name=$1
  local before_cnt=$2
  local after_cnt=$3
  local status="PASS"
  if [ "$before_cnt" != "$after_cnt" ]; then
    status="FAIL"
  fi
  printf "%-36s %-12s %-15s %-15s %-8s\n" "$table_name" "$BIZDATE" "$before_cnt" "$after_cnt" "$status"
}

echo "[1/3] Query counts before rerun: $BIZDATE"
BEFORE_ODS=$(query_count ods_retail_hive)
BEFORE_DWD=$(query_count dwd_retail_clean_hive)
BEFORE_ADS_COUNTRY=$(query_count ads_country_sales_rank_hive)

echo "[2/3] Rerun full Hive main chain: $BIZDATE"
sh "$RUN_ALL" "$BIZDATE"

echo "[3/3] Query counts after rerun: $BIZDATE"
AFTER_ODS=$(query_count ods_retail_hive)
AFTER_DWD=$(query_count dwd_retail_clean_hive)
AFTER_ADS_COUNTRY=$(query_count ads_country_sales_rank_hive)

echo ""
echo "Idempotency Check Result"
printf "%-36s %-12s %-15s %-15s %-8s\n" "table_name" "dt" "before_cnt" "after_cnt" "status"
printf "%-36s %-12s %-15s %-15s %-8s\n" "------------------------------------" "------------" "---------------" "---------------" "--------"
print_line ods_retail_hive "$BEFORE_ODS" "$AFTER_ODS"
print_line dwd_retail_clean_hive "$BEFORE_DWD" "$AFTER_DWD"
print_line ads_country_sales_rank_hive "$BEFORE_ADS_COUNTRY" "$AFTER_ADS_COUNTRY"

echo ""
if [ "$BEFORE_ODS" = "$AFTER_ODS" ] && [ "$BEFORE_DWD" = "$AFTER_DWD" ] && [ "$BEFORE_ADS_COUNTRY" = "$AFTER_ADS_COUNTRY" ]; then
  echo "FINAL_RESULT: PASS - repeated execution did not change row counts."
else
  echo "FINAL_RESULT: FAIL - row counts changed after rerun, please check SQL or source data."
  exit 2
fi
