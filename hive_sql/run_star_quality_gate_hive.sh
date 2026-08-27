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

# 可选环境变量
HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"

# 可配置资源参数
MAP_MEMORY_MB="${MAP_MEMORY_MB:-2048}"
MAP_JAVA_XMX="${MAP_JAVA_XMX:-1536m}"
REDUCE_MEMORY_MB="${REDUCE_MEMORY_MB:-2048}"
REDUCE_JAVA_XMX="${REDUCE_JAVA_XMX:-1536m}"
TASK_TIMEOUT_MS="${TASK_TIMEOUT_MS:-3600000}"

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

# =====================================================
# 临时文件用于保存 Hive stderr
# =====================================================
HIVE_STDERR="$(mktemp /tmp/hive_stderr_XXXXXX.tmp)"
trap 'rm -f "${HIVE_STDERR}"' EXIT

echo "========================================"
echo "Start star schema quality gate"
echo "bizdate: ${BIZDATE}"
echo "database: ${HIVE_DATABASE}"
echo "========================================"

# 1. 计算星型模型质量指标并写入日志
hive \
    --database "${HIVE_DATABASE}" \
    --hiveconf bizdate="${BIZDATE}" \
    --hiveconf mapreduce.map.memory.mb="${MAP_MEMORY_MB}" \
    --hiveconf mapreduce.map.java.opts="-Xmx${MAP_JAVA_XMX}" \
    --hiveconf mapreduce.reduce.memory.mb="${REDUCE_MEMORY_MB}" \
    --hiveconf mapreduce.reduce.java.opts="-Xmx${REDUCE_JAVA_XMX}" \
    --hiveconf mapreduce.task.timeout="${TASK_TIMEOUT_MS}" \
    -f "${BASE_DIR}/28_load_star_quality_log_hive.sql"

# 2. 查询质量指标（与 single_session 一致的四指标门禁）
QUALITY_RESULT="$(
    hive --database "${HIVE_DATABASE}" -S -e "
        SELECT
            COUNT(*) AS rule_cnt,
            COUNT(DISTINCT rule_code) AS distinct_rule_cnt,
            COALESCE(SUM(CASE WHEN check_level = 'BLOCK' AND check_status = 'PASS' THEN 1 ELSE 0 END), 0) AS block_pass_cnt,
            COALESCE(SUM(CASE WHEN check_level = 'BLOCK' AND check_status = 'FAIL' THEN 1 ELSE 0 END), 0) AS block_fail_cnt
        FROM star_quality_log_hive
        WHERE dt='${BIZDATE}';
    " 2>"${HIVE_STDERR}"
)" || {
    echo "ERROR: Hive quality query failed."
    echo "database=${HIVE_DATABASE}"
    echo "bizdate=${BIZDATE}"
    echo "Hive stderr:"
    cat "${HIVE_STDERR}"
    exit 1
}

# 严格解析质量结果
# 1. 统计非空行数
NONEMPTY_LINE_COUNT="$(
    printf '%s\n' "${QUALITY_RESULT}" |
    awk 'NF > 0 {count++} END {print count + 0}'
)"

if [ "${NONEMPTY_LINE_COUNT}" -ne 1 ]; then
    echo "ERROR: BLOCK_QUALITY_RESULT_UNPARSEABLE"
    echo "Quality query returned ${NONEMPTY_LINE_COUNT} non-empty lines (expected exactly 1)."
    echo "Raw result:"
    echo "${QUALITY_RESULT}"
    exit 1
fi

# 2. 获取唯一非空行
QUALITY_LINE="$(
    printf '%s\n' "${QUALITY_RESULT}" |
    awk 'NF > 0 {print; exit}'
)"

# 3. 使用 read 解析四个字段
read -r RULE_CNT DISTINCT_RULE_CNT BLOCK_PASS_CNT BLOCK_FAIL_CNT EXTRA_FIELD <<< "${QUALITY_LINE}"

# 4. 检查 EXTRA_FIELD 必须为空
if [ -n "${EXTRA_FIELD:-}" ]; then
    echo "ERROR: BLOCK_QUALITY_RESULT_UNPARSEABLE"
    echo "Quality query returned extra fields (expected exactly 4 fields)."
    echo "Raw result: ${QUALITY_LINE}"
    exit 1
fi

# 5. 检查四个字段全部为非负整数
if ! [[ "${RULE_CNT:-}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: BLOCK_QUALITY_RESULT_UNPARSEABLE"
    echo "rule_cnt is not a valid non-negative integer: ${RULE_CNT:-}"
    exit 1
fi

if ! [[ "${DISTINCT_RULE_CNT:-}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: BLOCK_QUALITY_RESULT_UNPARSEABLE"
    echo "distinct_rule_cnt is not a valid non-negative integer: ${DISTINCT_RULE_CNT:-}"
    exit 1
fi

if ! [[ "${BLOCK_PASS_CNT:-}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: BLOCK_QUALITY_RESULT_UNPARSEABLE"
    echo "block_pass_cnt is not a valid non-negative integer: ${BLOCK_PASS_CNT:-}"
    exit 1
fi

if ! [[ "${BLOCK_FAIL_CNT:-}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: BLOCK_QUALITY_RESULT_UNPARSEABLE"
    echo "block_fail_cnt is not a valid non-negative integer: ${BLOCK_FAIL_CNT:-}"
    exit 1
fi

echo "Quality gate results for ${BIZDATE}:"
echo "  rule_cnt=${RULE_CNT}"
echo "  distinct_rule_cnt=${DISTINCT_RULE_CNT}"
echo "  block_pass_cnt=${BLOCK_PASS_CNT}"
echo "  block_fail_cnt=${BLOCK_FAIL_CNT}"

# 6. 验证质量门禁指标
EXPECTED_RULE_CNT=18

if [ "${RULE_CNT}" -ne "${EXPECTED_RULE_CNT}" ] || \
   [ "${DISTINCT_RULE_CNT}" -ne "${EXPECTED_RULE_CNT}" ]; then
    echo "ERROR: BLOCK_QUALITY_RULE_INCOMPLETE"
    echo "Quality rules incomplete."
    echo "Expected ${EXPECTED_RULE_CNT} rules, got rule_cnt=${RULE_CNT}, distinct_rule_cnt=${DISTINCT_RULE_CNT}."
    exit 1
fi

if [ "${BLOCK_PASS_CNT}" -ne "${EXPECTED_RULE_CNT}" ]; then
    echo "ERROR: BLOCK_QUALITY_FAILED"
    echo "Quality gate did not pass all BLOCK rules."
    echo "Expected ${EXPECTED_RULE_CNT} BLOCK PASS, got ${BLOCK_PASS_CNT}."
    exit 1
fi

if [ "${BLOCK_FAIL_CNT}" -ne 0 ]; then
    echo "ERROR: BLOCK_QUALITY_FAILED"
    echo "Quality gate has BLOCK failures."
    echo "Expected 0 BLOCK FAIL, got ${BLOCK_FAIL_CNT}."
    exit 1
fi

echo "Star schema quality gate passed."
echo "========================================"
