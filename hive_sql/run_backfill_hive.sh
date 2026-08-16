#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_backfill_hive.sh
# 功能: 按日期区间回刷 Hive 主链路
# 用法:
#   bash run_backfill_hive.sh 2026-04-01 2026-04-08
#
# 说明:
#   1. 按日期从小到大调用 run_all_hive.sh。
#   2. 任意一天失败后立即停止，不继续处理后续日期。
#   3. 通过各层 INSERT OVERWRITE 重写对应 dt 分区，保证可重复执行。
#   4. 依赖 Linux GNU date 命令。
# =====================================================

START_DATE="${1:-}"
END_DATE="${2:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_ALL_SCRIPT="${BASE_DIR}/run_all_hive.sh"
HIVE_DATABASE="${HIVE_DATABASE:-default}"
export HIVE_DATABASE

if [ -z "${START_DATE}" ] || [ -z "${END_DATE}" ]; then
    echo "ERROR: start_date and end_date are required."
    echo "Usage: bash run_backfill_hive.sh 2026-04-01 2026-04-08"
    exit 1
fi

if ! date -d "${START_DATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid start_date: ${START_DATE}"
    exit 1
fi

if ! date -d "${END_DATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid end_date: ${END_DATE}"
    exit 1
fi

if [ ! -f "${RUN_ALL_SCRIPT}" ]; then
    echo "ERROR: main script not found: ${RUN_ALL_SCRIPT}"
    exit 1
fi

START_DATE_NORM="$(date -d "${START_DATE}" +%F)"
END_DATE_NORM="$(date -d "${END_DATE}" +%F)"

if [ "$(date -d "${START_DATE_NORM}" +%s)" -gt \
     "$(date -d "${END_DATE_NORM}" +%s)" ]; then
    echo "ERROR: start_date must be earlier than or equal to end_date."
    exit 1
fi

echo "========================================"
echo "Start Hive backfill job"
echo "start_date: ${START_DATE_NORM}"
echo "end_date:   ${END_DATE_NORM}"
echo "database:   ${HIVE_DATABASE}"
echo "========================================"

if ! BUSINESS_DATES="$(
    hive --database "${HIVE_DATABASE}" -S -e "
        SELECT bizdate
        FROM (
            SELECT DISTINCT
                FROM_UNIXTIME(
                    COALESCE(
                        UNIX_TIMESTAMP(TRIM(CAST(InvoiceDate AS STRING)), 'yyyy-MM-dd HH:mm:ss'),
                        UNIX_TIMESTAMP(TRIM(CAST(InvoiceDate AS STRING)), 'yyyy-MM-dd HH:mm'),
                        UNIX_TIMESTAMP(TRIM(CAST(InvoiceDate AS STRING)), 'd/M/yyyy HH:mm:ss'),
                        UNIX_TIMESTAMP(TRIM(CAST(InvoiceDate AS STRING)), 'd/M/yyyy HH:mm')
                    ),
                    'yyyy-MM-dd'
                ) AS bizdate
            FROM retail
        ) t
        WHERE bizdate BETWEEN '${START_DATE_NORM}' AND '${END_DATE_NORM}'
        ORDER BY bizdate;
    " 2>/dev/null
)"; then
    echo "ERROR: failed to query business dates."
    exit 1
fi

BUSINESS_DATES="$(
    printf '%s\n' "${BUSINESS_DATES}" |
    grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || true
)"

if [ -z "${BUSINESS_DATES}" ]; then
    echo "No business dates found in the requested range."
    exit 0
fi

while IFS= read -r CURRENT_DATE
do
    [ -z "${CURRENT_DATE}" ] && continue

    echo "========================================"
    echo "Backfill bizdate: ${CURRENT_DATE}"
    echo "========================================"

if ! RUN_STAR=0 bash "${RUN_ALL_SCRIPT}" "${CURRENT_DATE}"; then
        echo "ERROR: backfill failed at bizdate=${CURRENT_DATE}"
        echo "Remaining business dates were not executed."
        exit 1
    fi
done <<< "${BUSINESS_DATES}"

echo "========================================"
echo "Hive backfill job finished successfully"
echo "start_date: ${START_DATE_NORM}"
echo "end_date:   ${END_DATE_NORM}"
echo "========================================"
