-- =====================================================
-- 文件名: 26_ads_bi_export_dataset.sql
-- 文件属性: 长期保留，提交代码仓库
-- 功能: ADS 核心指标汇总导出查询模板
-- 说明:
--   1. 输出统一的 dt、metric_name、metric_value 三列，
--      便于导出 TSV/CSV 或作为轻量级 BI Dashboard 数据源。
--   2. 本 SQL 为可选扩展查询，不参与 run_all_hive.sh 主链路。
--   3. 所有指标统一转换为 DECIMAL(18,2)，避免 UNION ALL 类型不一致。
-- =====================================================

-- 1. 高价值客户销售贡献率（百分比）
SELECT
    dt,
    'High Value Sales Contribution Pct' AS metric_name,
    CAST(
        COALESCE(MAX(sales_contribution_pct), 0)
        AS DECIMAL(18,2)
    ) AS metric_value
FROM ads_high_value_customer_sales_contribution_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY dt

UNION ALL

-- 2. 全部客户数量
SELECT
    dt,
    'Total Customer Count' AS metric_name,
    CAST(
        COALESCE(SUM(customer_cnt), 0)
        AS DECIMAL(18,2)
    ) AS metric_value
FROM ads_customer_level_distribution_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY dt

UNION ALL

-- 3. 全部销售额
SELECT
    dt,
    'Total Sales' AS metric_name,
    CAST(
        COALESCE(SUM(total_sales), 0)
        AS DECIMAL(18,2)
    ) AS metric_value
FROM ads_country_sales_rank_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY dt;
