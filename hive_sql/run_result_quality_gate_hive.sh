#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_result_quality_gate_hive.sh
# 功能: 执行 DWS / ADS 后置质量检查
# 用法:
#   bash run_result_quality_gate_hive.sh 2026-04-08
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_result_quality_gate_hive.sh 2026-04-08"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

echo "========================================"
echo "Start DWS/ADS result quality gate"
echo "bizdate: ${BIZDATE}"
echo "========================================"

# 1. 计算 DWS / ADS 质量指标并写入结果质量日志
hive \
    --hiveconf bizdate="${BIZDATE}" \
    -f "${BASE_DIR}/27_load_result_quality_log_hive.sql"

# 2. 统计 BLOCK 级失败项
FAILED_COUNT=$(
    hive -S -e "
        SELECT COUNT(1)
        FROM result_quality_log_hive
        WHERE dt='${BIZDATE}'
          AND check_status='FAIL'
          AND check_level='BLOCK';
    " 2>/dev/null |
    grep -E '^[0-9]+$' |
    tail -n 1
)

# 无法读取结果时不能默认通过
if [ -z "${FAILED_COUNT}" ]; then
    echo "ERROR: failed to read result quality check."
    exit 1
fi

# BLOCK 失败时阻断主链路
if [ "${FAILED_COUNT}" -gt 0 ]; then
    echo "ERROR: DWS/ADS result quality gate failed."
    echo "failed_count=${FAILED_COUNT}"
    echo "Check result_quality_log_hive where dt='${BIZDATE}'."
    exit 1
fi

# WARN 只展示数量，不阻断
WARN_COUNT=$(
    hive -S -e "
        SELECT COUNT(1)
        FROM result_quality_log_hive
        WHERE dt='${BIZDATE}'
          AND check_status='FAIL'
          AND check_level='WARN';
    " 2>/dev/null |
    grep -E '^[0-9]+$' |
    tail -n 1
)

WARN_COUNT="${WARN_COUNT:-0}"

echo "DWS/ADS result quality gate passed."
echo "failed_count=0"
echo "warn_count=${WARN_COUNT}"
echo "========================================"
