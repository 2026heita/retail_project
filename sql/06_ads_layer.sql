USE retail_project;

-- =============================
-- 一、ADS：客户复购率指标表
-- =============================

DROP TABLE IF EXISTS ads_repeat_purchase_summary;

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

-- 查看结果
SELECT * FROM ads_repeat_purchase_summary;


-- =============================
-- 二、ADS：月度销售趋势表
-- =============================

DROP TABLE IF EXISTS ads_monthly_sales_trend;

CREATE TABLE ads_monthly_sales_trend AS
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
    ROUND(SUM(amount), 2) AS monthly_sales,
    COUNT(DISTINCT Invoice) AS monthly_orders,
    COUNT(DISTINCT CustomerID) AS monthly_customers
FROM retail_clean2
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY month;

-- 查看结果
SELECT * FROM ads_monthly_sales_trend;


-- =============================
-- 三、ADS：月度销售增长分析表
-- =============================

DROP TABLE IF EXISTS ads_monthly_sales_growth;

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

-- 查看结果
SELECT * FROM ads_monthly_sales_growth;


-- =============================
-- 四、ADS：国家销售排行表
-- =============================

DROP TABLE IF EXISTS ads_country_sales_rank;

CREATE TABLE ads_country_sales_rank AS
SELECT
    Country,
    ROUND(SUM(amount), 2) AS total_sales,
    COUNT(DISTINCT Invoice) AS total_orders,
    COUNT(DISTINCT CustomerID) AS total_customers,
    RANK() OVER (ORDER BY SUM(amount) DESC) AS sales_rank
FROM retail_clean2
GROUP BY Country;

-- 查看结果
SELECT * FROM ads_country_sales_rank;


-- =============================
-- 五、ADS：高价值客户名单表
-- =============================

DROP TABLE IF EXISTS ads_high_value_customers;

CREATE TABLE ads_high_value_customers AS
SELECT
    CustomerID,
    order_count,
    ROUND(total_spent, 2) AS total_spent,
    customer_level
FROM dws_customer_value
WHERE customer_level = 'High Value'
ORDER BY total_spent DESC;

-- 查看结果
SELECT * FROM ads_high_value_customers;


-- =============================
-- 六、ADS：热销商品 Top10 表
-- =============================

DROP TABLE IF EXISTS ads_top10_products;

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

-- 查看结果
SELECT * FROM ads_top10_products;