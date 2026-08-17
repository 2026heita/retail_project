#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# 文件名：02_backfill_sales_overview_to_mysql.sh
# 功能：范围式批量同步 Hive ADS 到 MySQL
# 用法：
#   HIVE_DATABASE=retail_canonical \
#   bash 02_backfill_sales_overview_to_mysql.sh 2009-12-01 2011-12-09
# 说明：
# 1. 一次 Hive CLI 查询范围内所有行；
# 2. 批量写入 MySQL；
# 3. 逐行对账；
# 4. 不删除范围外已有数据。
# ============================================================

HIVE_DATABASE="${HIVE_DATABASE:-retail_canonical}"
SOURCE_SYSTEM="${SOURCE_SYSTEM:-}"

MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-retail_sync_user}"
MYSQL_DB="${MYSQL_DB:-retail_bi}"
MYSQL_TABLE="bi_sales_overview_daily"

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

if [[ "${START_DT}" > "${END_DT}" ]]; then
    echo "错误：START_DT (${START_DT}) 不能晚于 END_DT (${END_DT})"
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
        echo "示例：SOURCE_SYSTEM=local_sample_ads HIVE_DATABASE=default bash $0 ${START_DT} ${END_DT}"
        exit 1
    fi
fi

echo "=========================================="
echo "开始范围式批量同步经营总览数据"
echo "hive_database：${HIVE_DATABASE}"
echo "source_system：${SOURCE_SYSTEM}"
echo "范围：${START_DT} 至 ${END_DT}"
echo "=========================================="

# ------------------------------------------------------------
# 1. 获取 MySQL 密码（只输入一次）
# ------------------------------------------------------------
if [[ -z "${MYSQL_PASSWORD:-}" ]]; then
    read -r -s -p "请输入 retail_sync_user 的 MySQL 密码：" MYSQL_PASSWORD
    echo
fi

# ------------------------------------------------------------
# 2. 创建临时文件并设置 trap
# ------------------------------------------------------------
TEMP_HIVE_DATA="$(mktemp)"
TEMP_MYSQL_SQL="$(mktemp)"
MYSQL_CNF="$(mktemp)"

cleanup() {
    unset MYSQL_PASSWORD

    if [[ -f "${TEMP_HIVE_DATA}" ]]; then
        rm -f "${TEMP_HIVE_DATA}"
    fi
    if [[ -f "${TEMP_MYSQL_SQL}" ]]; then
        rm -f "${TEMP_MYSQL_SQL}"
    fi
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
# 3. 从 Hive ADS 查询范围内所有数据
# ------------------------------------------------------------
echo
echo "[1/6] 从 Hive 查询范围数据..."

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
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}'
ORDER BY dt;
"
)" || {
    echo "错误：Hive 查询失败，退出。"
    exit 1
}

if [[ -z "${HIVE_OUTPUT}" ]]; then
    echo "错误：Hive 查询返回空结果。"
    exit 1
fi

echo "${HIVE_OUTPUT}" | awk 'NF' > "${TEMP_HIVE_DATA}"

SOURCE_ROW_COUNT="$(wc -l < "${TEMP_HIVE_DATA}")"

if [[ "${SOURCE_ROW_COUNT}" -le 0 ]]; then
    echo "错误：Hive 中无数据。"
    exit 1
fi

echo "Hive 源端行数：${SOURCE_ROW_COUNT}"

# ------------------------------------------------------------
# 4. 格式校验并生成 MySQL SQL
# ------------------------------------------------------------
echo
echo "[2/6] 格式校验并生成 MySQL SQL..."

echo "INSERT INTO ${MYSQL_TABLE} (" > "${TEMP_MYSQL_SQL}"
echo "    dt," >> "${TEMP_MYSQL_SQL}"
echo "    total_sales," >> "${TEMP_MYSQL_SQL}"
echo "    total_orders," >> "${TEMP_MYSQL_SQL}"
echo "    total_customers," >> "${TEMP_MYSQL_SQL}"
echo "    total_quantity," >> "${TEMP_MYSQL_SQL}"
echo "    avg_order_value," >> "${TEMP_MYSQL_SQL}"
echo "    source_system" >> "${TEMP_MYSQL_SQL}"
echo ") VALUES" >> "${TEMP_MYSQL_SQL}"

LINE_NUM=0
VALID_LINE_COUNT=0

while IFS=$'\t' read -r DT TOTAL_SALES TOTAL_ORDERS TOTAL_CUSTOMERS TOTAL_QUANTITY AVG_ORDER_VALUE; do
    LINE_NUM=$((LINE_NUM + 1))

    # 日期格式校验
    if [[ ! "${DT}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "错误：第 ${LINE_NUM} 行日期格式非法：${DT}"
        exit 1
    fi

    # 数字格式校验（允许负数、小数）
    if [[ ! "${TOTAL_SALES}" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "错误：第 ${LINE_NUM} 行 total_sales 格式非法：${TOTAL_SALES}"
        exit 1
    fi
    if [[ ! "${TOTAL_ORDERS}" =~ ^[0-9]+$ ]]; then
        echo "错误：第 ${LINE_NUM} 行 total_orders 格式非法：${TOTAL_ORDERS}"
        exit 1
    fi
    if [[ ! "${TOTAL_CUSTOMERS}" =~ ^[0-9]+$ ]]; then
        echo "错误：第 ${LINE_NUM} 行 total_customers 格式非法：${TOTAL_CUSTOMERS}"
        exit 1
    fi
    if [[ ! "${TOTAL_QUANTITY}" =~ ^[0-9]+$ ]]; then
        echo "错误：第 ${LINE_NUM} 行 total_quantity 格式非法：${TOTAL_QUANTITY}"
        exit 1
    fi
    if [[ ! "${AVG_ORDER_VALUE}" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "错误：第 ${LINE_NUM} 行 avg_order_value 格式非法：${AVG_ORDER_VALUE}"
        exit 1
    fi

    VALID_LINE_COUNT=$((VALID_LINE_COUNT + 1))

    if [[ "${VALID_LINE_COUNT}" -gt 1 ]]; then
        echo "," >> "${TEMP_MYSQL_SQL}"
    fi

    printf "    ('%s', %s, %s, %s, %s, %s, '%s')" \
        "${DT}" \
        "${TOTAL_SALES}" \
        "${TOTAL_ORDERS}" \
        "${TOTAL_CUSTOMERS}" \
        "${TOTAL_QUANTITY}" \
        "${AVG_ORDER_VALUE}" \
        "${SOURCE_SYSTEM}" >> "${TEMP_MYSQL_SQL}"

done < "${TEMP_HIVE_DATA}"

echo "" >> "${TEMP_MYSQL_SQL}"
echo "ON DUPLICATE KEY UPDATE" >> "${TEMP_MYSQL_SQL}"
echo "    total_sales = VALUES(total_sales)," >> "${TEMP_MYSQL_SQL}"
echo "    total_orders = VALUES(total_orders)," >> "${TEMP_MYSQL_SQL}"
echo "    total_customers = VALUES(total_customers)," >> "${TEMP_MYSQL_SQL}"
echo "    total_quantity = VALUES(total_quantity)," >> "${TEMP_MYSQL_SQL}"
echo "    avg_order_value = VALUES(avg_order_value)," >> "${TEMP_MYSQL_SQL}"
echo "    source_system = VALUES(source_system);" >> "${TEMP_MYSQL_SQL}"

if [[ "${VALID_LINE_COUNT}" -ne "${SOURCE_ROW_COUNT}" ]]; then
    echo "错误：有效行数 (${VALID_LINE_COUNT}) != 源端行数 (${SOURCE_ROW_COUNT})"
    exit 1
fi

echo "生成 MySQL SQL 完成，有效行数：${VALID_LINE_COUNT}"

# ------------------------------------------------------------
# 写入前保护：禁止相同日期跨 source_system 静默覆盖
# ------------------------------------------------------------
echo
echo "写入前保护检查：确认目标日期没有其他 source_system 数据..."

HIVE_DT_LIST="$(cut -d$'\t' -f1 "${TEMP_HIVE_DATA}" | sort -u)"

if [[ -z "${HIVE_DT_LIST}" ]]; then
    echo "错误：无法从 Hive 数据中解析业务日期列表。"
    exit 1
fi

DT_CONDITIONS=""
while IFS= read -r DT_VALUE; do
    if [[ -z "${DT_CONDITIONS}" ]]; then
        DT_CONDITIONS="'${DT_VALUE}'"
    else
        DT_CONDITIONS="${DT_CONDITIONS}, '${DT_VALUE}'"
    fi
done <<< "${HIVE_DT_LIST}"

CONFLICT_OUTPUT="$(
    mysql \
        --defaults-extra-file="${MYSQL_CNF}" \
        --database="${MYSQL_DB}" \
        --batch \
        --raw \
        --skip-column-names \
        -e "
SELECT
    CONCAT_WS('\t', DATE_FORMAT(dt, '%Y-%m-%d'), COALESCE(source_system, ''))
FROM ${MYSQL_TABLE}
WHERE dt IN (${DT_CONDITIONS})
  AND (source_system IS NULL OR source_system != '${SOURCE_SYSTEM}');
"
)"

if [[ -n "${CONFLICT_OUTPUT}" ]]; then
    echo "错误：以下业务日期已存在其他 source_system 的数据，拒绝覆盖。"
    while IFS=$'\t' read -r CONFLICT_DT CONFLICT_SOURCE; do
        echo "  日期=${CONFLICT_DT}，已有 source_system=${CONFLICT_SOURCE}，准备写入 source_system=${SOURCE_SYSTEM}"
    done <<< "${CONFLICT_OUTPUT}"
    exit 1
fi

# ------------------------------------------------------------
# 5. 执行 MySQL 写入
# ------------------------------------------------------------
echo
echo "[3/6] 执行 MySQL 写入..."

mysql \
    --defaults-extra-file="${MYSQL_CNF}" \
    --database="${MYSQL_DB}" < "${TEMP_MYSQL_SQL}" || {
    echo "错误：MySQL 写入失败。"
    exit 1
}

echo "MySQL 写入完成。"

# ------------------------------------------------------------
# 6. 从 MySQL 导出验证数据
# ------------------------------------------------------------
echo
echo "[4/6] 从 MySQL 导出验证数据..."

MYSQL_VERIFY_OUTPUT="$(
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
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}'
  AND source_system = '${SOURCE_SYSTEM}'
ORDER BY dt;
"
)" || {
    echo "错误：MySQL 验证查询失败。"
    exit 1
}

if [[ -z "${MYSQL_VERIFY_OUTPUT}" ]]; then
    echo "错误：MySQL 验证查询返回空结果。"
    exit 1
fi

echo "${MYSQL_VERIFY_OUTPUT}" | awk 'NF' > "${TEMP_HIVE_DATA}.mysql_verify"

TARGET_ROW_COUNT="$(wc -l < "${TEMP_HIVE_DATA}.mysql_verify")"

rm -f "${TEMP_HIVE_DATA}.mysql_verify"

echo "MySQL 目标端行数：${TARGET_ROW_COUNT}"

# ------------------------------------------------------------
# 7. 行数校验
# ------------------------------------------------------------
echo
echo "[5/6] 行数校验..."

if [[ "${TARGET_ROW_COUNT}" -ne "${SOURCE_ROW_COUNT}" ]]; then
    echo "错误：MySQL 目标端行数 (${TARGET_ROW_COUNT}) != Hive 源端行数 (${SOURCE_ROW_COUNT})"
    exit 1
fi

echo "行数校验通过：${SOURCE_ROW_COUNT}"

# ------------------------------------------------------------
# 8. 逐行对账
# ------------------------------------------------------------
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

echo
echo "[6/6] 逐行对账..."

MYSQL_VERIFY_OUTPUT_FINAL="$(
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
WHERE dt BETWEEN '${START_DT}' AND '${END_DT}'
  AND source_system = '${SOURCE_SYSTEM}'
ORDER BY dt;
"
)"

echo "${MYSQL_VERIFY_OUTPUT_FINAL}" | awk 'NF' > "${TEMP_HIVE_DATA}.mysql_final"

LINE_NUM=0
MISMATCH_COUNT=0

while IFS=$'\t' read -r MYSQL_DT MYSQL_SALES MYSQL_ORDERS MYSQL_CUSTOMERS MYSQL_QUANTITY MYSQL_AVG; do
    LINE_NUM=$((LINE_NUM + 1))

    HIVE_LINE="$(sed -n "${LINE_NUM}p" "${TEMP_HIVE_DATA}")"

    if [[ -z "${HIVE_LINE}" ]]; then
        echo "错误：Hive 数据不足，缺少第 ${LINE_NUM} 行。"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
        continue
    fi

    IFS=$'\t' read -r HIVE_DT HIVE_SALES HIVE_ORDERS HIVE_CUSTOMERS HIVE_QUANTITY HIVE_AVG <<< "${HIVE_LINE}"

    if [[ "${MYSQL_DT}" != "${HIVE_DT}" ]]; then
        echo "第 ${LINE_NUM} 行 dt 不一致：Hive=${HIVE_DT}, MySQL=${MYSQL_DT}"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
    if ! decimal_equal "${MYSQL_SALES}" "${HIVE_SALES}"; then
        echo "第 ${LINE_NUM} 行 total_sales 不一致：Hive=${HIVE_SALES}, MySQL=${MYSQL_SALES}"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
    if [[ "${MYSQL_ORDERS}" != "${HIVE_ORDERS}" ]]; then
        echo "第 ${LINE_NUM} 行 total_orders 不一致：Hive=${HIVE_ORDERS}, MySQL=${MYSQL_ORDERS}"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
    if [[ "${MYSQL_CUSTOMERS}" != "${HIVE_CUSTOMERS}" ]]; then
        echo "第 ${LINE_NUM} 行 total_customers 不一致：Hive=${HIVE_CUSTOMERS}, MySQL=${MYSQL_CUSTOMERS}"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
    if [[ "${MYSQL_QUANTITY}" != "${HIVE_QUANTITY}" ]]; then
        echo "第 ${LINE_NUM} 行 total_quantity 不一致：Hive=${HIVE_QUANTITY}, MySQL=${MYSQL_QUANTITY}"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
    if ! decimal_equal "${MYSQL_AVG}" "${HIVE_AVG}"; then
        echo "第 ${LINE_NUM} 行 avg_order_value 不一致：Hive=${HIVE_AVG}, MySQL=${MYSQL_AVG}"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi

done < "${TEMP_HIVE_DATA}.mysql_final"

rm -f "${TEMP_HIVE_DATA}.mysql_final"

if [[ "${MISMATCH_COUNT}" -gt 0 ]]; then
    echo "=========================================="
    echo "BLOCK：逐行对账发现 ${MISMATCH_COUNT} 处不一致"
    echo "=========================================="
    exit 1
fi

echo "逐行对账通过。"

echo "=========================================="
echo "PASS：范围式批量同步完成"
echo "  source_rows=${SOURCE_ROW_COUNT}"
echo "  target_rows=${TARGET_ROW_COUNT}"
echo "  start_dt=${START_DT}"
echo "  end_dt=${END_DT}"
echo "  hive_database=${HIVE_DATABASE}"
echo "  source_system=${SOURCE_SYSTEM}"
echo "=========================================="
