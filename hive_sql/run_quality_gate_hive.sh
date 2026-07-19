#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_quality_gate_hive.sh
# 功能: 执行 DWD 数据质量检查，并在存在失败项时返回非零状态
# 用法:
#   bash run_quality_gate_hive.sh 2026-07-18
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_quality_gate_hive.sh 2026-07-18"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

echo "========================================"
echo "Start Hive data quality gate"
echo "bizdate: ${BIZDATE}"
echo "========================================"

# 1. 确保质量日志表存在
hive \
    --hiveconf bizdate="${BIZDATE}" \
    -f "${BASE_DIR}/23_quality_log_hive.sql"

# 2. 计算质量指标并写入质量日志
hive \
    --hiveconf bizdate="${BIZDATE}" \
    -f "${BASE_DIR}/24_load_quality_log_hive.sql"

# 3. 查询当天失败项数量
FAILED_COUNT=$(
    hive -S -e "
        SELECT COUNT(1)
        FROM quality_log_hive
        WHERE dt='${BIZDATE}'
          AND check_status='FAIL';
    " 2>/dev/null |
    grep -E '^[0-9]+$' |
    tail -n 1
)

# 无法读取结果时不能默认通过
if [ -z "${FAILED_COUNT}" ]; then
    echo "ERROR: failed to read quality check result."
    exit 1
fi

# 有任意失败项时，主动返回非零状态
if [ "${FAILED_COUNT}" -gt 0 ]; then
    echo "ERROR: data quality gate failed."
    echo "failed_count=${FAILED_COUNT}"
    echo "Check quality_log_hive where dt='${BIZDATE}'."
    exit 1
fi

echo "Data quality gate passed."
echo "failed_count=0"
echo "========================================"