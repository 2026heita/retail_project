#!/usr/bin/env bash

set -Eeuo pipefail

BIZDATE="${1:-}"

HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"
SOURCE_SYSTEM="${SOURCE_SYSTEM:-}"

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

# canonical 数据库允许使用明确且安全的默认来源标识。
# 其他 Hive 数据库的数据来源无法由数据库名可靠推断，
# 必须由调用方显式声明，避免误标为 canonical 数据。
if [[ -z "${SOURCE_SYSTEM}" ]]; then
    if [[ "${HIVE_DATABASE}" == "retail_canonical" ]]; then
        SOURCE_SYSTEM="retail_canonical_anomaly_ads"
    else
        echo "错误：非 canonical Hive 数据库必须显式设置 SOURCE_SYSTEM。"
        echo "当前 HIVE_DATABASE=${HIVE_DATABASE}"
        echo "示例：SOURCE_SYSTEM=local_sample_anomaly_ads HIVE_DATABASE=default bash $0 ${BIZDATE}"
        exit 1
    fi
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

mapfile -d '' -t FIELDS < <(
    python3 - "${SOURCE_ROW}" <<'PY'
import csv
import io
import sys

row = next(csv.reader(io.StringIO(sys.argv[1]), delimiter="\t"))

if len(row) != 16:
    print(
        f"ERROR: expected 16 TSV columns, got {len(row)}",
        file=sys.stderr,
    )
    sys.exit(1)

for value in row:
    sys.stdout.write(value)
    sys.stdout.write("\0")
PY
)

if [[ "${#FIELDS[@]}" -ne 16 ]]; then
    echo "错误：解析后的异常数据字段数不是 16。"
    echo "实际字段数：${#FIELDS[@]}"
    exit 1
fi

DT="${FIELDS[0]}"
TOTAL_SALES="${FIELDS[1]}"
TOTAL_ORDERS="${FIELDS[2]}"
TOTAL_CUSTOMERS="${FIELDS[3]}"
TOTAL_QUANTITY="${FIELDS[4]}"
AVG_ORDER_VALUE="${FIELDS[5]}"
PREV_DT="${FIELDS[6]}"
PREV_SALES="${FIELDS[7]}"
SALES_CHANGE_PCT="${FIELDS[8]}"
SALES_LOSS_AMOUNT="${FIELDS[9]}"
ORDERS_CHANGE_PCT="${FIELDS[10]}"
CUSTOMERS_CHANGE_PCT="${FIELDS[11]}"
QUANTITY_CHANGE_PCT="${FIELDS[12]}"
AOV_CHANGE_PCT="${FIELDS[13]}"
ANOMALY_LEVEL="${FIELDS[14]}"
PRIMARY_DRIVER="${FIELDS[15]}"

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

# ------------------------------------------------------------
# 写入前保护：禁止相同日期跨 source_system 静默覆盖
# ------------------------------------------------------------
EXISTING_SOURCE="$(
    mysql \
        --defaults-extra-file="${MYSQL_CNF}" \
        --database="${MYSQL_DB}" \
        --batch \
        --raw \
        --skip-column-names \
        -e "
SELECT COALESCE(source_system, '')
FROM ${MYSQL_TABLE}
WHERE dt = '${BIZDATE}'
LIMIT 1;
"
)"

if [[ -n "${EXISTING_SOURCE}" && "${EXISTING_SOURCE}" != "${SOURCE_SYSTEM}" ]]; then
    echo "错误：业务日期 ${BIZDATE} 已存在其他 source_system 的数据，拒绝覆盖。"
    echo "当前日期：${BIZDATE}"
    echo "已有 source_system：${EXISTING_SOURCE}"
    echo "准备写入 source_system：${SOURCE_SYSTEM}"
    exit 1
fi

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

mapfile -d '' -t TARGET_FIELDS < <(
    python3 - "${TARGET_ROW}" <<'PY'
import csv
import io
import sys

row = next(csv.reader(io.StringIO(sys.argv[1]), delimiter="\t"))

if len(row) != 16:
    print(
        f"ERROR: expected 16 TSV columns, got {len(row)}",
        file=sys.stderr,
    )
    sys.exit(1)

for value in row:
    sys.stdout.write(value)
    sys.stdout.write("\0")
PY
)

if [[ "${#TARGET_FIELDS[@]}" -ne 16 ]]; then
    echo "错误：MySQL 对账数据解析后的字段数不是 16。"
    echo "实际字段数：${#TARGET_FIELDS[@]}"
    exit 1
fi

TARGET_DT="${TARGET_FIELDS[0]}"
TARGET_SALES="${TARGET_FIELDS[1]}"
TARGET_ORDERS="${TARGET_FIELDS[2]}"
TARGET_CUSTOMERS="${TARGET_FIELDS[3]}"
TARGET_QUANTITY="${TARGET_FIELDS[4]}"
TARGET_AVG="${TARGET_FIELDS[5]}"
TARGET_PREV_DT="${TARGET_FIELDS[6]}"
TARGET_PREV_SALES="${TARGET_FIELDS[7]}"
TARGET_SALES_CHANGE="${TARGET_FIELDS[8]}"
TARGET_SALES_LOSS="${TARGET_FIELDS[9]}"
TARGET_ORDERS_CHANGE="${TARGET_FIELDS[10]}"
TARGET_CUSTOMERS_CHANGE="${TARGET_FIELDS[11]}"
TARGET_QUANTITY_CHANGE="${TARGET_FIELDS[12]}"
TARGET_AOV_CHANGE="${TARGET_FIELDS[13]}"
TARGET_LEVEL="${TARGET_FIELDS[14]}"
TARGET_DRIVER="${TARGET_FIELDS[15]}"

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