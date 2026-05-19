#!/bin/bash

# =====================================================
# 文件名: run_t1_window_hive.sh
# 功能: Hive 主链路 T+1 延迟数据修正窗口
# 用法:
#   sh run_t1_window_hive.sh 2026-04-08
#
# 说明:
#   1. 输入当天 bizdate。
#   2. 自动计算前一天 last_date。
#   3. 调用 run_backfill_hive.sh，依次回刷 last_date 和 bizdate 两天分区。
#   4. 通过 INSERT OVERWRITE 覆盖对应 dt 分区，保证任务幂等。
#   5. 依赖 Linux GNU date 命令。
# =====================================================

BIZDATE=$1
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$BIZDATE" ]; then
  echo "ERROR: bizdate is required."
  echo "Usage: sh run_t1_window_hive.sh 2026-04-08"
  exit 1
fi

if ! date -d "$BIZDATE" +%F >/dev/null 2>&1; then
  echo "ERROR: invalid bizdate: $BIZDATE"
  echo "Usage: sh run_t1_window_hive.sh 2026-04-08"
  exit 1
fi

BIZDATE="$(date -d "$BIZDATE" +%F)"
LAST_DATE="$(date -d "$BIZDATE -1 day" +%F)"

echo "========================================"
echo "Start Hive T+1 window refresh"
echo "last_date: ${LAST_DATE}"
echo "bizdate:   ${BIZDATE}"
echo "base_dir:  ${BASE_DIR}"
echo "========================================"

sh "$BASE_DIR/run_backfill_hive.sh" "$LAST_DATE" "$BIZDATE"

if [ $? -ne 0 ]; then
  echo "ERROR: T+1 window refresh failed."
  exit 1
fi

echo "========================================"
echo "Hive T+1 window refresh finished successfully"
echo "refresh range: ${LAST_DATE} ~ ${BIZDATE}"
echo "========================================"
