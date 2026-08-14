#!/usr/bin/env bash

# =====================================================
# 文件名：30_backfill_ads_sales_overview_daily.sh
# 功能：范围式回刷销售概览 ADS 指标
# 用法：
#   HIVE_DATABASE=retail_canonical \
#   bash 30_backfill_ads_sales_overview_daily.sh 2009-12-01 2011-12-09
# 说明：
# 1. 整个范围的 ADS DML 只执行一次 Hive CLI；
# 2. 使用动态分区 INSERT OVERWRITE；
# 3. 前置 DWD 检查和后置 ADS 验证使用独立查询；
# 4. 不硬编码行数作为成功条件。
# =====================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/29_ads_sales_overview_daily_hive.sql"

HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"

# MapReduce 资源配置（与项目现有范围 runner 保持一致）
MAP_MEMORY_MB="${MAP_MEMORY_MB:-2048}"
MAP_JAVA_XMX="${MAP_JAVA_XMX:-1536m}"
REDUCE_MEMORY_MB="${REDUCE_MEMORY_MB:-2048}"
REDUCE_JAVA_XMX="${REDUCE_JAVA_XMX:-1536m}"
TASK_TIMEOUT_MS="${TASK_TIMEOUT_MS:-3600000}"

START_DT="${1:-}"
END_DT="${2:-}"

if [[ -z "${START_DT}" || -z "${END_DT}" ]]; then
    echo "错误：缺少日期参数。"
    echo "用法：bash $0 yyyy-MM-dd yyyy-MM-dd"
    exit 1
fi

if [[ ! "${START_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误：START_DT 格式必须为 yyyy-MM-dd，实际：${START_DT}"
    exit 1
fi

if [[ ! "${END_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误：END_DT 格式必须为 yyyy-MM-dd，实际：${END_DT}"
    exit 1
fi

if ! date -d "${START_DT}" +%Y-%m-%d >/dev/null 2>&1; then
    echo "错误：START_DT 不是合法日期：${START_DT}"
    exit 1
fi

if ! date -d "${END_DT}" +%Y-%m-%d >/dev/null 2>&1; then
    echo "错误：END_DT 不是合法日期：${END_DT}"
    exit 1
fi

# 规范化日期格式
START_DT="$(date -d "${START_DT}" +%F)"
END_DT="$(date -d "${END_DT}" +%F)"

if [[ "${START_DT}" > "${END_DT}" ]]; then
    echo "错误：START_DT (${START_DT}) 不能晚于 END_DT (${END_DT})"
    exit 1
fi

if [[ ! -f "${SQL_FILE}" ]]; then
    echo "错误：未找到 ADS SQL 文件：${SQL_FILE}"
    exit 1
fi

echo "=========================================="
echo "开始回刷销售概览 ADS 指标"
echo "Hive 数据库：${HIVE_DATABASE}"
echo "范围：${START_DT} 至 ${END_DT}"
echo "SQL 文件：${SQL_FILE}"
echo "=========================================="

# ------------------------------------------------------------
# 1. 执行前检查：DWD 在范围内存在业务日期
# ------------------------------------------------------------
echo
echo "[1/4] 检查 DWD 在范围内是否存在业务日期..."

DWD_CHECK_OUTPUT="$(
    hive --database "${HIVE_DATABASE}" -S -e "
SELECT
    COUNT(DISTINCT dt) AS dwd_distinct_dt,
    COALESCE(MIN(dt), '__EMPTY__') AS dwd_min_dt,
    COALESCE(MAX(dt), '__EMPTY__') AS dwd_max_dt,
    COALESCE(SUM(amount), 0) AS dwd_sum_amount
FROM dwd_retail_clean_hive
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}';
"
)" || {
    echo "错误：DWD 预检查 Hive 查询失败。"
    exit 1
}

if [[ -z "${DWD_CHECK_OUTPUT}" ]]; then
    echo "错误：DWD 预检查返回空结果。"
    exit 1
fi

DWD_CHECK_LINE="$(echo "${DWD_CHECK_OUTPUT}" | awk 'NF' | tail -n 1)"

# 严格解析：必须恰好 4 个字段
IFS=$'\t' read -r DWD_DISTINCT_DT DWD_MIN_DT DWD_MAX_DT DWD_SUM_AMOUNT EXTRA_FIELD <<< "${DWD_CHECK_LINE}"

if [[ -n "${EXTRA_FIELD:-}" ]]; then
    echo "错误：DWD 预检查返回字段数超过 4 个。"
    echo "原始输出：${DWD_CHECK_OUTPUT}"
    exit 1
fi

# 验证字段格式
if [[ ! "${DWD_DISTINCT_DT}" =~ ^[0-9]+$ ]]; then
    echo "错误：dwd_distinct_dt 不是合法非负整数：${DWD_DISTINCT_DT}"
    exit 1
fi

if [[ "${DWD_DISTINCT_DT}" -eq 0 ]]; then
    if [[ "${DWD_MIN_DT}" != "__EMPTY__" || "${DWD_MAX_DT}" != "__EMPTY__" ]]; then
        echo "错误：DWD 无业务日期时 min_dt/max_dt 应为 __EMPTY__。"
        exit 1
    fi
else
    if [[ ! "${DWD_MIN_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "错误：dwd_min_dt 不是合法日期格式：${DWD_MIN_DT}"
        exit 1
    fi

    if [[ ! "${DWD_MAX_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "错误：dwd_max_dt 不是合法日期格式：${DWD_MAX_DT}"
        exit 1
    fi
fi

# dwd_sum_amount 必须是合法十进制数字（允许负数、小数）
if [[ ! "${DWD_SUM_AMOUNT}" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
    echo "错误：dwd_sum_amount 不是合法十进制数字：${DWD_SUM_AMOUNT}"
    exit 1
fi

echo "DWD 预检查通过："
echo "  distinct_dt=${DWD_DISTINCT_DT}"
echo "  min_dt=${DWD_MIN_DT}"
echo "  max_dt=${DWD_MAX_DT}"
echo "  sum_amount=${DWD_SUM_AMOUNT}"

ADS_TABLE_EXISTS="$(
    hive --database "${HIVE_DATABASE}" -S -e "
SHOW TABLES 'ads_sales_overview_daily_hive';
"
)" || {
    echo "错误：检查 ADS 表是否存在失败。"
    exit 1
}

ADS_OLD_PARTITIONS=""

if [[ -n "${ADS_TABLE_EXISTS}" ]]; then
    ADS_OLD_PARTITIONS="$(
        hive --database "${HIVE_DATABASE}" -S -e "
SHOW PARTITIONS ads_sales_overview_daily_hive;
" | awk -F= -v start="${START_DT}" -v end="${END_DT}" '
$1 == "dt" {
    dt = $2
    if (dt >= start && dt <= end) {
        print dt
    }
}'
    )" || {
        echo "错误：查询 ADS 旧分区失败。"
        exit 1
    }
fi

DROP_PARTITION_CLAUSES=""

while IFS= read -r dt; do
    [[ -z "${dt}" ]] && continue

    if [[ ! "${dt}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "错误：ADS 分区值格式非法：${dt}"
        exit 1
    fi

    if [[ "${dt}" < "${START_DT}" || "${dt}" > "${END_DT}" ]]; then
    echo "错误：ADS 分区 ${dt} 超出回刷范围 ${START_DT} 至 ${END_DT}。"
    exit 1
    fi

    DROP_PARTITION_CLAUSES+=", PARTITION (dt='${dt}')"
done <<< "${ADS_OLD_PARTITIONS}"

DROP_PARTITION_CLAUSES="${DROP_PARTITION_CLAUSES#, }"

if [[ -n "${DROP_PARTITION_CLAUSES}" ]]; then
    echo
    echo "清理回刷范围内的 ADS 旧分区..."

    hive --database "${HIVE_DATABASE}" -S -e "
ALTER TABLE ads_sales_overview_daily_hive
DROP IF EXISTS ${DROP_PARTITION_CLAUSES};
" || {
        echo "错误：删除 ADS 旧分区失败。"
        exit 1
    }
else
    echo
    echo "回刷范围内没有 ADS 旧分区，无需清理。"
fi

# ------------------------------------------------------------
# 2. 执行 ADS SQL（整个范围一次 Hive CLI）
# ------------------------------------------------------------
echo
echo "[2/4] 执行 ADS SQL（范围式动态分区）..."

hive \
    --database "${HIVE_DATABASE}" \
    --hiveconf start_dt="${START_DT}" \
    --hiveconf end_dt="${END_DT}" \
    --hiveconf mapreduce.map.memory.mb="${MAP_MEMORY_MB}" \
    --hiveconf mapreduce.map.java.opts="-Xmx${MAP_JAVA_XMX}" \
    --hiveconf mapreduce.reduce.memory.mb="${REDUCE_MEMORY_MB}" \
    --hiveconf mapreduce.reduce.java.opts="-Xmx${REDUCE_JAVA_XMX}" \
    --hiveconf mapreduce.task.timeout="${TASK_TIMEOUT_MS}" \
    -f "${SQL_FILE}" || {
    echo "错误：ADS SQL 执行失败。"
    exit 1
}

echo "ADS SQL 执行完成。"

# ------------------------------------------------------------
# 3. 执行后验证：ADS 表指标
# ------------------------------------------------------------
echo
echo "[3/4] 验证 ADS 表指标..."

ADS_VERIFY_OUTPUT="$(
    hive --database "${HIVE_DATABASE}" -S -e "
SELECT
    COUNT(*) AS ads_row_count,
    COUNT(DISTINCT dt) AS ads_distinct_dt,
    COALESCE(MIN(dt), '__EMPTY__') AS ads_min_dt,
    COALESCE(MAX(dt), '__EMPTY__') AS ads_max_dt,
    COALESCE(SUM(total_sales), 0) AS ads_sum_total_sales
FROM ads_sales_overview_daily_hive
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}';
"
)" || {
    echo "错误：ADS 验证 Hive 查询失败。"
    exit 1
}

if [[ -z "${ADS_VERIFY_OUTPUT}" ]]; then
    echo "错误：ADS 验证返回空结果。"
    exit 1
fi

ADS_VERIFY_LINE="$(echo "${ADS_VERIFY_OUTPUT}" | awk 'NF' | tail -n 1)"

# 严格解析：必须恰好 5 个字段
IFS=$'\t' read -r ADS_ROW_COUNT ADS_DISTINCT_DT ADS_MIN_DT ADS_MAX_DT ADS_SUM_TOTAL_SALES EXTRA_FIELD <<< "${ADS_VERIFY_LINE}"

if [[ -n "${EXTRA_FIELD:-}" ]]; then
    echo "错误：ADS 验证返回字段数超过 5 个。"
    echo "原始输出：${ADS_VERIFY_OUTPUT}"
    exit 1
fi

# 验证字段格式
if [[ ! "${ADS_ROW_COUNT}" =~ ^[0-9]+$ ]]; then
    echo "错误：ads_row_count 不是合法非负整数：${ADS_ROW_COUNT}"
    exit 1
fi

if [[ ! "${ADS_DISTINCT_DT}" =~ ^[0-9]+$ ]]; then
    echo "错误：ads_distinct_dt 不是合法非负整数：${ADS_DISTINCT_DT}"
    exit 1
fi

if [[ "${ADS_DISTINCT_DT}" -eq 0 ]]; then
    if [[ "${ADS_MIN_DT}" != "__EMPTY__" || "${ADS_MAX_DT}" != "__EMPTY__" ]]; then
        echo "错误：ADS 无业务日期时 min_dt/max_dt 应为 __EMPTY__。"
        exit 1
    fi
else
    if [[ ! "${ADS_MIN_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "错误：ads_min_dt 不是合法日期格式：${ADS_MIN_DT}"
        exit 1
    fi

    if [[ ! "${ADS_MAX_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "错误：ads_max_dt 不是合法日期格式：${ADS_MAX_DT}"
        exit 1
    fi
fi

# ads_sum_total_sales 必须是合法十进制数字（允许负数、小数）
if [[ ! "${ADS_SUM_TOTAL_SALES}" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
    echo "错误：ads_sum_total_sales 不是合法十进制数字：${ADS_SUM_TOTAL_SALES}"
    exit 1
fi

echo "ADS 验证结果："
echo "  row_count=${ADS_ROW_COUNT}"
echo "  distinct_dt=${ADS_DISTINCT_DT}"
echo "  min_dt=${ADS_MIN_DT}"
echo "  max_dt=${ADS_MAX_DT}"
echo "  sum_total_sales=${ADS_SUM_TOTAL_SALES}"

# ------------------------------------------------------------
# 4. 对账：ADS vs DWD
# ------------------------------------------------------------
echo
echo "[4/4] 对账 ADS vs DWD..."

BLOCK_REASON=""

if [[ "${ADS_ROW_COUNT}" -ne "${ADS_DISTINCT_DT}" ]]; then
    BLOCK_REASON="ADS row_count (${ADS_ROW_COUNT}) != distinct_dt (${ADS_DISTINCT_DT})"
fi

if [[ "${ADS_DISTINCT_DT}" -ne "${DWD_DISTINCT_DT}" ]]; then
    if [[ -n "${BLOCK_REASON}" ]]; then
        BLOCK_REASON="${BLOCK_REASON}; "
    fi
    BLOCK_REASON="${BLOCK_REASON}ADS distinct_dt (${ADS_DISTINCT_DT}) != DWD distinct_dt (${DWD_DISTINCT_DT})"
fi

if [[ "${ADS_MIN_DT}" != "${DWD_MIN_DT}" ]]; then
    if [[ -n "${BLOCK_REASON}" ]]; then
        BLOCK_REASON="${BLOCK_REASON}; "
    fi
    BLOCK_REASON="${BLOCK_REASON}ADS min_dt (${ADS_MIN_DT}) != DWD min_dt (${DWD_MIN_DT})"
fi

if [[ "${ADS_MAX_DT}" != "${DWD_MAX_DT}" ]]; then
    if [[ -n "${BLOCK_REASON}" ]]; then
        BLOCK_REASON="${BLOCK_REASON}; "
    fi
    BLOCK_REASON="${BLOCK_REASON}ADS max_dt (${ADS_MAX_DT}) != DWD max_dt (${DWD_MAX_DT})"
fi

# 金额对账：允许 0.01 差异
ADS_SUM_DECIMAL="${ADS_SUM_TOTAL_SALES}"
DWD_SUM_DECIMAL="${DWD_SUM_AMOUNT}"

DIFF_RESULT="$(
    awk -v ads="${ADS_SUM_DECIMAL}" -v dwd="${DWD_SUM_DECIMAL}" 'BEGIN {
        diff = ads - dwd
        if (diff < 0) diff = -diff
        if (diff > 0.01) print "FAIL"
        else print "PASS"
    }'
)"

if [[ "${DIFF_RESULT}" == "FAIL" ]]; then
    if [[ -n "${BLOCK_REASON}" ]]; then
        BLOCK_REASON="${BLOCK_REASON}; "
    fi
    BLOCK_REASON="${BLOCK_REASON}ADS sum(total_sales) (${ADS_SUM_TOTAL_SALES}) vs DWD sum(amount) (${DWD_SUM_AMOUNT}) 差异超过 0.01"
fi

if [[ -n "${BLOCK_REASON}" ]]; then
    echo "=========================================="
    echo "BLOCK：对账失败"
    echo "原因：${BLOCK_REASON}"
    echo "=========================================="
    exit 1
fi

echo "=========================================="
echo "PASS：ADS 范围式回刷并对账通过"
echo "  hive_database=${HIVE_DATABASE}"
echo "  start_dt=${START_DT}"
echo "  end_dt=${END_DT}"
echo "  ads_row_count=${ADS_ROW_COUNT}"
echo "  ads_distinct_dt=${ADS_DISTINCT_DT}"
echo "  ads_min_dt=${ADS_MIN_DT}"
echo "  ads_max_dt=${ADS_MAX_DT}"
echo "  ads_sum_total_sales=${ADS_SUM_TOTAL_SALES}"
echo "  dwd_sum_amount=${DWD_SUM_AMOUNT}"
echo "=========================================="
