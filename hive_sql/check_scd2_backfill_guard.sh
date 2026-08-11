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
#
# 失败关闭策略:
#   - Hive 命令执行失败时阻断，不按首次部署放行
#   - 先检查表是否存在，再查询分区
#   - 查询 next_dwd_dt 失败时阻断
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 可选环境变量
HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"

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

# =====================================================
# 临时文件用于保存 Hive stderr
# =====================================================
HIVE_STDERR="$(mktemp /tmp/hive_stderr_XXXXXX.tmp)"
trap 'rm -f "${HIVE_STDERR}"' EXIT

# =====================================================
# 第一步: 检查 dim_user 表是否存在
# =====================================================
echo "Checking if dim_user table exists..."

TABLE_CHECK_RESULT="$(
    hive --database "${HIVE_DATABASE}" -S -e "SHOW TABLES LIKE 'dim_user';" 2>"${HIVE_STDERR}"
)" || {
    echo "ERROR: Hive SHOW TABLES LIKE 'dim_user' failed."
    echo "database=${HIVE_DATABASE}"
    echo "bizdate=${BIZDATE}"
    echo "Hive stderr:"
    cat "${HIVE_STDERR}"
    exit 1
}

# 检查查询结果是否包含精确的 dim_user
if ! printf '%s\n' "${TABLE_CHECK_RESULT}" | grep -qx 'dim_user'; then
    echo "INFO: dim_user table does not exist yet."
    echo "SCD2 guard status: INITIAL_LOAD"
    echo "database=${HIVE_DATABASE}"
    echo "bizdate=${BIZDATE}"
    echo "max_dim_user_dt=NONE"
    echo "next_dwd_dt=NONE"
    exit 0
fi

echo "dim_user table exists."

# =====================================================
# 第二步: 查询 dim_user 分区
# =====================================================
echo "Querying dim_user partitions..."

PARTITIONS="$(
    hive --database "${HIVE_DATABASE}" -S -e "SHOW PARTITIONS dim_user;" 2>"${HIVE_STDERR}"
)" || {
    echo "ERROR: Hive SHOW PARTITIONS dim_user failed."
    echo "database=${HIVE_DATABASE}"
    echo "bizdate=${BIZDATE}"
    echo "Hive stderr:"
    cat "${HIVE_STDERR}"
    exit 1
}

MAX_DT="$(
    printf '%s\n' "${PARTITIONS}" \
    | sed -n 's/^dt=//p' \
    | sort \
    | tail -1
)"

# 表已创建但还没有任何分区
if [ -z "${MAX_DT}" ]; then
    echo "INFO: dim_user has no partitions."
    echo "SCD2 guard status: INITIAL_LOAD"
    echo "database=${HIVE_DATABASE}"
    echo "bizdate=${BIZDATE}"
    echo "max_dim_user_dt=NONE"
    echo "next_dwd_dt=NONE"
    exit 0
fi

echo "dim_user max partition: ${MAX_DT}"

# =====================================================
# 第三步: 查询 next_dwd_dt (max_dt 之后的第一个真实业务日期)
# =====================================================
echo "Querying next_dwd_dt from dwd_retail_clean_hive..."

NEXT_DWD_DT="$(
    hive --database "${HIVE_DATABASE}" -S -e "
        SELECT MIN(dt)
        FROM dwd_retail_clean_hive
        WHERE dt > '${MAX_DT}';
    " 2>"${HIVE_STDERR}"
)" || {
    echo "ERROR: Hive query for next_dwd_dt failed."
    echo "database=${HIVE_DATABASE}"
    echo "bizdate=${BIZDATE}"
    echo "max_dim_user_dt=${MAX_DT}"
    echo "Hive stderr:"
    cat "${HIVE_STDERR}"
    exit 1
}

# 清理查询结果（去除空白和 NULL）
NEXT_DWD_DT="$(echo "${NEXT_DWD_DT}" | tr -d '[:space:]')"

if [ -z "${NEXT_DWD_DT}" ] || [ "${NEXT_DWD_DT}" = "NULL" ]; then
    echo "ERROR: no business dates found after max_dim_user_dt=${MAX_DT}."
    echo "SCD2 guard status: BLOCK_NO_NEXT_DWD_DT"
    echo "database=${HIVE_DATABASE}"
    echo "bizdate=${BIZDATE}"
    echo "max_dim_user_dt=${MAX_DT}"
    echo "next_dwd_dt=NONE"
    echo
    echo "Cannot append beyond current max without DWD data."
    echo "No automatic rerun or overwrite is allowed."
    exit 1
fi

echo "next_dwd_dt: ${NEXT_DWD_DT}"

# =====================================================
# 第四步: 执行 SCD2 Guard 检查
# =====================================================
BIZDATE_TS="$(date -d "${BIZDATE}" +%s)"
MAX_DT_TS="$(date -d "${MAX_DT}" +%s)"
NEXT_DWD_DT_TS="$(date -d "${NEXT_DWD_DT}" +%s)"

echo "SCD2 guard check:"
echo "database=${HIVE_DATABASE}"
echo "bizdate=${BIZDATE}"
echo "max_dim_user_dt=${MAX_DT}"
echo "next_dwd_dt=${NEXT_DWD_DT}"

# 情况 1: bizdate <= max_dt，历史覆盖，阻断
if [ "${BIZDATE_TS}" -le "${MAX_DT_TS}" ]; then
    echo "ERROR: unsafe historical single-date rerun detected."
    echo "SCD2 guard status: BLOCK_HISTORY_OVERWRITE"
    echo
    echo "dim_user already contains a later or equal snapshot:"
    echo "  max_dim_user_dt=${MAX_DT}"
    echo "  bizdate=${BIZDATE}"
    echo
    echo "This is a historical overwrite, not a normal incremental append."
    echo "Use range backfill script with proper validation:"
    echo "  bash ${BASE_DIR}/run_star_backfill_hive.sh <start_date> <end_date>"
    exit 1
fi

# 情况 2: bizdate > next_dwd_dt，跳日，阻断
if [ "${BIZDATE_TS}" -gt "${NEXT_DWD_DT_TS}" ]; then
    echo "ERROR: bizdate skips over next DWD business date."
    echo "SCD2 guard status: BLOCK_GAP"
    echo
    echo "bizdate is after the next DWD business date:"
    echo "  bizdate=${BIZDATE}"
    echo "  next_dwd_dt=${NEXT_DWD_DT}"
    echo
    echo "Cannot skip business dates. Must process in ascending order."
    echo "Use range backfill script to process all dates:"
    echo "  bash ${BASE_DIR}/run_star_backfill_hive.sh ${NEXT_DWD_DT} ${BIZDATE}"
    exit 1
fi

# 情况 3: bizdate = next_dwd_dt，正常追加，允许
if [ "${BIZDATE_TS}" -eq "${NEXT_DWD_DT_TS}" ]; then
    echo "SCD2 guard status: ALLOW"
    echo "SCD2 guard passed: bizdate equals next_dwd_dt (normal append)."
    exit 0
fi

# 不应该到达这里
echo "ERROR: unexpected SCD2 guard state."
echo "bizdate=${BIZDATE}"
echo "max_dim_user_dt=${MAX_DT}"
echo "next_dwd_dt=${NEXT_DWD_DT}"
exit 1
