#!/bin/bash
set -Eeuo pipefail

# =====================================================
# 文件名: run_idempotency_check_hive.sh
# 功能: 校验同一 bizdate 重复执行后，核心表行数和数据内容是否一致
# 用法:
#   bash run_idempotency_check_hive.sh 2026-04-08
#
# 说明:
#   1. 重跑前后分别采集核心表快照。
#   2. 快照同时包含行数和两组内容指纹，不再只比较行数。
#   3. 排除质量日志表，因为 check_time 每次执行都会变化。
#   4. 任一核心表快照变化时返回非零状态。
# =====================================================

BIZDATE="${1:-}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_ALL_SCRIPT="${BASE_DIR}/run_all_hive.sh"

if [ -z "${BIZDATE}" ]; then
    echo "ERROR: bizdate is required."
    echo "Usage: bash run_idempotency_check_hive.sh 2026-04-08"
    exit 1
fi

if ! date -d "${BIZDATE}" +%F >/dev/null 2>&1; then
    echo "ERROR: invalid bizdate: ${BIZDATE}"
    exit 1
fi

if [ ! -f "${RUN_ALL_SCRIPT}" ]; then
    echo "ERROR: main script not found: ${RUN_ALL_SCRIPT}"
    exit 1
fi

BIZDATE="$(date -d "${BIZDATE}" +%F)"

TMP_DIR="$(mktemp -d)"
BEFORE_FILE="${TMP_DIR}/before_snapshot.tsv"
AFTER_FILE="${TMP_DIR}/after_snapshot.tsv"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

snapshot_sql() {
    cat <<SQL
SET hive.cli.print.header=false;

SELECT
    'ods_retail_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(invoice, '<NULL>'),
                        COALESCE(stockcode, '<NULL>'),
                        COALESCE(description, '<NULL>'),
                        COALESCE(CAST(quantity AS STRING), '<NULL>'),
                        COALESCE(invoicedate, '<NULL>'),
                        COALESCE(CAST(price AS STRING), '<NULL>'),
                        COALESCE(customerid, '<NULL>'),
                        COALESCE(country, '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(invoice, '<NULL>'),
                            COALESCE(stockcode, '<NULL>'),
                            COALESCE(description, '<NULL>'),
                            COALESCE(CAST(quantity AS STRING), '<NULL>'),
                            COALESCE(invoicedate, '<NULL>'),
                            COALESCE(CAST(price AS STRING), '<NULL>'),
                            COALESCE(customerid, '<NULL>'),
                            COALESCE(country, '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM ods_retail_hive
WHERE dt='${BIZDATE}'

UNION ALL

SELECT
    'dwd_retail_clean_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(invoice, '<NULL>'),
                        COALESCE(stockcode, '<NULL>'),
                        COALESCE(description, '<NULL>'),
                        COALESCE(CAST(quantity AS STRING), '<NULL>'),
                        COALESCE(invoicedate, '<NULL>'),
                        COALESCE(CAST(price AS STRING), '<NULL>'),
                        COALESCE(customerid, '<NULL>'),
                        COALESCE(country, '<NULL>'),
                        COALESCE(CAST(amount AS STRING), '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(invoice, '<NULL>'),
                            COALESCE(stockcode, '<NULL>'),
                            COALESCE(description, '<NULL>'),
                            COALESCE(CAST(quantity AS STRING), '<NULL>'),
                            COALESCE(invoicedate, '<NULL>'),
                            COALESCE(CAST(price AS STRING), '<NULL>'),
                            COALESCE(customerid, '<NULL>'),
                            COALESCE(country, '<NULL>'),
                            COALESCE(CAST(amount AS STRING), '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM dwd_retail_clean_hive
WHERE dt='${BIZDATE}'

UNION ALL

SELECT
    'dws_customer_value_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(customerid, '<NULL>'),
                        COALESCE(CAST(order_count AS STRING), '<NULL>'),
                        COALESCE(CAST(total_spent AS STRING), '<NULL>'),
                        COALESCE(customer_level, '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(customerid, '<NULL>'),
                            COALESCE(CAST(order_count AS STRING), '<NULL>'),
                            COALESCE(CAST(total_spent AS STRING), '<NULL>'),
                            COALESCE(customer_level, '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM dws_customer_value_hive
WHERE dt='${BIZDATE}'

UNION ALL

SELECT
    'dws_sales_summary_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(country, '<NULL>'),
                        COALESCE(CAST(total_orders AS STRING), '<NULL>'),
                        COALESCE(CAST(total_customers AS STRING), '<NULL>'),
                        COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                        COALESCE(CAST(avg_order_value AS STRING), '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(country, '<NULL>'),
                            COALESCE(CAST(total_orders AS STRING), '<NULL>'),
                            COALESCE(CAST(total_customers AS STRING), '<NULL>'),
                            COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                            COALESCE(CAST(avg_order_value AS STRING), '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM dws_sales_summary_hive
WHERE dt='${BIZDATE}'

UNION ALL

SELECT
    'ads_high_value_customer_sales_contribution_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(CAST(high_value_customer_cnt AS STRING), '<NULL>'),
                        COALESCE(CAST(high_value_order_cnt AS STRING), '<NULL>'),
                        COALESCE(CAST(high_value_total_sales AS STRING), '<NULL>'),
                        COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                        COALESCE(CAST(sales_contribution_pct AS STRING), '<NULL>'),
                        COALESCE(CAST(avg_sales_per_customer AS STRING), '<NULL>'),
                        COALESCE(CAST(avg_orders_per_customer AS STRING), '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(CAST(high_value_customer_cnt AS STRING), '<NULL>'),
                            COALESCE(CAST(high_value_order_cnt AS STRING), '<NULL>'),
                            COALESCE(CAST(high_value_total_sales AS STRING), '<NULL>'),
                            COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                            COALESCE(CAST(sales_contribution_pct AS STRING), '<NULL>'),
                            COALESCE(CAST(avg_sales_per_customer AS STRING), '<NULL>'),
                            COALESCE(CAST(avg_orders_per_customer AS STRING), '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM ads_high_value_customer_sales_contribution_hive
WHERE dt='${BIZDATE}'

UNION ALL

SELECT
    'ads_customer_level_distribution_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(customer_level, '<NULL>'),
                        COALESCE(CAST(customer_cnt AS STRING), '<NULL>'),
                        COALESCE(CAST(total_spent AS STRING), '<NULL>'),
                        COALESCE(CAST(customer_cnt_pct AS STRING), '<NULL>'),
                        COALESCE(CAST(sales_pct AS STRING), '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(customer_level, '<NULL>'),
                            COALESCE(CAST(customer_cnt AS STRING), '<NULL>'),
                            COALESCE(CAST(total_spent AS STRING), '<NULL>'),
                            COALESCE(CAST(customer_cnt_pct AS STRING), '<NULL>'),
                            COALESCE(CAST(sales_pct AS STRING), '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM ads_customer_level_distribution_hive
WHERE dt='${BIZDATE}'

UNION ALL

SELECT
    'ads_country_sales_rank_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(country, '<NULL>'),
                        COALESCE(CAST(sales_rank AS STRING), '<NULL>'),
                        COALESCE(CAST(total_orders AS STRING), '<NULL>'),
                        COALESCE(CAST(total_customers AS STRING), '<NULL>'),
                        COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                        COALESCE(CAST(avg_order_value AS STRING), '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(country, '<NULL>'),
                            COALESCE(CAST(sales_rank AS STRING), '<NULL>'),
                            COALESCE(CAST(total_orders AS STRING), '<NULL>'),
                            COALESCE(CAST(total_customers AS STRING), '<NULL>'),
                            COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                            COALESCE(CAST(avg_order_value AS STRING), '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM ads_country_sales_rank_hive
WHERE dt='${BIZDATE}'

UNION ALL

SELECT
    'ads_high_value_customer_preference_hive',
    COUNT(1),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    CONCAT_WS(
                        '#|#',
                        COALESCE(stockcode, '<NULL>'),
                        COALESCE(description, '<NULL>'),
                        COALESCE(CAST(high_value_customer_cnt AS STRING), '<NULL>'),
                        COALESCE(CAST(high_value_order_cnt AS STRING), '<NULL>'),
                        COALESCE(CAST(total_quantity AS STRING), '<NULL>'),
                        COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                        COALESCE(CAST(sales_rank AS STRING), '<NULL>')
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    ),
    COALESCE(
        SUM(
            CAST(
                CRC32(
                    REVERSE(
                        CONCAT_WS(
                            '#|#',
                            COALESCE(stockcode, '<NULL>'),
                            COALESCE(description, '<NULL>'),
                            COALESCE(CAST(high_value_customer_cnt AS STRING), '<NULL>'),
                            COALESCE(CAST(high_value_order_cnt AS STRING), '<NULL>'),
                            COALESCE(CAST(total_quantity AS STRING), '<NULL>'),
                            COALESCE(CAST(total_sales AS STRING), '<NULL>'),
                            COALESCE(CAST(sales_rank AS STRING), '<NULL>')
                        )
                    )
                ) AS DECIMAL(38,0)
            )
        ),
        CAST(0 AS DECIMAL(38,0))
    )
FROM ads_high_value_customer_preference_hive
WHERE dt='${BIZDATE}';
SQL
}

collect_snapshot() {
    local output_file="$1"
    local stage_name="$2"

    echo "${stage_name}"

    if ! hive -S -e "$(snapshot_sql)" > "${output_file}"; then
        echo "ERROR: failed to collect idempotency snapshot."
        exit 1
    fi

    sort -t $'\t' -k1,1 "${output_file}" -o "${output_file}"

    if [ "$(wc -l < "${output_file}")" -ne 8 ]; then
        echo "ERROR: unexpected snapshot row count."
        echo "Expected 8 tables, actual: $(wc -l < "${output_file}")"
        cat "${output_file}"
        exit 1
    fi
}

print_snapshot() {
    local snapshot_file="$1"

    printf "%-52s %-14s %-22s %-22s\n" \
        "table_name" "row_count" "checksum_1" "checksum_2"

    while IFS=$'\t' read -r table_name row_count checksum_1 checksum_2
    do
        printf "%-52s %-14s %-22s %-22s\n" \
            "${table_name}" \
            "${row_count}" \
            "${checksum_1}" \
            "${checksum_2}"
    done < "${snapshot_file}"
}

echo "========================================"
echo "Start Hive idempotency check"
echo "bizdate: ${BIZDATE}"
echo "========================================"

collect_snapshot "${BEFORE_FILE}" "[1/3] Collect snapshot before rerun"

echo ""
print_snapshot "${BEFORE_FILE}"

echo ""
echo "[2/3] Rerun full Hive main chain"
if ! bash "${RUN_ALL_SCRIPT}" "${BIZDATE}"; then
    echo "ERROR: main chain failed during idempotency check."
    exit 1
fi

collect_snapshot "${AFTER_FILE}" "[3/3] Collect snapshot after rerun"

echo ""
print_snapshot "${AFTER_FILE}"

echo ""
if diff -u "${BEFORE_FILE}" "${AFTER_FILE}"; then
    echo "FINAL_RESULT: PASS"
    echo "Repeated execution did not change row counts or content fingerprints."
else
    echo "FINAL_RESULT: FAIL"
    echo "At least one core table changed after repeated execution."
    echo "Review the diff above to locate the changed table."
    exit 2
fi
