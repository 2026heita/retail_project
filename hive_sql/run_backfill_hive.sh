#!/bin/bash

# =====================================================
# 文件名: run_backfill_hive.sh
# 功能: Hive 主链路日期区间回刷脚本
# 用法:
#   sh run_backfill_hive.sh 2026-04-01 2026-04-08
#
# 说明:
#   1. 按日期区间循环调用 run_all_hive.sh。
#   2. 每天通过 INSERT OVERWRITE 覆盖对应 dt 分区，保证重复执行不产生重复数据。
#   3. 支持单日回刷和多日回刷。
#   4. 依赖 Linux GNU date 命令。
# =====================================================

START_DATE=$1
END_DATE=$2
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
  echo "ERROR: start_date and end_date are required."
  echo "Usage: sh run_backfill_hive.sh 2026-04-01 2026-04-08"
  exit 1
fi

if ! date -d "$START_DATE" +%F >/dev/null 2>&1; then
  echo "ERROR: invalid start_date: $START_DATE"
  exit 1
fi

if ! date -d "$END_DATE" +%F >/dev/null 2>&1; then
  echo "ERROR: invalid end_date: $END_DATE"
  exit 1
fi

CURRENT_DATE="$(date -d "$START_DATE" +%F)"
END_DATE_NORM="$(date -d "$END_DATE" +%F)"

if [ "$(date -d "$CURRENT_DATE" +%s)" -gt "$(date -d "$END_DATE_NORM" +%s)" ]; then
  echo "ERROR: start_date must be earlier than or equal to end_date."
  echo "start_date: $START_DATE"
  echo "end_date: $END_DATE"
  exit 1
fi

echo "========================================"
echo "Start Hive backfill job"
echo "start_date: ${CURRENT_DATE}"
echo "end_date:   ${END_DATE_NORM}"
echo "base_dir:   ${BASE_DIR}"
echo "========================================"

while [ "$(date -d "$CURRENT_DATE" +%s)" -le "$(date -d "$END_DATE_NORM" +%s)" ]
do
  echo "========================================"
  echo "Backfill bizdate: $CURRENT_DATE"
  echo "========================================"

  sh "$BASE_DIR/run_all_hive.sh" "$CURRENT_DATE"

  if [ $? -ne 0 ]; then
    echo "ERROR: backfill failed at bizdate=$CURRENT_DATE"
    exit 1
  fi

  CURRENT_DATE="$(date -d "$CURRENT_DATE +1 day" +%F)"
done

echo "========================================"
echo "Hive backfill job finished successfully"
echo "start_date: $START_DATE"
echo "end_date: $END_DATE"
echo "========================================"
