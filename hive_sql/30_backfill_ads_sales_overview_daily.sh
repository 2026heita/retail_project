#!/usr/bin/env bash

# =====================================================
# 文件名：30_backfill_ads_sales_overview_daily.sh
# 功能：回刷 2026-04-01 至 2026-04-08 的销售概览 ADS 指标
# 说明：
# 1. 每个日期单独执行；
# 2. 使用 INSERT OVERWRITE 覆盖对应日期分区；
# 3. 重复执行仍保持每个日期一行；
# 4. 明确不处理额外测试日期 2026-05-10。
# =====================================================

set -euo pipefail

# 自动取得当前脚本所在目录，避免把项目路径写死。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SQL_FILE="${SCRIPT_DIR}/29_ads_sales_overview_daily_hive.sql"

if [[ ! -f "${SQL_FILE}" ]]; then
    echo "错误：未找到 ADS SQL 文件：${SQL_FILE}"
    exit 1
fi

BIZ_DATES=(
    "2026-04-01"
    "2026-04-02"
    "2026-04-03"
    "2026-04-04"
    "2026-04-05"
    "2026-04-06"
    "2026-04-07"
    "2026-04-08"
)

echo "=========================================="
echo "开始回刷销售概览 ADS 指标"
echo "SQL 文件：${SQL_FILE}"
echo "回刷日期数：${#BIZ_DATES[@]}"
echo "=========================================="

for bizdate in "${BIZ_DATES[@]}"; do
    echo
    echo "开始处理业务日期：${bizdate}"

    hive \
        --hiveconf bizdate="${bizdate}" \
        -f "${SQL_FILE}"

    echo "业务日期 ${bizdate} 处理完成"
done

echo
echo "=========================================="
echo "所有日期回刷完成，开始执行结果校验"
echo "=========================================="

hive -e "
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT dt) AS day_count,
    MIN(dt) AS min_date,
    MAX(dt) AS max_date
FROM ads_sales_overview_daily_hive
WHERE dt BETWEEN '2026-04-01' AND '2026-04-08';

SELECT
    dt,
    total_sales,
    total_orders,
    total_customers,
    total_quantity,
    avg_order_value
FROM ads_sales_overview_daily_hive
WHERE dt BETWEEN '2026-04-01' AND '2026-04-08'
ORDER BY dt;
"

echo
echo "ADS 多日回刷与校验完成"