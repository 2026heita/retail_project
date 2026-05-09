USE retail_project;

-- =============================
-- ADS：客户收入集中度分析
-- 统计 Top10 和 Top50 客户销售贡献占比
-- 用于判断平台收入是否依赖少数头部客户
-- =============================

DROP TABLE IF EXISTS ads_customer_revenue_concentration;

CREATE TABLE ads_customer_revenue_concentration AS
WITH customer_sales AS (
    SELECT
        CustomerID,
        ROUND(SUM(amount), 2) AS total_spent
    FROM retail_clean2
    GROUP BY CustomerID
),
ranked_customers AS (
    SELECT
        CustomerID,
        total_spent,
        ROW_NUMBER() OVER (ORDER BY total_spent DESC) AS rn
    FROM customer_sales
),
total_sales_base AS (
    SELECT
        ROUND(SUM(total_spent), 2) AS total_sales
    FROM customer_sales
)
SELECT
    'TOP10' AS customer_group,
    COUNT(*) AS customer_count,
    ROUND(SUM(total_spent), 2) AS group_sales,
    ROUND(SUM(total_spent) / MAX(total_sales) * 100, 2) AS sales_contribution_pct
FROM ranked_customers
CROSS JOIN total_sales_base
WHERE rn <= 10

UNION ALL

SELECT
    'TOP50' AS customer_group,
    COUNT(*) AS customer_count,
    ROUND(SUM(total_spent), 2) AS group_sales,
    ROUND(SUM(total_spent) / MAX(total_sales) * 100, 2) AS sales_contribution_pct
FROM ranked_customers
CROSS JOIN total_sales_base
WHERE rn <= 50;

-- 查看结果
SELECT * FROM ads_customer_revenue_concentration;