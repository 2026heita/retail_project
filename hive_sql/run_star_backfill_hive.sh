#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_star_backfill_hive.sh
# 功能: 星型模型区间回刷执行入口
# 用法:
#   bash run_star_backfill_hive.sh 2009-12-01 2011-12-09
#
# 执行效率边界说明:
#   - 已避免每天重复执行 DDL (建表只在开始前执行一次)
#   - 仍属于按业务日期顺序执行的 SCD2 回刷
#   - 大范围回刷会产生较多 MapReduce 作业
#   - 在完成 SQL 区间化优化前，不建议直接执行完整 604 日回刷
#
# 失败关闭策略:
#   - Hive 命令执行失败时阻断，不按首次部署放行
#   - 先检查表是否存在，再查询分区
#   - DWD 日期查询失败时返回非零状态
#   - 日期格式校验失败时阻断
#   - 七张表最大分区不一致时阻断
#   - START_DATE 不符合连续追加条件时阻断
#
# 环境变量:
#   STAR_EXEC_MODE: legacy (default) | single_session
#     传递给 run_star_schema_hive.sh
#
#   STAR_BACKFILL_DRY_RUN: 0 (default) | 1
#     1 = 只读预览模式，只输出信息不执行 DDL/DML
# =====================================================

START_DATE="${1:-}"
END_DATE="${2:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 可选环境变量
HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"
BATCH_DT="${BATCH_DT:-${START_DATE}}"
STAR_EXEC_MODE="${STAR_EXEC_MODE:-legacy}"
STAR_BACKFILL_DRY_RUN="${STAR_BACKFILL_DRY_RUN:-0}"

# 可配置资源参数
MAP_MEMORY_MB="${MAP_MEMORY_MB:-2048}"
MAP_JAVA_XMX="${MAP_JAVA_XMX:-1536m}"
REDUCE_MEMORY_MB="${REDUCE_MEMORY_MB:-2048}"
REDUCE_JAVA_XMX="${REDUCE_JAVA_XMX:-1536m}"
TASK_TIMEOUT_MS="${TASK_TIMEOUT_MS:-3600000}"

if [ -z "${START_DATE}" ] || [ -z "${END_DATE}" ]; then
    echo "ERROR: start_date and end_date are required."
    echo "Usage: bash run_star_backfill_hive.sh YYYY-MM-DD YYYY-MM-DD"
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

START_DATE="$(date -d "${START_DATE}" +%F)"
END_DATE="$(date -d "${END_DATE}" +%F)"

if [[ "${START_DATE}" > "${END_DATE}" ]]; then
    echo "ERROR: start_date (${START_DATE}) must not be after end_date (${END_DATE})."
    exit 1
fi

# 验证 STAR_EXEC_MODE
if [ "${STAR_EXEC_MODE}" != "legacy" ] && [ "${STAR_EXEC_MODE}" != "single_session" ]; then
    echo "ERROR: invalid STAR_EXEC_MODE: ${STAR_EXEC_MODE}"
    echo "Valid values: legacy, single_session"
    exit 1
fi

# 验证 STAR_BACKFILL_DRY_RUN
if [ "${STAR_BACKFILL_DRY_RUN}" != "0" ] && [ "${STAR_BACKFILL_DRY_RUN}" != "1" ]; then
    echo "ERROR: invalid STAR_BACKFILL_DRY_RUN: ${STAR_BACKFILL_DRY_RUN}"
    echo "Valid values: 0, 1"
    exit 1
fi

# 导出环境变量供子脚本使用
export HIVE_DATABASE
export BATCH_DT
export MAP_MEMORY_MB
export MAP_JAVA_XMX
export REDUCE_MEMORY_MB
export REDUCE_JAVA_XMX
export TASK_TIMEOUT_MS
export STAR_EXEC_MODE
export STAR_BACKFILL_DRY_RUN

# =====================================================
# 临时文件用于保存 Hive stderr
# =====================================================
HIVE_STDERR="$(mktemp /tmp/hive_stderr_XXXXXX.tmp)"
trap 'rm -f "${HIVE_STDERR}"' EXIT

echo "========================================"
echo "Start star schema backfill"
echo "start_date: ${START_DATE}"
echo "end_date: ${END_DATE}"
echo "database: ${HIVE_DATABASE}"
echo "exec_mode: ${STAR_EXEC_MODE}"
echo "dry_run: ${STAR_BACKFILL_DRY_RUN}"
echo "========================================"

# =====================================================
# 辅助函数: 查询表的最大分区
# =====================================================
get_max_partition() {
    local table_name="$1"
    local result=""

    result="$(
        hive --database "${HIVE_DATABASE}" -S -e "
            SHOW PARTITIONS ${table_name};
        " 2>"${HIVE_STDERR}"
    )" || {
        echo "ERROR: Hive SHOW PARTITIONS ${table_name} failed."
        echo "Hive stderr:"
        cat "${HIVE_STDERR}"
        return 1
    }

    local max_dt=""
    max_dt="$(
        printf '%s\n' "${result}" \
        | sed -n 's/^dt=//p' \
        | sort \
        | tail -1
    )"

    if [ -z "${max_dt}" ]; then
        echo "NONE"
    else
        echo "${max_dt}"
    fi
    return 0
}

# =====================================================
# 第一步: 检查七张星型表的分区状态
# =====================================================
echo "Checking partition status of 7 star schema tables..."

# 定义七张表
STAR_TABLES=(
    "dim_user"
    "dim_product"
    "dim_date"
    "dim_geo"
    "fact_order"
    "dws_customer_value_star_hive"
    "star_quality_log_hive"
)

# 存储每张表的最大分区
declare -A TABLE_MAX_DT
NONE_COUNT=0
DATE_COUNT_TABLES=0
FIRST_DATE_FOUND=""

for table in "${STAR_TABLES[@]}"; do
    # 检查表是否存在
    TABLE_CHECK_RESULT="$(
        hive --database "${HIVE_DATABASE}" -S -e "SHOW TABLES LIKE '${table}';" 2>"${HIVE_STDERR}"
    )" || {
        echo "ERROR: Hive SHOW TABLES LIKE '${table}' failed."
        echo "database=${HIVE_DATABASE}"
        echo "Hive stderr:"
        cat "${HIVE_STDERR}"
        exit 1
    }

    if ! printf '%s\n' "${TABLE_CHECK_RESULT}" | grep -qx "${table}"; then
        echo "Table ${table}: DOES NOT EXIST"
        TABLE_MAX_DT["${table}"]="NONE"
        NONE_COUNT=$((NONE_COUNT + 1))
    else
        # 查询最大分区
        max_dt="$(get_max_partition "${table}")" || {
            echo "ERROR: Failed to get max partition for ${table}"
            echo "BLOCK_QUERY_FAILED"
            exit 1
        }

        TABLE_MAX_DT["${table}"]="${max_dt}"
        echo "Table ${table}: max_dt=${max_dt}"

        if [ "${max_dt}" = "NONE" ]; then
            NONE_COUNT=$((NONE_COUNT + 1))
        else
            DATE_COUNT_TABLES=$((DATE_COUNT_TABLES + 1))
            if [ -z "${FIRST_DATE_FOUND}" ]; then
                FIRST_DATE_FOUND="${max_dt}"
            fi
        fi
    fi
done

# =====================================================
# 第二步: 严格检查七表状态
# =====================================================
echo
echo "Checking partition consistency across tables..."

# 情况 A: 全部 NONE (7/7)
if [ "${NONE_COUNT}" -eq 7 ]; then
    echo "INFO: All 7 tables are NONE (INITIAL_LOAD_CANDIDATE)"
    STAR_STATE="INITIAL_LOAD_CANDIDATE"
# 情况 B: 全部有日期且一致
elif [ "${NONE_COUNT}" -eq 0 ]; then
    # 检查所有日期是否一致
    MISMATCH_COUNT=0
    for table in "${STAR_TABLES[@]}"; do
        if [ "${TABLE_MAX_DT[${table}]}" != "${FIRST_DATE_FOUND}" ]; then
            MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
        fi
    done

    if [ "${MISMATCH_COUNT}" -gt 0 ]; then
        echo "ERROR: BLOCK_PARTITION_MISMATCH"
        echo "Max partitions are inconsistent across star tables."
        echo "Expected all tables to have max_dt=${FIRST_DATE_FOUND}"
        echo "Table states:"
        for table in "${STAR_TABLES[@]}"; do
            echo "  - ${table}=${TABLE_MAX_DT[${table}]}"
        done
        echo
        echo "Please ensure all tables are at the same date before backfill."
        exit 1
    fi

    echo "INFO: All 7 tables have consistent max_dt=${FIRST_DATE_FOUND} (APPEND_CANDIDATE)"
    STAR_STATE="APPEND_CANDIDATE"
    MAX_DT_ALL_TABLES="${FIRST_DATE_FOUND}"
# 情况 C: 部分 NONE，部分有日期
else
    echo "ERROR: BLOCK_PARTIAL_DATE"
    echo "Some tables have data while others are empty."
    echo "This is an inconsistent state that requires investigation."
    echo "Table states:"
    for table in "${STAR_TABLES[@]}"; do
        echo "  - ${table}=${TABLE_MAX_DT[${table}]}"
    done
    echo
    echo "NONE_COUNT=${NONE_COUNT}, DATE_COUNT=${DATE_COUNT_TABLES}"
    echo "Please ensure all tables are either empty or have consistent data."
    exit 1
fi

# =====================================================
# 第三步: 质量基线检查（仅 APPEND_CANDIDATE 模式）
# =====================================================
if [ "${STAR_STATE}" = "APPEND_CANDIDATE" ]; then
    echo
    echo "Checking quality baseline for max_dt=${MAX_DT_ALL_TABLES}..."

    QUALITY_CHECK_RESULT="$(
        hive --database "${HIVE_DATABASE}" -S -e "
            SELECT
                COUNT(*) AS rule_cnt,
                COUNT(DISTINCT rule_code) AS distinct_rule_cnt,
                COALESCE(SUM(CASE WHEN check_level = 'BLOCK' AND check_status = 'PASS' THEN 1 ELSE 0 END), 0) AS block_pass_cnt,
                COALESCE(SUM(CASE WHEN check_level = 'BLOCK' AND check_status = 'FAIL' THEN 1 ELSE 0 END), 0) AS block_fail_cnt
            FROM star_quality_log_hive
            WHERE dt = '${MAX_DT_ALL_TABLES}';
        " 2>"${HIVE_STDERR}"
    )" || {
        echo "ERROR: Hive quality baseline query failed."
        echo "BLOCK_QUERY_FAILED"
        echo "Hive stderr:"
        cat "${HIVE_STDERR}"
        exit 1
    }

    # 严格解析质量结果
    # 1. 统计非空行数
    NONEMPTY_LINE_COUNT="$(
        printf '%s\n' "${QUALITY_CHECK_RESULT}" |
        awk 'NF > 0 {count++} END {print count + 0}'
    )"

    if [ "${NONEMPTY_LINE_COUNT}" -ne 1 ]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_UNPARSEABLE"
        echo "Quality baseline query returned ${NONEMPTY_LINE_COUNT} non-empty lines (expected exactly 1)."
        echo "Raw result:"
        echo "${QUALITY_CHECK_RESULT}"
        exit 1
    fi

    # 2. 获取唯一非空行
    QUALITY_LINE="$(
        printf '%s\n' "${QUALITY_CHECK_RESULT}" |
        awk 'NF > 0 {print; exit}'
    )"

    # 3. 使用 read 解析四个字段
    read -r RULE_CNT DISTINCT_RULE_CNT BLOCK_PASS_CNT BLOCK_FAIL_CNT EXTRA_FIELD <<< "${QUALITY_LINE}"

    # 4. 检查 EXTRA_FIELD 必须为空
    if [ -n "${EXTRA_FIELD:-}" ]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_UNPARSEABLE"
        echo "Quality baseline query returned extra fields (expected exactly 4 fields)."
        echo "Raw result: ${QUALITY_LINE}"
        exit 1
    fi

    # 5. 检查四个字段全部为非负整数
    if ! [[ "${RULE_CNT:-}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_UNPARSEABLE"
        echo "rule_cnt is not a valid non-negative integer: ${RULE_CNT:-}"
        exit 1
    fi

    if ! [[ "${DISTINCT_RULE_CNT:-}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_UNPARSEABLE"
        echo "distinct_rule_cnt is not a valid non-negative integer: ${DISTINCT_RULE_CNT:-}"
        exit 1
    fi

    if ! [[ "${BLOCK_PASS_CNT:-}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_UNPARSEABLE"
        echo "block_pass_cnt is not a valid non-negative integer: ${BLOCK_PASS_CNT:-}"
        exit 1
    fi

    if ! [[ "${BLOCK_FAIL_CNT:-}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_UNPARSEABLE"
        echo "block_fail_cnt is not a valid non-negative integer: ${BLOCK_FAIL_CNT:-}"
        exit 1
    fi

    echo "Quality baseline for ${MAX_DT_ALL_TABLES}:"
    echo "  rule_cnt=${RULE_CNT}"
    echo "  distinct_rule_cnt=${DISTINCT_RULE_CNT}"
    echo "  block_pass_cnt=${BLOCK_PASS_CNT}"
    echo "  block_fail_cnt=${BLOCK_FAIL_CNT}"

    # 6. 验证质量基线指标
    if [ "${RULE_CNT}" -ne 17 ] || [ "${DISTINCT_RULE_CNT}" -ne 17 ]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_INCOMPLETE"
        echo "Previous date ${MAX_DT_ALL_TABLES} has incomplete quality rules."
        echo "Expected 17 rules, got rule_cnt=${RULE_CNT}, distinct_rule_cnt=${DISTINCT_RULE_CNT}."
        exit 1
    fi

    if [ "${BLOCK_PASS_CNT}" -ne 17 ]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_FAILED"
        echo "Previous date ${MAX_DT_ALL_TABLES} did not pass all BLOCK rules."
        echo "Expected 17 BLOCK PASS, got ${BLOCK_PASS_CNT}."
        exit 1
    fi

    if [ "${BLOCK_FAIL_CNT}" -ne 0 ]; then
        echo "ERROR: BLOCK_LAST_DATE_QUALITY_FAILED"
        echo "Previous date ${MAX_DT_ALL_TABLES} has BLOCK failures."
        echo "Expected 0 BLOCK FAIL, got ${BLOCK_FAIL_CNT}."
        exit 1
    fi

    echo "Quality baseline check passed for ${MAX_DT_ALL_TABLES}."
fi

# =====================================================
# 第四步: 查询 next_dwd_dt 或 DWD MIN(dt)
# =====================================================
echo
echo "Querying DWD business dates..."

NEXT_DWD_DT="NONE"
DWD_MIN_DT="NONE"

if [ "${STAR_STATE}" = "APPEND_CANDIDATE" ]; then
    # 查询 max_dt 之后的第一个真实业务日期
    NEXT_DWD_DT="$(
        hive --database "${HIVE_DATABASE}" -S -e "
            SELECT MIN(dt)
            FROM dwd_retail_clean_hive
            WHERE dt > '${MAX_DT_ALL_TABLES}';
        " 2>"${HIVE_STDERR}"
    )" || {
        echo "ERROR: Hive query for next_dwd_dt failed."
        echo "BLOCK_QUERY_FAILED"
        echo "Hive stderr:"
        cat "${HIVE_STDERR}"
        exit 1
    }

    NEXT_DWD_DT="$(echo "${NEXT_DWD_DT}" | tr -d '[:space:]')"

    if [ -z "${NEXT_DWD_DT}" ] || [ "${NEXT_DWD_DT}" = "NULL" ]; then
        NEXT_DWD_DT="NONE"
    fi

    echo "next_dwd_dt: ${NEXT_DWD_DT}"
elif [ "${STAR_STATE}" = "INITIAL_LOAD_CANDIDATE" ]; then
    # 查询 DWD 最早的业务日期
    DWD_MIN_DT="$(
        hive --database "${HIVE_DATABASE}" -S -e "
            SELECT MIN(dt)
            FROM dwd_retail_clean_hive;
        " 2>"${HIVE_STDERR}"
    )" || {
        echo "ERROR: Hive query for DWD MIN(dt) failed."
        echo "BLOCK_QUERY_FAILED"
        echo "Hive stderr:"
        cat "${HIVE_STDERR}"
        exit 1
    }

    DWD_MIN_DT="$(echo "${DWD_MIN_DT}" | tr -d '[:space:]')"

    if [ -z "${DWD_MIN_DT}" ] || [ "${DWD_MIN_DT}" = "NULL" ]; then
        echo "ERROR: No business dates found in DWD."
        echo "Cannot perform initial load without DWD data."
        exit 1
    fi

    echo "dwd_min_dt: ${DWD_MIN_DT}"
fi

# =====================================================
# 第五步: 验证 START_DATE 是否符合连续追加条件
# =====================================================
echo
echo "Validating START_DATE against existing history..."

START_DATE_TS="$(date -d "${START_DATE}" +%s)"

# 情况 1: 首次部署，所有表都是 NONE
if [ "${STAR_STATE}" = "INITIAL_LOAD_CANDIDATE" ]; then
    echo "INFO: Initial deployment mode (all tables are NONE)."

    # 首次装载必须从 DWD 最早日期开始
    DWD_MIN_DT_TS="$(date -d "${DWD_MIN_DT}" +%s)"
    if [ "${START_DATE_TS}" -gt "${DWD_MIN_DT_TS}" ]; then
        echo "ERROR: BLOCK_INITIAL_LOAD_NOT_FROM_EARLIEST_DWD"
        echo
        echo "START_DATE (${START_DATE}) is later than DWD earliest date (${DWD_MIN_DT})."
        echo "Initial load must start from the earliest DWD date to build complete SCD2 history."
        echo "Starting from a later date would create incomplete customer version chains."
        echo
        echo "Use START_DATE=${DWD_MIN_DT} for initial load."
        exit 1
    fi

    if [ "${START_DATE_TS}" -lt "${DWD_MIN_DT_TS}" ]; then
        echo "ERROR: BLOCK_INITIAL_LOAD_BEFORE_DWD"
        echo
        echo "START_DATE (${START_DATE}) is earlier than DWD earliest date (${DWD_MIN_DT})."
        echo "No DWD data available before ${DWD_MIN_DT}."
        exit 1
    fi

    echo "START_DATE=${START_DATE} equals DWD earliest date. Initial load mode."

# 情况 2: 追加模式，已有历史数据
elif [ "${STAR_STATE}" = "APPEND_CANDIDATE" ]; then
    MAX_DT_TS="$(date -d "${MAX_DT_ALL_TABLES}" +%s)"

    # 情况 2a: START_DATE <= MAX_DT，历史覆盖，阻断
    if [ "${START_DATE_TS}" -le "${MAX_DT_TS}" ]; then
        echo "ERROR: BLOCK_HISTORY_OVERWRITE"
        echo
        echo "START_DATE (${START_DATE}) is less than or equal to current max date (${MAX_DT_ALL_TABLES})."
        echo "This script does not support historical overwrite."
        echo "Current environment already has history. Cannot use ${START_DATE} as backfill start."
        echo
        echo "If you need to rebuild historical data, design a controlled rebuild process."
        exit 1
    fi

    # 情况 2b: NEXT_DWD_DT 为 NONE，说明没有更多 DWD 数据
    if [ "${NEXT_DWD_DT}" = "NONE" ]; then
        echo "ERROR: BLOCK_NO_NEXT_DWD_DT"
        echo
        echo "No business dates found in DWD after max_dim_user_dt=${MAX_DT_ALL_TABLES}."
        echo "Cannot append beyond current max without DWD data."
        exit 1
    fi

    # 情况 2c: START_DATE > NEXT_DWD_DT，跳日，阻断
    NEXT_DWD_DT_TS="$(date -d "${NEXT_DWD_DT}" +%s)"
    if [ "${START_DATE_TS}" -gt "${NEXT_DWD_DT_TS}" ]; then
        echo "ERROR: BLOCK_GAP"
        echo
        echo "START_DATE (${START_DATE}) skips over next DWD business date (${NEXT_DWD_DT})."
        echo "Cannot skip business dates. Must process in ascending order."
        echo
        echo "Use START_DATE=${NEXT_DWD_DT} to continue from the next available date."
        exit 1
    fi

    # 情况 2d: START_DATE = NEXT_DWD_DT，正常追加，允许
    if [ "${START_DATE_TS}" -eq "${NEXT_DWD_DT_TS}" ]; then
        echo "START_DATE=${START_DATE} equals next_dwd_dt=${NEXT_DWD_DT}. Normal append mode."
    fi
fi

# =====================================================
# 第六步: 读取 DWD 真实业务日期
# =====================================================
echo
echo "Reading real business dates from DWD..."

BUSINESS_DATES="$(
    hive --database "${HIVE_DATABASE}" -S -e "
        SELECT DISTINCT dt
        FROM dwd_retail_clean_hive
        WHERE dt >= '${START_DATE}'
          AND dt <= '${END_DATE}'
        ORDER BY dt ASC;
    " 2>"${HIVE_STDERR}"
)" || {
    echo "ERROR: Hive DWD date query failed."
    echo "BLOCK_QUERY_FAILED"
    echo "database=${HIVE_DATABASE}"
    echo "start_date=${START_DATE}"
    echo "end_date=${END_DATE}"
    echo "Hive stderr:"
    cat "${HIVE_STDERR}"
    exit 1
}

if [ -z "${BUSINESS_DATES}" ]; then
    echo "ERROR: no business dates found in DWD for range [${START_DATE}, ${END_DATE}]."
    exit 1
fi

# 验证日期格式
DATE_COUNT=0
while IFS= read -r dt; do
    if [[ -z "${dt}" ]]; then
        continue
    fi
    if ! [[ "${dt}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "ERROR: invalid date format from DWD query: ${dt}"
        echo "Expected format: YYYY-MM-DD"
        exit 1
    fi
    DATE_COUNT=$((DATE_COUNT + 1))
done <<< "${BUSINESS_DATES}"

if [ "${DATE_COUNT}" -eq 0 ]; then
    echo "ERROR: no valid business dates found."
    exit 1
fi

echo "Found ${DATE_COUNT} business dates."

# =====================================================
# 第七步: 只读预览模式
# =====================================================
if [ "${STAR_BACKFILL_DRY_RUN}" = "1" ]; then
    echo
    echo "========================================"
    echo "DRY RUN MODE - No DDL/DML will be executed"
    echo "========================================"
    echo
    echo "Current partition status:"
    for table in "${STAR_TABLES[@]}"; do
        echo "  ${table}: max_dt=${TABLE_MAX_DT[${table}]}"
    done
    echo
    echo "Backfill request:"
    echo "  start_date: ${START_DATE}"
    echo "  end_date: ${END_DATE}"
    echo "  business_date_count: ${DATE_COUNT}"
    echo "  exec_mode: ${STAR_EXEC_MODE}"
    echo
    echo "Business dates to process:"
    echo "${BUSINESS_DATES}" | head -20
    if [ "${DATE_COUNT}" -gt 20 ]; then
        echo "  ... and $((DATE_COUNT - 20)) more dates"
    fi
    echo
    echo "Estimated Hive CLI calls:"
    if [ "${STAR_EXEC_MODE}" = "legacy" ]; then
        echo "  Preflight (table checks + quality baseline): 17 calls"
        echo "    - SHOW TABLES LIKE: 7 calls (one per table)"
        echo "    - SHOW PARTITIONS: 7 calls (one per table)"
        echo "    - Quality baseline query: 1 call"
        echo "    - next_dwd_dt or DWD MIN query: 1 call"
        echo "    - DWD date range query: 1 call"
        echo "  DDL: 6 calls (one-time, separate CLI per table)"
        echo "  DML per date: 8 calls"
        echo "    - 6 SQL files (12, 14, 22, 21, 16, 18): 6 calls"
        echo "    - Quality gate (28_load + query): 2 calls"
        echo "  Total: 17 + 6 + 8N = 23 + 8N calls (N = ${DATE_COUNT} dates)"
    else
        echo "  Preflight (table checks + quality baseline): 17 calls"
        echo "    - SHOW TABLES LIKE: 7 calls (one per table)"
        echo "    - SHOW PARTITIONS: 7 calls (one per table)"
        echo "    - Quality baseline query: 1 call"
        echo "    - next_dwd_dt or DWD MIN query: 1 call"
        echo "    - DWD date range query: 1 call"
        echo "  DDL: 1 call (combined, one-time)"
        echo "  DML per date: 1 call (combined SQL with quality assertion)"
        echo "  Total: 17 + 1 + N = 18 + N calls (N = ${DATE_COUNT} dates)"
    fi
    echo
    echo "Continuous append condition: SATISFIED"
    echo
    echo "========================================"
    echo "DRY RUN completed. No changes made."
    echo "========================================"
    exit 0
fi

# =====================================================
# 第七步: 统一执行 DDL (建表)
# =====================================================
echo
echo "========================================"
echo "Running DDL phase (CREATE TABLE) - once for all dates"
echo "========================================"

# single_session 模式下，拼接 DDL 到一个临时文件
if [ "${STAR_EXEC_MODE}" = "single_session" ]; then
    TEMP_DDL_SQL="$(mktemp /tmp/star_backfill_ddl_XXXXXX.sql)"
    trap 'rm -f "${HIVE_STDERR}" "${TEMP_DDL_SQL}"' EXIT

    echo "-- Combined DDL for star schema tables" > "${TEMP_DDL_SQL}"
    echo "-- Generated at: $(date)" >> "${TEMP_DDL_SQL}"
    echo "-- start_date: ${START_DATE}" >> "${TEMP_DDL_SQL}"
    echo "-- end_date: ${END_DATE}" >> "${TEMP_DDL_SQL}"
    echo "" >> "${TEMP_DDL_SQL}"

    # 拼接 6 个 DDL 文件
    cat "${BASE_DIR}/11_dim_user_scd2_hive.sql" >> "${TEMP_DDL_SQL}"
    echo "" >> "${TEMP_DDL_SQL}"
    cat "${BASE_DIR}/13_dim_product_hive.sql" >> "${TEMP_DDL_SQL}"
    echo "" >> "${TEMP_DDL_SQL}"
    cat "${BASE_DIR}/19_dim_date_hive.sql" >> "${TEMP_DDL_SQL}"
    echo "" >> "${TEMP_DDL_SQL}"
    cat "${BASE_DIR}/20_dim_geo_hive.sql" >> "${TEMP_DDL_SQL}"
    echo "" >> "${TEMP_DDL_SQL}"
    cat "${BASE_DIR}/15_fact_order_hive.sql" >> "${TEMP_DDL_SQL}"
    echo "" >> "${TEMP_DDL_SQL}"
    cat "${BASE_DIR}/17_dws_customer_value_star_hive.sql" >> "${TEMP_DDL_SQL}"
    echo "" >> "${TEMP_DDL_SQL}"

    echo "Executing combined DDL SQL..."
    if ! hive \
        --database "${HIVE_DATABASE}" \
        --hiveconf mapreduce.map.memory.mb="${MAP_MEMORY_MB}" \
        --hiveconf mapreduce.map.java.opts="-Xmx${MAP_JAVA_XMX}" \
        --hiveconf mapreduce.reduce.memory.mb="${REDUCE_MEMORY_MB}" \
        --hiveconf mapreduce.reduce.java.opts="-Xmx${REDUCE_JAVA_XMX}" \
        --hiveconf mapreduce.task.timeout="${TASK_TIMEOUT_MS}" \
        -f "${TEMP_DDL_SQL}"; then
        echo "ERROR: Combined DDL execution failed."
        exit 1
    fi

    echo "DDL phase completed."
else
    # legacy 模式: 每个 DDL 文件单独执行
    run_ddl_sql() {
        local step_name="$1"
        local sql_file="$2"
        local sql_path="${BASE_DIR}/${sql_file}"

        if [ ! -f "${sql_path}" ]; then
            echo "ERROR: SQL file not found: ${sql_path}"
            exit 1
        fi

        echo
        echo "========================================"
        echo "${step_name}"
        echo "SQL: ${sql_file}"
        echo "database: ${HIVE_DATABASE}"
        echo "========================================"

        if ! hive \
            --database "${HIVE_DATABASE}" \
            --hiveconf mapreduce.map.memory.mb="${MAP_MEMORY_MB}" \
            --hiveconf mapreduce.map.java.opts="-Xmx${MAP_JAVA_XMX}" \
            --hiveconf mapreduce.reduce.memory.mb="${REDUCE_MEMORY_MB}" \
            --hiveconf mapreduce.reduce.java.opts="-Xmx${REDUCE_JAVA_XMX}" \
            --hiveconf mapreduce.task.timeout="${TASK_TIMEOUT_MS}" \
            -f "${sql_path}"; then
            echo "ERROR: ${step_name} failed."
            echo "ERROR SQL: ${sql_path}"
            exit 1
        fi
    }

    run_ddl_sql "[DDL-01/06] Create SCD2 user dimension" \
        "11_dim_user_scd2_hive.sql"

    run_ddl_sql "[DDL-02/06] Create product dimension" \
        "13_dim_product_hive.sql"

    run_ddl_sql "[DDL-03/06] Create date dimension" \
        "19_dim_date_hive.sql"

    run_ddl_sql "[DDL-04/06] Create geography dimension" \
        "20_dim_geo_hive.sql"

    run_ddl_sql "[DDL-05/06] Create order fact table" \
        "15_fact_order_hive.sql"

    run_ddl_sql "[DDL-06/06] Create star DWS customer value table" \
        "17_dws_customer_value_star_hive.sql"

    echo
    echo "========================================"
    echo "DDL phase completed."
    echo "========================================"
fi

# =====================================================
# 第八步: 遍历业务日期执行 DML (装载数据)
# =====================================================
echo
echo "========================================"
echo "Running DML phase (LOAD DATA) - per date"
echo "========================================"

PROCESSED=0
FAILED_DATE=""

while IFS= read -r BIZDATE; do
    if [[ -z "${BIZDATE}" ]]; then
        continue
    fi

    PROCESSED=$((PROCESSED + 1))
    echo
    echo "========================================"
    echo "[${PROCESSED}/${DATE_COUNT}] Processing date: ${BIZDATE}"
    echo "========================================"

    if ! HIVE_DATABASE="${HIVE_DATABASE}" \
         BATCH_DT="${BIZDATE}" \
         STAR_DDL_MODE=skip \
         SCD2_GUARD_MODE=skip \
         STAR_EXEC_MODE="${STAR_EXEC_MODE}" \
         MAP_MEMORY_MB="${MAP_MEMORY_MB}" \
         MAP_JAVA_XMX="${MAP_JAVA_XMX}" \
         REDUCE_MEMORY_MB="${REDUCE_MEMORY_MB}" \
         REDUCE_JAVA_XMX="${REDUCE_JAVA_XMX}" \
         TASK_TIMEOUT_MS="${TASK_TIMEOUT_MS}" \
         bash "${BASE_DIR}/run_star_schema_hive.sh" "${BIZDATE}"; then
        FAILED_DATE="${BIZDATE}"
        echo "ERROR: star schema backfill failed on date: ${FAILED_DATE}"
        echo "Processed ${PROCESSED} of ${DATE_COUNT} dates before failure."
        exit 1
    fi
done <<< "${BUSINESS_DATES}"

echo
echo "========================================"
echo "Star schema backfill completed successfully."
echo "start_date: ${START_DATE}"
echo "end_date: ${END_DATE}"
echo "database: ${HIVE_DATABASE}"
echo "dates_processed: ${PROCESSED}"
echo "exec_mode: ${STAR_EXEC_MODE}"
echo "========================================"
