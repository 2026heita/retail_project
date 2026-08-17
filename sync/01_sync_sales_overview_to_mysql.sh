#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# 文件名：01_sync_sales_overview_to_mysql.sh
# 功能：将 Hive ADS 经营总览指标同步到 MySQL（单日）
# 用法：
#   HIVE_DATABASE=retail_canonical \
#   bash 01_sync_sales_overview_to_mysql.sh 2010-03-04
# ============================================================

BIZDATE="${1:-}"

HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"
SOURCE_SYSTEM="${SOURCE_SYSTEM:-}"

MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-retail_sync_user}"
MYSQL_DB="${MYSQL_DB:-retail_bi}"
MYSQL_TABLE="bi_sales_overview_daily"

if [[ -z "${BIZDATE}" ]]; then
    echo "错误：缺少业务日期。"
    echo "用法：bash $0 yyyy-MM-dd"
    exit 1
fi

if [[ ! "${BIZDATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误：业务日期格式必须为 yyyy-MM-dd。"
    exit 1
fi

# canonical 数据库允许使用明确且安全的默认来源标识。
# 其他 Hive 数据库的数据来源无法由数据库名可靠推断，
# 必须由调用方显式声明，避免误标为 canonical 数据。
if [[ -z "${SOURCE_SYSTEM}" ]]; then
    if [[ "${HIVE_DATABASE}" == "retail_canonical" ]]; then
        SOURCE_SYSTEM="retail_canonical_ads"
    else
        echo "错误：非 canonical Hive 数据库必须显式设置 SOURCE_SYSTEM。"
        echo "当前 HIVE_DATABASE=${HIVE_DATABASE}"
        echo "示例：SOURCE_SYSTEM=local_sample_ads HIVE_DATABASE=default bash $0 ${BIZDATE}"
        exit 1
    fi
fi

echo "=========================================="
echo "开始同步经营总览数据"
echo "业务日期：${BIZDATE}"
echo "hive_database：${HIVE_DATABASE}"
echo "source_system：${SOURCE_SYSTEM}"
echo "=========================================="

# ------------------------------------------------------------
# 1. 从 Hive ADS 中读取指定日期数据
# ------------------------------------------------------------
HIVE_OUTPUT="$(
    hive --database "${HIVE_DATABASE}" -S -e "
SELECT
    CONCAT_WS(
        '\t',
        CAST(dt AS STRING),
        CAST(total_sales AS STRING),
        CAST(total_orders AS STRING),
        CAST(total_customers AS STRING),
        CAST(total_quantity AS STRING),
        CAST(avg_order_value AS STRING)
    )
FROM ads_sales_overview_daily_hive
WHERE dt = '${BIZDATE}';
"
)" || {
    echo "错误：Hive 查询失败，退出。"
    exit 1
}

mapfile -t SOURCE_ROWS < <(echo "${HIVE_OUTPUT}" | awk 'NF')

SOURCE_COUNT="${#SOURCE_ROWS[@]}"

if [[ "${SOURCE_COUNT}" -ne 1 ]]; then
    echo "错误：Hive ADS 中业务日期 ${BIZDATE} 应有且只能有一行。"
    echo "实际行数：${SOURCE_COUNT}"
    exit 1
fi

SOURCE_ROW="${SOURCE_ROWS[0]}"

IFS=$'\t' read -r \
    DT \
    TOTAL_SALES \
    TOTAL_ORDERS \
    TOTAL_CUSTOMERS \
    TOTAL_QUANTITY \
    AVG_ORDER_VALUE \
    <<< "${SOURCE_ROW}"

echo "Hive 源端数据："
echo "dt=${DT}"
echo "total_sales=${TOTAL_SALES}"
echo "total_orders=${TOTAL_ORDERS}"
echo "total_customers=${TOTAL_CUSTOMERS}"
echo "total_quantity=${TOTAL_QUANTITY}"
echo "avg_order_value=${AVG_ORDER_VALUE}"

# ------------------------------------------------------------
# 2. 获取 MySQL 密码
# ------------------------------------------------------------
if [[ -z "${MYSQL_PASSWORD:-}" ]]; then
    read -r -s -p "请输入 retail_sync_user 的 MySQL 密码：" MYSQL_PASSWORD
    echo
fi

MYSQL_CNF="$(mktemp)"

cleanup() {
    unset MYSQL_PASSWORD

    if [[ -f "${MYSQL_CNF}" ]]; then
        if command -v shred >/dev/null 2>&1; then
            shred -u "${MYSQL_CNF}"
        else
            rm -f "${MYSQL_CNF}"
        fi
    fi
}

trap cleanup EXIT

cat > "${MYSQL_CNF}" <<EOF
[client]
host=${MYSQL_HOST}
port=${MYSQL_PORT}
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
default-character-set=utf8mb4
EOF

chmod 600 "${MYSQL_CNF}"

# ------------------------------------------------------------
# 3. 写入 MySQL
# 主键已存在时更新，实现指定日期幂等同步
# ------------------------------------------------------------
mysql \
    --defaults-extra-file="${MYSQL_CNF}" \
    --database="${MYSQL_DB}" <<SQL
INSERT INTO ${MYSQL_TABLE} (
    dt,
    total_sales,
    total_orders,
    total_customers,
    total_quantity,
    avg_order_value,
    source_system
)
VALUES (
    '${DT}',
    ${TOTAL_SALES},
    ${TOTAL_ORDERS},
    ${TOTAL_CUSTOMERS},
    ${TOTAL_QUANTITY},
    ${AVG_ORDER_VALUE},
    '${SOURCE_SYSTEM}'
)
ON DUPLICATE KEY UPDATE
    total_sales = ${TOTAL_SALES},
    total_orders = ${TOTAL_ORDERS},
    total_customers = ${TOTAL_CUSTOMERS},
    total_quantity = ${TOTAL_QUANTITY},
    avg_order_value = ${AVG_ORDER_VALUE},
    source_system = '${SOURCE_SYSTEM}';
SQL

echo "MySQL 写入完成。"

# ------------------------------------------------------------
# 4. 检查目标端行数
# ------------------------------------------------------------
TARGET_COUNT="$(
    mysql \
        --defaults-extra-file="${MYSQL_CNF}" \
        --database="${MYSQL_DB}" \
        --batch \
        --skip-column-names \
        -e "
SELECT COUNT(*)
FROM ${MYSQL_TABLE}
WHERE dt = '${BIZDATE}';
"
)"

if [[ "${TARGET_COUNT}" -ne 1 ]]; then
    echo "错误：MySQL 目标表中应有且只能有一行。"
    echo "实际行数：${TARGET_COUNT}"
    exit 1
fi

# ------------------------------------------------------------
# 5. 读取 MySQL 数据并与 Hive 对账
# ------------------------------------------------------------
TARGET_ROW="$(
    mysql \
        --defaults-extra-file="${MYSQL_CNF}" \
        --database="${MYSQL_DB}" \
        --batch \
        --raw \
        --skip-column-names \
        -e "
SELECT
    CONCAT_WS(
        '\t',
        DATE_FORMAT(dt, '%Y-%m-%d'),
        CAST(total_sales AS CHAR),
        CAST(total_orders AS CHAR),
        CAST(total_customers AS CHAR),
        CAST(total_quantity AS CHAR),
        CAST(avg_order_value AS CHAR)
    )
FROM ${MYSQL_TABLE}
WHERE dt = '${BIZDATE}';
"
)"

echo "MySQL 目标端数据："
echo "${TARGET_ROW}"

IFS=$'\t' read -r \
    TARGET_DT \
    TARGET_SALES \
    TARGET_ORDERS \
    TARGET_CUSTOMERS \
    TARGET_QUANTITY \
    TARGET_AVG \
    <<< "${TARGET_ROW}"

# DECIMAL 字段按数值语义比较，避免 341.4 与 341.40 这类展示格式差异误报。
# 当前业务字段为 DECIMAL(18,2)，0.001 小于最小有效差异 0.01。
decimal_equal() {
    local left="$1"
    local right="$2"

    awk -v a="${left}" -v b="${right}" '
        BEGIN {
            diff = a - b;
            if (diff < 0) {
                diff = -diff;
            }
            exit !(diff <= 0.001);
        }
    '
}

MISMATCH_COUNT=0

if [[ "${DT}" != "${TARGET_DT}" ]]; then
    echo "dt 不一致：Hive=${DT}, MySQL=${TARGET_DT}"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
fi

if ! decimal_equal "${TOTAL_SALES}" "${TARGET_SALES}"; then
    echo "total_sales 不一致：Hive=${TOTAL_SALES}, MySQL=${TARGET_SALES}"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
fi

if [[ "${TOTAL_ORDERS}" != "${TARGET_ORDERS}" ]]; then
    echo "total_orders 不一致：Hive=${TOTAL_ORDERS}, MySQL=${TARGET_ORDERS}"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
fi

if [[ "${TOTAL_CUSTOMERS}" != "${TARGET_CUSTOMERS}" ]]; then
    echo "total_customers 不一致：Hive=${TOTAL_CUSTOMERS}, MySQL=${TARGET_CUSTOMERS}"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
fi

if [[ "${TOTAL_QUANTITY}" != "${TARGET_QUANTITY}" ]]; then
    echo "total_quantity 不一致：Hive=${TOTAL_QUANTITY}, MySQL=${TARGET_QUANTITY}"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
fi

if ! decimal_equal "${AVG_ORDER_VALUE}" "${TARGET_AVG}"; then
    echo "avg_order_value 不一致：Hive=${AVG_ORDER_VALUE}, MySQL=${TARGET_AVG}"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
fi

if [[ "${MISMATCH_COUNT}" -gt 0 ]]; then
    echo "同步失败：Hive 与 MySQL 存在 ${MISMATCH_COUNT} 个字段不一致。"
    exit 1
fi

echo "=========================================="
echo "同步并对账通过：PASS"
echo "业务日期：${BIZDATE}"
echo "=========================================="
