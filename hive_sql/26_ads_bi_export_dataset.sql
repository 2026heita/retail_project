-- =====================================================
-- 文件名: 26_ads_bi_export_dataset.sql
-- 功能: ADS 核心指标汇总导出查询模板
-- 说明:
--   1. 汇总部分核心 ADS 指标，便于导出统一指标数据或辅助轻量级 BI Dashboard 数据准备。
--   2. 该 SQL 为可选扩展查询，不参与 Hive 主链路 run_all_hive.sh 执行。
--   3. 当前 HTML + ECharts 轻量级 BI Dashboard 主要基于 ADS 导出 TSV 文件生成，不依赖重型 BI 工具。
-- =====================================================

SELECT
    dt,
    'High Value Customer Sales Contribution' AS metric_name,
    SUM(amount) AS metric_value
FROM ads_high_value_customer_sales_contribution_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY dt

UNION ALL

SELECT
    dt,
    'Customer Level Distribution' AS metric_name,
    COUNT(*) AS metric_value
FROM ads_customer_level_distribution_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY dt

UNION ALL

SELECT
    dt,
    'Country Sales Rank' AS metric_name,
    SUM(total_sales) AS metric_value
FROM ads_country_sales_rank_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY dt;
