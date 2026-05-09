#!/bin/bash

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-retail_project}"

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$BASE_DIR/etl_log.txt"
RUN_SQL="$BASE_DIR/../sql/08_run_all.sql"
LOG_TABLE_SQL="$BASE_DIR/../sql/11_etl_task_log.sql"

BATCH_ID=$(date +"%Y%m%d_%H%M%S")

# MySQL 密码参数处理：
# 如果 DB_PASSWORD 为空，则不传 -p，避免 MySQL 进入交互式密码输入
MYSQL_PWD_OPT=""
if [ -n "$DB_PASSWORD" ]; then
  MYSQL_PWD_OPT="-p$DB_PASSWORD"
fi

echo "========== ETL START ==========" | tee -a "$LOG_FILE"
echo "batch_id=$BATCH_ID" | tee -a "$LOG_FILE"
echo "run_time=$(date '+%F %T')" | tee -a "$LOG_FILE"

if [ ! -f "$RUN_SQL" ]; then
  echo "[ERROR] 08_run_all.sql 不存在: $RUN_SQL" | tee -a "$LOG_FILE"
  exit 1
fi

if [ ! -f "$LOG_TABLE_SQL" ]; then
  echo "[ERROR] 11_etl_task_log.sql 不存在: $LOG_TABLE_SQL" | tee -a "$LOG_FILE"
  exit 1
fi

mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $MYSQL_PWD_OPT "$DB_NAME" < "$LOG_TABLE_SQL" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  echo "[ERROR] 创建 etl_task_log 失败" | tee -a "$LOG_FILE"
  exit 1
fi

mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $MYSQL_PWD_OPT "$DB_NAME" -e "
INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark)
VALUES ('$BATCH_ID', 'run_all_etl', NOW(), 'START', '开始执行 08_run_all.sql');
" >> "$LOG_FILE" 2>&1

mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $MYSQL_PWD_OPT "$DB_NAME" < "$RUN_SQL" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
  echo "[INFO] ETL 执行成功" | tee -a "$LOG_FILE"

  mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $MYSQL_PWD_OPT "$DB_NAME" -e "
  INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark)
  VALUES ('$BATCH_ID', 'run_all_etl', NOW(), 'SUCCESS', '08_run_all.sql 执行成功');
  " >> "$LOG_FILE" 2>&1

  echo "========== ETL SUCCESS ==========" | tee -a "$LOG_FILE"
else
  echo "[ERROR] ETL 执行失败" | tee -a "$LOG_FILE"

  mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $MYSQL_PWD_OPT "$DB_NAME" -e "
  INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark)
  VALUES ('$BATCH_ID', 'run_all_etl', NOW(), 'FAILED', '08_run_all.sql 执行失败，请检查 etl_log.txt');
  " >> "$LOG_FILE" 2>&1

  echo "========== ETL FAILED ==========" | tee -a "$LOG_FILE"
  exit 1
fi