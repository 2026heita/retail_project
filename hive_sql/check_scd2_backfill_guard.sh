#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: check_scd2_backfill_guard.sh
# 功能:
#   防止在已经存在更晚 dim_user 快照时，
#   单独重跑较早业务日期，造成后续 SCD2 快照不一致。
#
# 用法:
#   bash check_scd2_backfill_guard.sh 2026-04-08
#
# 返回:
#   0 = 可以安全执行
#   1 = 必须改用区间回刷
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash check_scd2_backfill_guard.sh YYYY-MM-DD"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

# 新环境中 dim_user 可能尚未创建。
# 这种情况下不阻断，后续建表流程会负责创建。
if ! PARTITIONS="$(
    hive -S -e "SHOW PARTITIONS dim_user;" 2>/dev/null
)"; then
    echo "INFO: dim_user table does not exist yet."
    echo "SCD2 guard passed for initial deployment."
    exit 0
fi

MAX_DT="$(
    printf '%s\n' "${PARTITIONS}" \
    | sed -n 's/^dt=//p' \
    | sort \
    | tail -1
)"

# 表已创建但还没有任何分区。
if [ -z "${MAX_DT}" ]; then
    echo "INFO: dim_user has no partitions."
    echo "SCD2 guard passed for first data load."
    exit 0
fi

BIZDATE_TS="$(date -d "${BIZDATE}" +%s)"
MAX_DT_TS="$(date -d "${MAX_DT}" +%s)"

echo "SCD2 guard check:"
echo "bizdate=${BIZDATE}"
echo "max_dim_user_dt=${MAX_DT}"

if [ "${BIZDATE_TS}" -lt "${MAX_DT_TS}" ]; then
    echo "ERROR: unsafe historical single-date rerun detected."
    echo
    echo "dim_user already contains a later snapshot:"
    echo "  max_dt=${MAX_DT}"
    echo
    echo "Rebuild all dependent dates in ascending order:"
    echo "  bash ${BASE_DIR}/run_backfill_hive.sh ${BIZDATE} ${MAX_DT}"
    exit 1
fi

echo "SCD2 guard passed."
exit 0
