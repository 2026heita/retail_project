#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_star_schema_hive.sh
# 功能: 构建指定业务日期的星型模型，并执行质量门禁
# 用法:
#   bash run_star_schema_hive.sh 2026-04-08
#
# 环境变量:
#   STAR_DDL_MODE: run (default) | skip
#     run  = 执行建表 SQL + 装载 SQL
#     skip = 只执行装载 SQL (适用于区间回刷)
#
#   STAR_EXEC_MODE: legacy (default) | single_session
#     legacy         = 每个 SQL 文件启动一个 Hive CLI (当前行为)
#     single_session = 每个业务日期只启动一个 Hive CLI，拼接所有 SQL
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 可选环境变量
HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"
BATCH_DT="${BATCH_DT:-${BIZDATE}}"
STAR_DDL_MODE="${STAR_DDL_MODE:-run}"
STAR_EXEC_MODE="${STAR_EXEC_MODE:-legacy}"

# 可配置资源参数
MAP_MEMORY_MB="${MAP_MEMORY_MB:-2048}"
MAP_JAVA_XMX="${MAP_JAVA_XMX:-1536m}"
REDUCE_MEMORY_MB="${REDUCE_MEMORY_MB:-2048}"
REDUCE_JAVA_XMX="${REDUCE_JAVA_XMX:-1536m}"
TASK_TIMEOUT_MS="${TASK_TIMEOUT_MS:-3600000}"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_star_schema_hive.sh YYYY-MM-DD"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

# 验证 STAR_DDL_MODE
if [ "${STAR_DDL_MODE}" != "run" ] && [ "${STAR_DDL_MODE}" != "skip" ]; then
    echo "ERROR: invalid STAR_DDL_MODE: ${STAR_DDL_MODE}"
    echo "Valid values: run, skip"
    exit 1
fi

# 验证 STAR_EXEC_MODE
if [ "${STAR_EXEC_MODE}" != "legacy" ] && [ "${STAR_EXEC_MODE}" != "single_session" ]; then
    echo "ERROR: invalid STAR_EXEC_MODE: ${STAR_EXEC_MODE}"
    echo "Valid values: legacy, single_session"
    exit 1
fi

# 导出环境变量供子脚本使用
export HIVE_DATABASE
export BATCH_DT
export STAR_DDL_MODE
export STAR_EXEC_MODE

# =====================================================
# SCD2 单日重跑保护
# =====================================================
if [ "${SCD2_GUARD_MODE:-enforce}" != "skip" ]; then
    echo "========================================"
    echo "Running SCD2 backfill guard"
    echo "bizdate: ${BIZDATE}"
    echo "database: ${HIVE_DATABASE}"
    echo "exec_mode: ${STAR_EXEC_MODE}"
    echo "========================================"
    if ! HIVE_DATABASE="${HIVE_DATABASE}" \
         bash "${BASE_DIR}/check_scd2_backfill_guard.sh" "${BIZDATE}"; then
        echo "ERROR: SCD2 backfill guard blocked execution."
        exit 1
    fi
fi

# =====================================================
# Legacy 模式: 每个 SQL 文件启动一个 Hive CLI
# =====================================================
run_hive_sql() {
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
    echo "bizdate: ${BIZDATE}"
    echo "database: ${HIVE_DATABASE}"
    echo "ddl_mode: ${STAR_DDL_MODE}"
    echo "exec_mode: ${STAR_EXEC_MODE}"
    echo "========================================"

    if ! hive \
        --database "${HIVE_DATABASE}" \
        --hiveconf bizdate="${BIZDATE}" \
        --hiveconf batch_dt="${BATCH_DT}" \
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

# =====================================================
# Single Session 模式: 拼接所有 SQL 到一个临时文件
# =====================================================
# Global temp file variables (must outlive function scope for EXIT trap)
TEMP_SQL=""
TEMP_DDL_SQL=""

cleanup_star_temp_files() {
    if [ -n "${TEMP_SQL:-}" ]; then
        rm -f -- "${TEMP_SQL}"
    fi
    if [ -n "${TEMP_DDL_SQL:-}" ]; then
        rm -f -- "${TEMP_DDL_SQL}"
    fi
}

trap cleanup_star_temp_files EXIT

run_single_session() {

    echo
    echo "========================================"
    echo "Single Session Mode: Preparing combined SQL"
    echo "bizdate: ${BIZDATE}"
    echo "database: ${HIVE_DATABASE}"
    echo "ddl_mode: ${STAR_DDL_MODE}"
    echo "========================================"

    # DDL 阶段 (如果需要)
    if [ "${STAR_DDL_MODE}" = "run" ]; then
        TEMP_DDL_SQL="$(mktemp /tmp/star_ddl_XXXXXX.sql)"

        echo "-- Combined DDL for star schema tables" > "${TEMP_DDL_SQL}"
        echo "-- Generated at: $(date)" >> "${TEMP_DDL_SQL}"
        echo "-- bizdate: ${BIZDATE}" >> "${TEMP_DDL_SQL}"
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
            --hiveconf bizdate="${BIZDATE}" \
            --hiveconf batch_dt="${BATCH_DT}" \
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
    fi

    # DML 阶段: 拼接 7 个装载 SQL
    TEMP_SQL="$(mktemp /tmp/star_dml_XXXXXX.sql)"

    echo "-- Combined DML for star schema loading" > "${TEMP_SQL}"
    echo "-- Generated at: $(date)" >> "${TEMP_SQL}"
    echo "-- bizdate: ${BIZDATE}" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    # 按顺序拼接 7 个 SQL 文件，每个前增加阶段标记
    echo "-- [1/7] Load SCD2 user dimension" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_01_DIM_USER' AS star_stage;" >> "${TEMP_SQL}"
    cat "${BASE_DIR}/12_load_dim_user_scd2_hive.sql" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    echo "-- [2/7] Load product dimension" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_02_DIM_PRODUCT' AS star_stage;" >> "${TEMP_SQL}"
    cat "${BASE_DIR}/14_load_dim_product_hive.sql" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    echo "-- [3/7] Load date dimension" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_03_DIM_DATE' AS star_stage;" >> "${TEMP_SQL}"
    cat "${BASE_DIR}/22_load_dim_date_hive.sql" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    echo "-- [4/7] Load geography dimension" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_04_DIM_GEO' AS star_stage;" >> "${TEMP_SQL}"
    cat "${BASE_DIR}/21_load_dim_geo_hive.sql" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    echo "-- [5/7] Load order fact table" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_05_FACT_ORDER' AS star_stage;" >> "${TEMP_SQL}"
    cat "${BASE_DIR}/16_load_fact_order_hive.sql" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    echo "-- [6/7] Load star DWS customer value" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_06_STAR_DWS' AS star_stage;" >> "${TEMP_SQL}"
    cat "${BASE_DIR}/18_load_dws_customer_value_star_hive.sql" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    echo "-- [7/7] Load star quality log" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_07_QUALITY_LOG' AS star_stage;" >> "${TEMP_SQL}"
    cat "${BASE_DIR}/28_load_star_quality_log_hive.sql" >> "${TEMP_SQL}"
    echo "" >> "${TEMP_SQL}"

    # 追加质量门禁检查
    echo "-- [8/8] Quality gate assertion" >> "${TEMP_SQL}"
    echo "SELECT 'STAR_STAGE=DML_08_QUALITY_ASSERT' AS star_stage;" >> "${TEMP_SQL}"
    cat >> "${TEMP_SQL}" <<EOF

-- Assert quality gate: 17 rules, all BLOCK rules PASS
SELECT ASSERT_TRUE(
    rule_cnt = 17
    AND distinct_rule_cnt = 17
    AND block_pass_cnt = 17
    AND block_fail_cnt = 0
)
FROM (
    SELECT
        COUNT(*) AS rule_cnt,
        COUNT(DISTINCT rule_code) AS distinct_rule_cnt,
        COALESCE(
            SUM(
                CASE
                    WHEN check_level = 'BLOCK'
                    AND check_status = 'PASS'
                    THEN 1 ELSE 0
                END
            ),
            0
        ) AS block_pass_cnt,
        COALESCE(
            SUM(
                CASE
                    WHEN check_level = 'BLOCK'
                    AND check_status = 'FAIL'
                    THEN 1 ELSE 0
                END
            ),
            0
        ) AS block_fail_cnt
    FROM star_quality_log_hive
    WHERE dt = '${BIZDATE}'
) q;
EOF

    echo "Executing combined DML SQL..."
    if ! hive \
        --database "${HIVE_DATABASE}" \
        --hiveconf bizdate="${BIZDATE}" \
        --hiveconf batch_dt="${BATCH_DT}" \
        --hiveconf mapreduce.map.memory.mb="${MAP_MEMORY_MB}" \
        --hiveconf mapreduce.map.java.opts="-Xmx${MAP_JAVA_XMX}" \
        --hiveconf mapreduce.reduce.memory.mb="${REDUCE_MEMORY_MB}" \
        --hiveconf mapreduce.reduce.java.opts="-Xmx${REDUCE_JAVA_XMX}" \
        --hiveconf mapreduce.task.timeout="${TASK_TIMEOUT_MS}" \
        -f "${TEMP_SQL}"; then
        echo "ERROR: Combined DML execution failed for bizdate=${BIZDATE}."
        echo "Check the last STAR_STAGE marker in Hive output to locate the failure phase."
        echo "Expected stages: DML_01_DIM_USER .. DML_07_QUALITY_LOG, DML_08_QUALITY_ASSERT."
        echo "Also check star_quality_log_hive where dt='${BIZDATE}' for quality details."
        exit 1
    fi

    echo "Single session execution completed successfully."
}

# =====================================================
# 主执行流程
# =====================================================
echo "========================================"
echo "Start star schema pipeline"
echo "bizdate: ${BIZDATE}"
echo "database: ${HIVE_DATABASE}"
echo "ddl_mode: ${STAR_DDL_MODE}"
echo "exec_mode: ${STAR_EXEC_MODE}"
echo "========================================"

if [ "${STAR_EXEC_MODE}" = "legacy" ]; then
    # Legacy 模式: 每个 SQL 文件单独执行

    # DDL 阶段 (建表)
    if [ "${STAR_DDL_MODE}" = "run" ]; then
        echo
        echo "========================================"
        echo "Running DDL phase (CREATE TABLE)"
        echo "========================================"

        run_hive_sql "[DDL-01/06] Create SCD2 user dimension" \
            "11_dim_user_scd2_hive.sql"

        run_hive_sql "[DDL-02/06] Create product dimension" \
            "13_dim_product_hive.sql"

        run_hive_sql "[DDL-03/06] Create date dimension" \
            "19_dim_date_hive.sql"

        run_hive_sql "[DDL-04/06] Create geography dimension" \
            "20_dim_geo_hive.sql"

        run_hive_sql "[DDL-05/06] Create order fact table" \
            "15_fact_order_hive.sql"

        run_hive_sql "[DDL-06/06] Create star DWS customer value table" \
            "17_dws_customer_value_star_hive.sql"
    else
        echo
        echo "========================================"
        echo "Skipping DDL phase (STAR_DDL_MODE=skip)"
        echo "========================================"
    fi

    # DML 阶段 (装载数据)
    echo
    echo "========================================"
    echo "Running DML phase (LOAD DATA)"
    echo "========================================"

    run_hive_sql "[DML-01/06] Load SCD2 user dimension partition" \
        "12_load_dim_user_scd2_hive.sql"

    run_hive_sql "[DML-02/06] Load product dimension partition" \
        "14_load_dim_product_hive.sql"

    run_hive_sql "[DML-03/06] Load date dimension partition" \
        "22_load_dim_date_hive.sql"

    run_hive_sql "[DML-04/06] Load geography dimension partition" \
        "21_load_dim_geo_hive.sql"

    run_hive_sql "[DML-05/06] Load order fact partition" \
        "16_load_fact_order_hive.sql"

    run_hive_sql "[DML-06/06] Load star DWS customer value partition" \
        "18_load_dws_customer_value_star_hive.sql"

    # 质量门禁
    echo
    echo "========================================"
    echo "Run star schema quality gate"
    echo "bizdate: ${BIZDATE}"
    echo "========================================"

    if [ ! -f "${BASE_DIR}/run_star_quality_gate_hive.sh" ]; then
        echo "ERROR: quality gate script not found:"
        echo "${BASE_DIR}/run_star_quality_gate_hive.sh"
        exit 1
    fi

    if ! bash "${BASE_DIR}/run_star_quality_gate_hive.sh" "${BIZDATE}"; then
        echo "ERROR: star schema pipeline blocked by quality gate."
        exit 1
    fi

elif [ "${STAR_EXEC_MODE}" = "single_session" ]; then
    # Single Session 模式: 拼接所有 SQL 到一个 Hive CLI
    run_single_session
fi

echo
echo "========================================"
echo "Star schema pipeline completed successfully."
echo "bizdate: ${BIZDATE}"
echo "database: ${HIVE_DATABASE}"
echo "ddl_mode: ${STAR_DDL_MODE}"
echo "exec_mode: ${STAR_EXEC_MODE}"
echo "========================================"
