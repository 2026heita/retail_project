#!/usr/bin/env bash

set -Eeuo pipefail

BIZDATE="${1:-}"

HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"
SOURCE_SYSTEM="${SOURCE_SYSTEM:-retail_canonical_anomaly_ads}"

MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-retail_sync_user}"
MYSQL_DB="${MYSQL_DB:-retail_bi}"
MYSQL_TABLE="bi_sales_anomaly_daily"

if [[ -z "${BIZDATE}" ]]; then
    echo "错误：缺少业务日期。"
    echo "用法：bash $0 yyyy-MM-dd"
    exit 1
fi

if [[ ! "${BIZDATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误：业务日期格式必须为 yyyy-MM-dd。"
    exit 1
fi

echo "=========================================="
echo "开始同步经营异常数据"
echo "业务日期：${BIZDATE}"
echo "hive_database：${HIVE_DATABASE}"
echo "source_system：${SOURCE_SYSTEM}"
echo "=========================================="

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
        CAST(avg_order_value AS STRING),
        COALESCE(CAST(prev_dt AS STRING), ''),
        COALESCE(CAST(prev_sales AS STRING), ''),
        COALESCE(CAST(sales_change_pct AS STRING), ''),
        COALESCE(CAST(sales_loss_amount AS STRING), ''),
        COALESCE(CAST(orders_change_pct AS STRING), ''),
        COALESCE(CAST(customers_change_pct AS STRING), ''),
        COALESCE(CAST(quantity_change_pct AS STRING), ''),
        COALESCE(CAST(aov_change_pct AS STRING), ''),
        COALESCE(CAST(anomaly_level AS STRING), ''),
        COALESCE(CAST(primary_driver AS STRING), '')
    )
FROM ads_sales_anomaly_daily_hive
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
    PREV_DT \
    PREV_SALES \
    SALES_CHANGE_PCT \
    SALES_LOSS_AMOUNT \
    ORDERS_CHANGE_PCT \
    CUSTOMERS_CHANGE_PCT \
    QUANTITY_CHANGE_PCT \
    AOV_CHANGE_PCT \
    ANOMALY_LEVEL \
    PRIMARY_DRIVER \
    <<< "${SOURCE_ROW}"

echo "Hive 源端数据："
echo "dt=${DT}"
echo "sales_change_pct=${SALES_CHANGE_PCT}"
echo "sales_loss_amount=${SALES_LOSS_AMOUNT}"
echo "anomaly_level=${ANOMALY_LEVEL}"
echo "primary_driver=${PRIMARY_DRIVER}"

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
    prev_dt,
    prev_sales,
    sales_change_pct,
    sales_loss_amount,
    orders_change_pct,
    customers_change_pct,
    quantity_change_pct,
    aov_change_pct,
    anomaly_level,
    primary_driver,
    source_system
)
VALUES (
    '${DT}',
    ${TOTAL_SALES},
    ${TOTAL_ORDERS},
    ${TOTAL_CUSTOMERS},
    ${TOTAL_QUANTITY},
    ${AVG_ORDER_VALUE},
    NULLIF('${PREV_DT}', ''),
    NULLIF('${PREV_SALES}', ''),
    NULLIF('${SALES_CHANGE_PCT}', ''),
    NULLIF('${SALES_LOSS_AMOUNT}', ''),
    NULLIF('${ORDERS_CHANGE_PCT}', ''),
    NULLIF('${CUSTOMERS_CHANGE_PCT}', ''),
    NULLIF('${QUANTITY_CHANGE_PCT}', ''),
    NULLIF('${AOV_CHANGE_PCT}', ''),
    '${ANOMALY_LEVEL}',
    NULLIF('${PRIMARY_DRIVER}', ''),
    '${SOURCE_SYSTEM}'
)
ON DUPLICATE KEY UPDATE
    total_sales = VALUES(total_sales),
    total_orders = VALUES(total_orders),
    total_customers = VALUES(total_customers),
    total_quantity = VALUES(total_quantity),
    avg_order_value = VALUES(avg_order_value),
    prev_dt = VALUES(prev_dt),
    prev_sales = VALUES(prev_sales),
    sales_change_pct = VALUES(sales_change_pct),
    sales_loss_amount = VALUES(sales_loss_amount),
    orders_change_pct = VALUES(orders_change_pct),
    customers_change_pct = VALUES(customers_change_pct),
    quantity_change_pct = VALUES(quantity_change_pct),
    aov_change_pct = VALUES(aov_change_pct),
    anomaly_level = VALUES(anomaly_level),
    primary_driver = VALUES(primary_driver),
    source_system = VALUES(source_system);
SQL

echo "MySQL 写入完成。"

TARGET_COUNT="$(
    mysql \
        --defaults-extra-file="${MYSQL_CNF}" \
        --database="${MYSQL_DB}" \
        --batch \
        --skip-column-names \
        -e "
SELECT COUNT(*)
FROM ${MYSQL_TABLE}
WHERE dt = '${BIZDATE}'
  AND source_system = '${SOURCE_SYSTEM}';
"
)"

if [[ "${TARGET_COUNT}" -ne 1 ]]; then
    echo "错误：MySQL 目标表中应有且只能有一行。"
    echo "实际行数：${TARGET_COUNT}"
    exit 1
fi

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
        CAST(avg_order_value AS CHAR),
        COALESCE(DATE_FORMAT(prev_dt, '%Y-%m-%d'), ''),
        COALESCE(CAST(prev_sales AS CHAR), ''),
        COALESCE(CAST(sales_change_pct AS CHAR), ''),
        COALESCE(CAST(sales_loss_amount AS CHAR), ''),
        COALESCE(CAST(orders_change_pct AS CHAR), ''),
        COALESCE(CAST(customers_change_pct AS CHAR), ''),
        COALESCE(CAST(quantity_change_pct AS CHAR), ''),
        COALESCE(CAST(aov_change_pct AS CHAR), ''),
        COALESCE(anomaly_level, ''),
        COALESCE(primary_driver, '')
    )
FROM ${MYSQL_TABLE}
WHERE dt = '${BIZDATE}'
  AND source_system = '${SOURCE_SYSTEM}';
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
    TARGET_PREV_DT \
    TARGET_PREV_SALES \
    TARGET_SALES_CHANGE \
    TARGET_SALES_LOSS \
    TARGET_ORDERS_CHANGE \
    TARGET_CUSTOMERS_CHANGE \
    TARGET_QUANTITY_CHANGE \
    TARGET_AOV_CHANGE \
    TARGET_LEVEL \
    TARGET_DRIVER \
    <<< "${TARGET_ROW}"

decimal_equal() {
    local left="$1"
    local right="$2"

    awk -v a="${left}" -v b="${right}" '
        BEGIN {
            if (a == "" || b == "") {
                exit !(a == b);
            }

            diff = a - b;
            if (diff < 0) {
                diff = -diff;
            }

            exit !(diff <= 0.001);
        }
    '
}

MISMATCH_COUNT=0

[[ "${DT}" == "${TARGET_DT}" ]] || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${TOTAL_SALES}" "${TARGET_SALES}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
[[ "${TOTAL_ORDERS}" == "${TARGET_ORDERS}" ]] || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
[[ "${TOTAL_CUSTOMERS}" == "${TARGET_CUSTOMERS}" ]] || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
[[ "${TOTAL_QUANTITY}" == "${TARGET_QUANTITY}" ]] || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${AVG_ORDER_VALUE}" "${TARGET_AVG}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))

[[ "${PREV_DT}" == "${TARGET_PREV_DT}" ]] || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${PREV_SALES}" "${TARGET_PREV_SALES}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${SALES_CHANGE_PCT}" "${TARGET_SALES_CHANGE}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${SALES_LOSS_AMOUNT}" "${TARGET_SALES_LOSS}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${ORDERS_CHANGE_PCT}" "${TARGET_ORDERS_CHANGE}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${CUSTOMERS_CHANGE_PCT}" "${TARGET_CUSTOMERS_CHANGE}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${QUANTITY_CHANGE_PCT}" "${TARGET_QUANTITY_CHANGE}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
decimal_equal "${AOV_CHANGE_PCT}" "${TARGET_AOV_CHANGE}" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
[[ "${ANOMALY_LEVEL}" == "${TARGET_LEVEL}" ]] || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
[[ "${PRIMARY_DRIVER}" == "${TARGET_DRIVER}" ]] || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))

if [[ "${MISMATCH_COUNT}" -gt 0 ]]; then
    echo "同步失败：Hive 与 MySQL 存在 ${MISMATCH_COUNT} 个字段不一致。"
    exit 1
fi

echo "=========================================="
echo "同步并对账通过：PASS"
echo "业务日期：${BIZDATE}"
echo "source_system：${SOURCE_SYSTEM}"
echo "=========================================="