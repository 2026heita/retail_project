#!/bin/bash

# =====================================================
# 文件名: run_star_schema_hive.sh
# 功能: 执行 11-22 星型模型扩展链路
# 用法:
#   sh run_star_schema_hive.sh 2026-04-08
#
# 说明:
#   1. 这是星型模型扩展链路，不替代 run_all_hive.sh 主链路。
#   2. 执行前请先运行 run_all_hive.sh，确保 ODS / DWD 主链路已完成。
#   3. 本脚本基于 DWD 构建 dim_user / dim_product / dim_date / dim_geo / fact_order。
#   4. 星型模型客户价值汇总表建议使用 dws_customer_value_star_hive，
#      避免与主链路 dws_customer_value_hive 表名和结构冲突。
# =====================================================

BIZDATE=$1
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$BIZDATE" ]; then
  echo "ERROR: bizdate is required."
  echo "Usage: sh run_star_schema_hive.sh 2026-04-08"
  exit 1
fi

if ! date -d "$BIZDATE" +%F >/dev/null 2>&1; then
  echo "ERROR: invalid bizdate: $BIZDATE"
  echo "Usage: sh run_star_schema_hive.sh 2026-04-08"
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
echo "Start Hive star schema extension job"
echo "bizdate: ${BIZDATE}"
echo "base_dir: ${BASE_DIR}"
echo "========================================"

run_hive_sql "[01/12] Create user dimension" \
  "$BASE_DIR/11_dim_user_scd2_hive.sql"

run_hive_sql "[02/12] Load user dimension snapshot" \
  "$BASE_DIR/12_load_dim_user_scd2_hive.sql"

run_hive_sql "[03/12] Create product dimension" \
  "$BASE_DIR/13_dim_product_hive.sql"

run_hive_sql "[04/12] Load product dimension" \
  "$BASE_DIR/14_load_dim_product_hive.sql"

run_hive_sql "[05/12] Create date dimension" \
  "$BASE_DIR/19_dim_date_hive.sql"

run_hive_sql "[06/12] Load date dimension" \
  "$BASE_DIR/22_load_dim_date_hive.sql"

run_hive_sql "[07/12] Create geo dimension" \
  "$BASE_DIR/20_dim_geo_hive.sql"

run_hive_sql "[08/12] Load geo dimension" \
  "$BASE_DIR/21_load_dim_geo_hive.sql"

run_hive_sql "[09/12] Create fact order table" \
  "$BASE_DIR/15_fact_order_hive.sql"

run_hive_sql "[10/12] Load fact order partition" \
  "$BASE_DIR/16_load_fact_order_hive.sql"

run_hive_sql "[11/12] Create star DWS customer value table" \
  "$BASE_DIR/17_dws_customer_value_star_hive.sql"

run_hive_sql "[12/12] Load star DWS customer value partition" \
  "$BASE_DIR/18_load_dws_customer_value_star_hive.sql"

echo "========================================"
echo "Hive star schema extension job finished successfully"
echo "bizdate: ${BIZDATE}"
echo "========================================"
