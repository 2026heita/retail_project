#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_t1_window_hive.sh
# 功能: 执行 Hive 主链路的 T+1 延迟数据修正窗口
# 用法:
#   bash run_t1_window_hive.sh 2026-04-08
#
# 说明:
#   1. 输入当天 bizdate。
#   2. 自动计算前一天 last_date。
#   3. 调用 run_backfill_hive.sh，依次回刷 last_date 和 bizdate。
#   4. 任意一天失败时立即停止并返回非零状态。
#   5. 依赖 Linux GNU date 命令。
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKFILL_SCRIPT="${BASE_DIR}/run_backfill_hive.sh"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_t1_window_hive.sh 2026-04-08"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    echo "Usage: bash run_t1_window_hive.sh 2026-04-08"
    exit 1
fi

if [ ! -f "${BACKFILL_SCRIPT}" ]; then
    echo "ERROR: backfill script not found: ${BACKFILL_SCRIPT}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"
LAST_DATE="$(date -d "${BIZDATE} -1 day" +%F)"

echo "========================================"
echo "Start Hive T+1 window refresh"
echo "last_date: ${LAST_DATE}"
echo "bizdate:   ${BIZDATE}"
echo "base_dir:  ${BASE_DIR}"
echo "========================================"

if ! bash "${BACKFILL_SCRIPT}" "${LAST_DATE}" "${BIZDATE}"; then
    echo "ERROR: T+1 window refresh failed."
    echo "refresh range: ${LAST_DATE} ~ ${BIZDATE}"
    exit 1
fi

echo "========================================"
echo "Hive T+1 window refresh finished successfully"
echo "refresh range: ${LAST_DATE} ~ ${BIZDATE}"
echo "========================================"
