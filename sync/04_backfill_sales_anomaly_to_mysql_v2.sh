#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
RECONCILE_SCRIPT="${BASE_DIR}/reconcile_anomaly.py"

HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"
SOURCE_SYSTEM="${SOURCE_SYSTEM:-retail_canonical_anomaly_ads}"

MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-retail_sync_user}"
MYSQL_DB="${MYSQL_DB:-retail_bi}"
MYSQL_TABLE="bi_sales_anomaly_daily"

START_DT="${1:-}"
END_DT="${2:-}"

if [[ -z "${START_DT}" || -z "${END_DT}" ]]; then
    echo "错误：缺少日期参数。"
    echo "用法：bash $0 yyyy-MM-dd yyyy-MM-dd"
    exit 1
fi

if [[ ! "${START_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误：START_DT 格式非法：${START_DT}"
    exit 1
fi

if [[ ! "${END_DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "错误：END_DT 格式非法：${END_DT}"
    exit 1
fi

if [[ "${START_DT}" > "${END_DT}" ]]; then
    echo "错误：START_DT 不能晚于 END_DT。"
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "错误：系统缺少 python3，本脚本需要 Python 3 解析 Hive 导出数据。"
    exit 1
fi

if [[ ! -f "${RECONCILE_SCRIPT}" ]]; then
    echo "错误：缺少对账脚本：${RECONCILE_SCRIPT}"
    exit 1
fi

echo "=========================================="
echo "开始范围式批量同步经营异常数据 V2"
echo "Hive：${HIVE_DATABASE}.ads_sales_anomaly_daily_hive"
echo "MySQL：${MYSQL_DB}.${MYSQL_TABLE}"
echo "source_system：${SOURCE_SYSTEM}"
echo "范围：${START_DT} 至 ${END_DT}"
echo "=========================================="

if [[ -z "${MYSQL_PASSWORD:-}" ]]; then
    read -r -s -p "请输入 retail_sync_user 的 MySQL 密码：" MYSQL_PASSWORD
    echo
fi

TEMP_HIVE_DATA="$(mktemp)"
TEMP_MYSQL_SQL="$(mktemp)"
TEMP_MYSQL_DATA="$(mktemp)"
MYSQL_CNF="$(mktemp)"

cleanup() {
    unset MYSQL_PASSWORD
    rm -f \
    "${TEMP_HIVE_DATA}" \
    "${TEMP_MYSQL_SQL}" \
    "${TEMP_MYSQL_DATA}" \
    "${MYSQL_CNF}"
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

echo
echo "[1/4] 从 Hive 导出原始异常 ADS 字段..."

hive --database "${HIVE_DATABASE}" -S -e "
SELECT
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
    primary_driver
FROM ads_sales_anomaly_daily_hive
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}'
ORDER BY dt;
" > "${TEMP_HIVE_DATA}" || {
    echo "错误：Hive 查询失败。"
    exit 1
}

SOURCE_ROW_COUNT="$(wc -l < "${TEMP_HIVE_DATA}")"
echo "Hive 源端行数：${SOURCE_ROW_COUNT}"

if [[ "${SOURCE_ROW_COUNT}" -le 0 ]]; then
    echo "错误：Hive 查询为空。"
    exit 1
fi

echo
echo "[2/4] Python 解析 Hive 数据并生成 MySQL UPSERT..."

python3 - "${TEMP_HIVE_DATA}" "${TEMP_MYSQL_SQL}" "${SOURCE_SYSTEM}" <<'PY'
import csv
import sys
from decimal import Decimal

src_path, sql_path, source_system = sys.argv[1:4]

expected_columns = [
    "dt", "total_sales", "total_orders", "total_customers",
    "total_quantity", "avg_order_value", "prev_dt", "prev_sales",
    "sales_change_pct", "sales_loss_amount", "orders_change_pct",
    "customers_change_pct", "quantity_change_pct", "aov_change_pct",
    "anomaly_level", "primary_driver"
]

def sql_num(v):
    v = (v or "").strip()
    if not v or v.upper() == "NULL" or v == r"\N":
        return "NULL"
    Decimal(v)  # validate numeric
    return v

def sql_date(v):
    v = (v or "").strip()
    if not v or v.upper() == "NULL" or v == r"\N":
        return "NULL"
    return "'" + v.replace("'", "''") + "'"

def sql_str(v):
    v = (v or "").strip()
    if not v or v.upper() == "NULL" or v == r"\N":
        return "NULL"
    return "'" + v.replace("'", "''") + "'"

rows = []

with open(src_path, "r", encoding="utf-8", newline="") as f:
    reader = csv.reader(f, delimiter="\t")
    for line_no, row in enumerate(reader, start=1):
        if not row or all(not x.strip() for x in row):
            continue
        if len(row) != 16:
            raise SystemExit(
                f"ERROR: 第 {line_no} 行字段数={len(row)}，期望 16。原始行：{row}"
            )
        rows.append(row)

if not rows:
    raise SystemExit("ERROR: 没有有效数据。")

with open(sql_path, "w", encoding="utf-8") as out:
    out.write("START TRANSACTION;\n")

    for row in rows:
        (
            dt, total_sales, total_orders, total_customers,
            total_quantity, avg_order_value, prev_dt, prev_sales,
            sales_change_pct, sales_loss_amount, orders_change_pct,
            customers_change_pct, quantity_change_pct, aov_change_pct,
            anomaly_level, primary_driver
        ) = row

        dt = dt.strip()
        if not dt:
            raise SystemExit("ERROR: dt 为空。")

        if anomaly_level not in {"NOT_EVALUATED", "NORMAL", "MEDIUM", "HIGH"}:
            raise SystemExit(
                f"ERROR: 日期 {dt} anomaly_level 非法：{anomaly_level}"
            )

        if primary_driver.strip() not in {"", r"\N", "NULL", "ORDERS", "AVG_ORDER_VALUE"}:
            raise SystemExit(
                f"ERROR: 日期 {dt} primary_driver 非法：{primary_driver}"
            )

        values = [
            sql_date(dt),
            sql_num(total_sales),
            sql_num(total_orders),
            sql_num(total_customers),
            sql_num(total_quantity),
            sql_num(avg_order_value),
            sql_date(prev_dt),
            sql_num(prev_sales),
            sql_num(sales_change_pct),
            sql_num(sales_loss_amount),
            sql_num(orders_change_pct),
            sql_num(customers_change_pct),
            sql_num(quantity_change_pct),
            sql_num(aov_change_pct),
            sql_str(anomaly_level),
            sql_str(primary_driver),
            sql_str(source_system),
        ]

        out.write(
            "INSERT INTO bi_sales_anomaly_daily "
            "(dt,total_sales,total_orders,total_customers,total_quantity,avg_order_value,"
            "prev_dt,prev_sales,sales_change_pct,sales_loss_amount,"
            "orders_change_pct,customers_change_pct,quantity_change_pct,aov_change_pct,"
            "anomaly_level,primary_driver,source_system) VALUES ("
            + ",".join(values)
            + ") ON DUPLICATE KEY UPDATE "
            "total_sales=VALUES(total_sales),"
            "total_orders=VALUES(total_orders),"
            "total_customers=VALUES(total_customers),"
            "total_quantity=VALUES(total_quantity),"
            "avg_order_value=VALUES(avg_order_value),"
            "prev_dt=VALUES(prev_dt),"
            "prev_sales=VALUES(prev_sales),"
            "sales_change_pct=VALUES(sales_change_pct),"
            "sales_loss_amount=VALUES(sales_loss_amount),"
            "orders_change_pct=VALUES(orders_change_pct),"
            "customers_change_pct=VALUES(customers_change_pct),"
            "quantity_change_pct=VALUES(quantity_change_pct),"
            "aov_change_pct=VALUES(aov_change_pct),"
            "anomaly_level=VALUES(anomaly_level),"
            "primary_driver=VALUES(primary_driver),"
            "source_system=VALUES(source_system);\n"
        )

    out.write("COMMIT;\n")

print(f"Python 解析通过：{len(rows)} 行")
PY

echo
echo "[3/4] 执行 MySQL 批量 UPSERT..."

mysql \
    --defaults-extra-file="${MYSQL_CNF}" \
    --database="${MYSQL_DB}" \
    < "${TEMP_MYSQL_SQL}" || {
    echo "错误：MySQL 写入失败。"
    exit 1
}

echo "MySQL 批量写入完成。"

echo
echo "[4/4] 目标端行数 + 关键案例检查..."

TARGET_ROW_COUNT="$(
    mysql \
        --defaults-extra-file="${MYSQL_CNF}" \
        --database="${MYSQL_DB}" \
        --batch \
        --skip-column-names \
        -e "
SELECT COUNT(*)
FROM ${MYSQL_TABLE}
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}'
  AND source_system = '${SOURCE_SYSTEM}';
"
)"

echo "MySQL 目标端行数：${TARGET_ROW_COUNT}"

if [[ "${TARGET_ROW_COUNT}" -ne "${SOURCE_ROW_COUNT}" ]]; then
    echo "BLOCK：Hive=${SOURCE_ROW_COUNT} 行，MySQL=${TARGET_ROW_COUNT} 行。"
    exit 1
fi

mysql \
    --defaults-extra-file="${MYSQL_CNF}" \
    --database="${MYSQL_DB}" \
    --batch \
    --raw \
    --skip-column-names \
    -e "
SELECT
    DATE_FORMAT(dt, '%Y-%m-%d'),
    total_sales,
    total_orders,
    total_customers,
    total_quantity,
    avg_order_value,
    IFNULL(DATE_FORMAT(prev_dt, '%Y-%m-%d'), '\\N'),
    IFNULL(prev_sales, '\\N'),
    IFNULL(sales_change_pct, '\\N'),
    IFNULL(sales_loss_amount, '\\N'),
    IFNULL(orders_change_pct, '\\N'),
    IFNULL(customers_change_pct, '\\N'),
    IFNULL(quantity_change_pct, '\\N'),
    IFNULL(aov_change_pct, '\\N'),
    anomaly_level,
    IFNULL(primary_driver, '\\N')
FROM ${MYSQL_TABLE}
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}'
  AND source_system = '${SOURCE_SYSTEM}'
ORDER BY dt;
" > "${TEMP_MYSQL_DATA}" || {
    echo "错误：MySQL 目标数据导出失败。"
    exit 1
}

echo
echo "开始 Hive / MySQL 逐字段对账..."

if ! python3 \
    "${RECONCILE_SCRIPT}" \
    "${TEMP_HIVE_DATA}" \
    "${TEMP_MYSQL_DATA}"
then
    echo "BLOCK：Hive / MySQL 异常数据逐字段对账失败。"
    exit 1
fi

echo
echo "=========================================="
echo "PASS：范围式批量同步完成"
echo "  source_rows=${SOURCE_ROW_COUNT}"
echo "  target_rows=${TARGET_ROW_COUNT}"
echo "  start_dt=${START_DT}"
echo "  end_dt=${END_DT}"
echo "  source_system=${SOURCE_SYSTEM}"
echo "=========================================="
