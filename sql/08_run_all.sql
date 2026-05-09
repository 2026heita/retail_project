USE retail_project;

-- =========================================
-- 08_run_all.sql
-- 作用：按顺序重建 DWD / DWS / ADS 各层表
-- 原始表：retail
-- =========================================

-- =========================================
-- 0. 检查原始表是否存在
-- =========================================
SELECT 'STEP 0: check ods table retail' AS step_name;
SHOW TABLES;

-- =========================================
-- 1. DWD 层：删除旧表
-- =========================================
SELECT 'STEP 1: drop dwd tables' AS step_name;

DROP TABLE IF EXISTS retail_clean2;
DROP TABLE IF EXISTS retail_clean;

-- =========================================
-- 2. DWD 层：构建清洗表 retail_clean
-- =========================================
SELECT 'STEP 2: create retail_clean' AS step_name;

CREATE TABLE retail_clean AS
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    CustomerID,
    Country,
    Quantity * Price AS amount
FROM retail
WHERE Quantity > 0
  AND Price > 0
  AND CustomerID IS NOT NULL
  AND Invoice NOT LIKE 'C%';

-- =========================================
-- 3. DWD 层：构建修正金额表 retail_clean2
-- =========================================
SELECT 'STEP 3: create retail_clean2' AS step_name;

CREATE TABLE retail_clean2 AS
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    CustomerID,
    Country,
    ROUND(Quantity * Price, 2) AS amount
FROM retail_clean;

-- =========================================
-- 4. DWS 层：删除旧表
-- =========================================
SELECT 'STEP 4: drop dws tables' AS step_name;

DROP TABLE IF EXISTS dws_sales_summary;
DROP TABLE IF EXISTS dws_customer_value;

-- =========================================
-- 5. DWS 层：销售汇总表
-- =========================================
SELECT 'STEP 5: create dws_sales_summary' AS step_name;

CREATE TABLE dws_sales_summary AS
SELECT
    Country,
    COUNT(DISTINCT Invoice) AS total_orders,
    COUNT(DISTINCT CustomerID) AS total_customers,
    ROUND(SUM(amount), 2) AS total_sales,
    ROUND(SUM(amount) / COUNT(DISTINCT Invoice), 2) AS avg_order_value
FROM retail_clean2
GROUP BY Country;

-- =========================================
-- 6. DWS 层：客户价值分层表
-- =========================================
SELECT 'STEP 6: create dws_customer_value' AS step_name;

CREATE TABLE dws_customer_value AS
SELECT
    CustomerID,
    COUNT(DISTINCT Invoice) AS order_count,
    ROUND(SUM(amount), 2) AS total_spent,
    CASE
        WHEN SUM(amount) >= 5000 THEN 'High Value'
        WHEN SUM(amount) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_level
FROM retail_clean2
GROUP BY CustomerID;

-- =========================================
-- 7. ADS 层：删除旧表
-- =========================================
SELECT 'STEP 7: drop ads tables' AS step_name;

DROP TABLE IF EXISTS ads_repeat_purchase_summary;
DROP TABLE IF EXISTS ads_monthly_sales_trend;
DROP TABLE IF EXISTS ads_monthly_sales_growth;
DROP TABLE IF EXISTS ads_country_sales_rank;
DROP TABLE IF EXISTS ads_high_value_customers;
DROP TABLE IF EXISTS ads_top10_products;
DROP TABLE IF EXISTS ads_customer_revenue_concentration;
DROP TABLE IF EXISTS ads_country_value_analysis;
DROP TABLE IF EXISTS ads_customer_level_distribution;
DROP TABLE IF EXISTS ads_product_sales_concentration;
DROP TABLE IF EXISTS ads_customer_order_frequency;
DROP TABLE IF EXISTS ads_high_value_customer_preference;
DROP TABLE IF EXISTS ads_high_value_customer_order_frequency;
DROP TABLE IF EXISTS ads_high_value_customer_country_distribution;
DROP TABLE IF EXISTS ads_high_value_customer_sales_contribution;

-- =========================================
-- 8. ADS 层：客户复购率指标表
-- =========================================
SELECT 'STEP 8: create ads_repeat_purchase_summary' AS step_name;

CREATE TABLE ads_repeat_purchase_summary AS
SELECT
    total_customers,
    repeat_customers,
    ROUND(repeat_customers / total_customers * 100, 2) AS repeat_rate_pct
FROM (
    SELECT
        (SELECT COUNT(DISTINCT CustomerID) FROM retail_clean2) AS total_customers,
        (
            SELECT COUNT(*)
            FROM (
                SELECT CustomerID
                FROM retail_clean2
                GROUP BY CustomerID
                HAVING COUNT(DISTINCT Invoice) > 1
            ) t
        ) AS repeat_customers
) s;

-- =========================================
-- 9. ADS 层：月度销售趋势表
-- =========================================
SELECT 'STEP 9: create ads_monthly_sales_trend' AS step_name;

CREATE TABLE ads_monthly_sales_trend AS
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
    ROUND(SUM(amount), 2) AS monthly_sales,
    COUNT(DISTINCT Invoice) AS monthly_orders,
    COUNT(DISTINCT CustomerID) AS monthly_customers
FROM retail_clean2
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY month;

-- =========================================
-- 10. ADS 层：月度销售增长表
-- =========================================
SELECT 'STEP 10: create ads_monthly_sales_growth' AS step_name;

CREATE TABLE ads_monthly_sales_growth AS
SELECT
    month,
    monthly_sales,
    prev_month_sales,
    ROUND(monthly_sales - prev_month_sales, 2) AS growth_amt,
    ROUND(
        (monthly_sales - prev_month_sales) / prev_month_sales * 100,
        2
    ) AS growth_rate_pct
FROM (
    SELECT
        month,
        monthly_sales,
        LAG(monthly_sales) OVER (ORDER BY month) AS prev_month_sales
    FROM ads_monthly_sales_trend
) t;

-- =========================================
-- 11. ADS 层：国家销售排行表
-- =========================================
SELECT 'STEP 11: create ads_country_sales_rank' AS step_name;

CREATE TABLE ads_country_sales_rank AS
SELECT
    Country,
    ROUND(SUM(amount), 2) AS total_sales,
    COUNT(DISTINCT Invoice) AS total_orders,
    COUNT(DISTINCT CustomerID) AS total_customers,
    RANK() OVER (ORDER BY SUM(amount) DESC) AS sales_rank
FROM retail_clean2
GROUP BY Country;

-- =========================================
-- 12. ADS 层：高价值客户名单表
-- =========================================
SELECT 'STEP 12: create ads_high_value_customers' AS step_name;

CREATE TABLE ads_high_value_customers AS
SELECT
    CustomerID,
    order_count,
    ROUND(total_spent, 2) AS total_spent,
    customer_level
FROM dws_customer_value
WHERE customer_level = 'High Value'
ORDER BY total_spent DESC;

-- =========================================
-- 13. ADS 层：热销商品 Top10 表
-- =========================================
SELECT 'STEP 13: create ads_top10_products' AS step_name;

CREATE TABLE ads_top10_products AS
SELECT
    StockCode,
    Description,
    SUM(Quantity) AS total_qty,
    ROUND(SUM(amount), 2) AS total_sales
FROM retail_clean2
GROUP BY StockCode, Description
ORDER BY total_sales DESC
LIMIT 10;

-- =========================================
-- 14. ADS 层：客户收入集中度分析表
-- =========================================
SELECT 'STEP 14: create ads_customer_revenue_concentration' AS step_name;

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
    SELECT ROUND(SUM(total_spent), 2) AS total_sales
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


-- =========================================
-- 15. ADS 层：国家价值分析表
-- =========================================
SELECT 'STEP 15: create ads_country_value_analysis' AS step_name;

CREATE TABLE ads_country_value_analysis AS
SELECT
    Country,
    COUNT(DISTINCT Invoice) AS total_orders,
    COUNT(DISTINCT CustomerID) AS total_customers,
    ROUND(SUM(amount), 2) AS total_sales,
    ROUND(SUM(amount) / COUNT(DISTINCT Invoice), 2) AS avg_order_value,
    ROUND(SUM(amount) / COUNT(DISTINCT CustomerID), 2) AS avg_customer_value,
    ROUND(COUNT(DISTINCT Invoice) / COUNT(DISTINCT CustomerID), 2) AS orders_per_customer
FROM retail_clean2
GROUP BY Country
ORDER BY total_sales DESC;

-- =========================================
-- 16. ADS 层：客户分层分布分析表
-- =========================================
SELECT 'STEP 16: create ads_customer_level_distribution' AS step_name;

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

-- =========================================
-- 17. ADS 层：商品销售集中度分析表
-- =========================================
SELECT 'STEP 17: create ads_product_sales_concentration' AS step_name;

CREATE TABLE ads_product_sales_concentration AS
WITH product_sales AS (
    SELECT
        StockCode,
        Description,
        ROUND(SUM(amount), 2) AS total_sales
    FROM retail_clean2
    GROUP BY StockCode, Description
),
ranked_products AS (
    SELECT
        StockCode,
        Description,
        total_sales,
        ROW_NUMBER() OVER (ORDER BY total_sales DESC) AS rn
    FROM product_sales
),
total_base AS (
    SELECT ROUND(SUM(total_sales), 2) AS total_sales_all
    FROM product_sales
)
SELECT
    'TOP10' AS product_group,
    COUNT(*) AS product_count,
    ROUND(SUM(total_sales), 2) AS group_sales,
    ROUND(SUM(total_sales) / MAX(total_sales_all) * 100, 2) AS sales_contribution_pct
FROM ranked_products
CROSS JOIN total_base
WHERE rn <= 10

UNION ALL

SELECT
    'TOP50' AS product_group,
    COUNT(*) AS product_count,
    ROUND(SUM(total_sales), 2) AS group_sales,
    ROUND(SUM(total_sales) / MAX(total_sales_all) * 100, 2) AS sales_contribution_pct
FROM ranked_products
CROSS JOIN total_base
WHERE rn <= 50;

-- =========================================
-- 18. ADS 层：客户下单频次分布分析表
-- =========================================
SELECT 'STEP 18: create ads_customer_order_frequency' AS step_name;

CREATE TABLE ads_customer_order_frequency AS
WITH customer_orders AS (
    SELECT
        CustomerID,
        COUNT(DISTINCT Invoice) AS order_count
    FROM retail_clean2
    GROUP BY CustomerID
),
frequency_summary AS (
    SELECT
        CASE
            WHEN order_count = 1 THEN '1_order'
            WHEN order_count BETWEEN 2 AND 3 THEN '2_3_orders'
            WHEN order_count BETWEEN 4 AND 10 THEN '4_10_orders'
            ELSE '10plus_orders'
        END AS order_frequency_level,
        COUNT(*) AS customer_cnt
    FROM customer_orders
    GROUP BY
        CASE
            WHEN order_count = 1 THEN '1_order'
            WHEN order_count BETWEEN 2 AND 3 THEN '2_3_orders'
            WHEN order_count BETWEEN 4 AND 10 THEN '4_10_orders'
            ELSE '10plus_orders'
        END
),
total_base AS (
    SELECT COUNT(*) AS total_customers
    FROM customer_orders
)
SELECT
    f.order_frequency_level,
    f.customer_cnt,
    ROUND(f.customer_cnt / t.total_customers * 100, 2) AS customer_pct
FROM frequency_summary f
CROSS JOIN total_base t
ORDER BY
    CASE f.order_frequency_level
        WHEN '1_order' THEN 1
        WHEN '2_3_orders' THEN 2
        WHEN '4_10_orders' THEN 3
        WHEN '10plus_orders' THEN 4
    END;
		
		-- =========================================
-- 19. ADS 层：高价值客户偏好商品分析表
-- =========================================
SELECT 'STEP 19: create ads_high_value_customer_preference' AS step_name;

CREATE TABLE ads_high_value_customer_preference AS
SELECT
    r.StockCode,
    r.Description,
    COUNT(DISTINCT r.CustomerID) AS high_value_customer_cnt,
    COUNT(DISTINCT r.Invoice) AS order_cnt,
    SUM(r.Quantity) AS total_quantity,
    ROUND(SUM(r.amount), 2) AS total_sales,
    ROUND(SUM(r.amount) / COUNT(DISTINCT r.Invoice), 2) AS avg_order_value
FROM retail_clean2 r
JOIN dws_customer_value d
  ON r.CustomerID = d.CustomerID
WHERE d.customer_level = 'High Value'
GROUP BY r.StockCode, r.Description
ORDER BY high_value_customer_cnt DESC, total_sales DESC
LIMIT 20;

-- =========================================
-- 20. ADS 层：高价值客户下单频次分布分析表
-- =========================================
SELECT 'STEP 20: create ads_high_value_customer_order_frequency' AS step_name;

CREATE TABLE ads_high_value_customer_order_frequency AS
WITH high_value_customer_orders AS (
    SELECT
        r.CustomerID,
        COUNT(DISTINCT r.Invoice) AS order_count
    FROM retail_clean2 r
    JOIN dws_customer_value d
      ON r.CustomerID = d.CustomerID
    WHERE d.customer_level = 'High Value'
    GROUP BY r.CustomerID
),
frequency_summary AS (
    SELECT
        CASE
            WHEN order_count = 1 THEN '1_order'
            WHEN order_count BETWEEN 2 AND 3 THEN '2_3_orders'
            WHEN order_count BETWEEN 4 AND 10 THEN '4_10_orders'
            ELSE '10plus_orders'
        END AS order_frequency_level,
        COUNT(*) AS customer_cnt
    FROM high_value_customer_orders
    GROUP BY
        CASE
            WHEN order_count = 1 THEN '1_order'
            WHEN order_count BETWEEN 2 AND 3 THEN '2_3_orders'
            WHEN order_count BETWEEN 4 AND 10 THEN '4_10_orders'
            ELSE '10plus_orders'
        END
),
total_base AS (
    SELECT COUNT(*) AS total_customers
    FROM high_value_customer_orders
)
SELECT
    f.order_frequency_level,
    f.customer_cnt,
    ROUND(f.customer_cnt / t.total_customers * 100, 2) AS customer_pct
FROM frequency_summary f
CROSS JOIN total_base t
ORDER BY
    CASE f.order_frequency_level
        WHEN '1_order' THEN 1
        WHEN '2_3_orders' THEN 2
        WHEN '4_10_orders' THEN 3
        WHEN '10plus_orders' THEN 4
    END;
		
		-- =========================================
-- 21. ADS 层：高价值客户国家分布分析表
-- =========================================
SELECT 'STEP 21: create ads_high_value_customer_country_distribution' AS step_name;

CREATE TABLE ads_high_value_customer_country_distribution AS
SELECT
    r.Country,
    COUNT(DISTINCT r.CustomerID) AS high_value_customer_cnt,
    COUNT(DISTINCT r.Invoice) AS order_cnt,
    ROUND(SUM(r.amount), 2) AS total_sales,
    ROUND(SUM(r.amount) / COUNT(DISTINCT r.CustomerID), 2) AS avg_customer_value,
    ROUND(COUNT(DISTINCT r.Invoice) / COUNT(DISTINCT r.CustomerID), 2) AS orders_per_customer
FROM retail_clean2 r
JOIN dws_customer_value d
  ON r.CustomerID = d.CustomerID
WHERE d.customer_level = 'High Value'
GROUP BY r.Country
ORDER BY high_value_customer_cnt DESC, total_sales DESC;

-- =========================================
-- 22. ADS 层：高价值客户销售贡献分析表
-- =========================================
SELECT 'STEP 22: create ads_high_value_customer_sales_contribution' AS step_name;

CREATE TABLE ads_high_value_customer_sales_contribution AS
WITH total_sales_base AS (
    SELECT
        ROUND(SUM(amount), 2) AS total_sales
    FROM retail_clean2
),
high_value_sales AS (
    SELECT
        ROUND(SUM(r.amount), 2) AS high_value_total_sales,
        COUNT(DISTINCT r.CustomerID) AS high_value_customer_cnt,
        COUNT(DISTINCT r.Invoice) AS high_value_order_cnt
    FROM retail_clean2 r
    JOIN dws_customer_value d
      ON r.CustomerID = d.CustomerID
    WHERE d.customer_level = 'High Value'
)
SELECT
    h.high_value_customer_cnt,
    h.high_value_order_cnt,
    h.high_value_total_sales,
    t.total_sales,
    ROUND(h.high_value_total_sales / t.total_sales * 100, 2) AS sales_contribution_pct,
    ROUND(h.high_value_total_sales / h.high_value_customer_cnt, 2) AS avg_sales_per_customer,
    ROUND(h.high_value_order_cnt / h.high_value_customer_cnt, 2) AS avg_orders_per_customer
FROM high_value_sales h
CROSS JOIN total_sales_base t;
-- =========================================
-- 23. 结果校验
-- =========================================
SELECT 'STEP 23: check result tables' AS step_name;

SELECT COUNT(*) AS dwd_row_cnt FROM retail_clean2;
SELECT COUNT(*) AS dws_country_cnt FROM dws_sales_summary;
SELECT COUNT(*) AS dws_customer_cnt FROM dws_customer_value;

SELECT * FROM ads_repeat_purchase_summary;
SELECT * FROM ads_monthly_sales_trend LIMIT 5;
SELECT * FROM ads_country_sales_rank LIMIT 10;
SELECT * FROM ads_top10_products LIMIT 10;

SELECT * FROM ads_customer_revenue_concentration;
SELECT * FROM ads_country_value_analysis LIMIT 10;
SELECT * FROM ads_customer_level_distribution;
SELECT * FROM ads_high_value_customer_preference LIMIT 10;
SELECT * FROM ads_high_value_customer_order_frequency;
SELECT * FROM ads_high_value_customer_country_distribution LIMIT 10;
SELECT * FROM ads_high_value_customer_sales_contribution;