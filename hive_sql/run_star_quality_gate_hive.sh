#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_star_quality_gate_hive.sh
# 功能: 执行星型模型质量门禁
# 用法:
#   bash run_star_quality_gate_hive.sh 2026-04-08
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_star_quality_gate_hive.sh 2026-04-08"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

echo "========================================"
echo "Start star schema quality gate"
echo "bizdate: ${BIZDATE}"
echo "========================================"

# 1. 计算星型模型质量指标并写入日志
hive \
    --hiveconf bizdate="${BIZDATE}" \
    -f "${BASE_DIR}/28_load_star_quality_log_hive.sql"

# 2. 查询 BLOCK 级失败项数量
FAILED_COUNT=$(
    hive -S -e "
        SELECT COUNT(1)
        FROM star_quality_log_hive
        WHERE dt='${BIZDATE}'
          AND check_status='FAIL'
          AND check_level='BLOCK';
    " 2>/dev/null |
    grep -E '^[0-9]+$' |
    tail -n 1
)

# 无法读取结果时不能默认通过
if [ -z "${FAILED_COUNT}" ]; then
    echo "ERROR: failed to read star quality check result."
    exit 1
fi

# 有 BLOCK 失败时主动返回非零状态
if [ "${FAILED_COUNT}" -gt 0 ]; then
    echo "ERROR: star schema quality gate failed."
    echo "failed_count=${FAILED_COUNT}"
    echo "Check star_quality_log_hive where dt='${BIZDATE}'."
    exit 1
fi

# WARN 只记录，不阻断
WARN_COUNT=$(
    hive -S -e "
        SELECT COUNT(1)
        FROM star_quality_log_hive
        WHERE dt='${BIZDATE}'
          AND check_status='FAIL'
          AND check_level='WARN';
    " 2>/dev/null |
    grep -E '^[0-9]+$' |
    tail -n 1
)

WARN_COUNT="${WARN_COUNT:-0}"

echo "Star schema quality gate passed."
echo "failed_count=0"
echo "warn_count=${WARN_COUNT}"
echo "========================================"
