USE retail_project;

-- =============================
-- ADS：客户分层分布分析
-- 统计 High Value、Medium Value、Low Value 客户的人数占比和销售贡献占比
-- 用于判断平台收入主要由哪一层客户驱动
-- =============================

DROP TABLE IF EXISTS ads_customer_level_distribution;

CREATE TABLE ads_customer_level_distribution AS
WITH level_summary AS (
    SELECT
        customer_level,
        COUNT(*) AS customer_cnt,
        ROUND(SUM(total_spent), 2) AS level_total_spent
    FROM dws_customer_value
    GROUP BY customer_level
),
total_base AS (
    SELECT
        COUNT(*) AS total_customers,
        ROUND(SUM(total_spent), 2) AS total_sales
    FROM dws_customer_value
)
SELECT
    l.customer_level,
    l.customer_cnt,
    l.level_total_spent,
    ROUND(l.customer_cnt / t.total_customers * 100, 2) AS customer_pct,
    ROUND(l.level_total_spent / t.total_sales * 100, 2) AS sales_pct
FROM level_summary l
CROSS JOIN total_base t
ORDER BY l.level_total_spent DESC;

-- 查看结果
SELECT * FROM ads_customer_level_distribution;