USE retail_project;

-- =====================
-- 一、客户行为分析（复购）
-- =====================

-- 每个客户下单次数 + 总消费
SELECT
    CustomerID,
    COUNT(DISTINCT Invoice) AS order_cnt,
    ROUND(SUM(amount), 2) AS total_spent
FROM retail_clean2
GROUP BY CustomerID
ORDER BY order_cnt DESC;

-- 复购客户数（下单次数 > 1）
SELECT
    COUNT(*) AS repeat_customers
FROM (
    SELECT CustomerID
    FROM retail_clean2
    GROUP BY CustomerID
    HAVING COUNT(DISTINCT Invoice) > 1
) t;

-- 总客户数
SELECT COUNT(DISTINCT CustomerID) AS total_customers
FROM retail_clean2;

-- 复购率（%）
SELECT
    ROUND(
        COUNT(*) / (
            SELECT COUNT(DISTINCT CustomerID) FROM retail_clean2
        ) * 100,
        2
    ) AS repeat_rate_pct
FROM (
    SELECT CustomerID
    FROM retail_clean2
    GROUP BY CustomerID
    HAVING COUNT(DISTINCT Invoice) > 1
) t;

-- =====================
-- 二、时间趋势进阶分析（环比）
-- =====================

-- 每月销售额
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
    ROUND(SUM(amount), 2) AS monthly_sales
FROM retail_clean2
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY month;

-- 每月销售额 + 上月销售额 + 增长额
SELECT
    month,
    monthly_sales,
    LAG(monthly_sales) OVER (ORDER BY month) AS prev_month_sales,
    ROUND(
        monthly_sales - LAG(monthly_sales) OVER (ORDER BY month),
        2
    ) AS growth
FROM (
    SELECT
        DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
        ROUND(SUM(amount), 2) AS monthly_sales
    FROM retail_clean2
    GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
) t;

-- =====================
-- 三、客户分层（按消费金额）
-- =====================

-- 每个客户总消费
SELECT
    CustomerID,
    ROUND(SUM(amount), 2) AS total_spent
FROM retail_clean2
GROUP BY CustomerID;

-- 客户分层统计
SELECT
    CASE
        WHEN total_spent >= 5000 THEN 'High Value'
        WHEN total_spent >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_level,
    COUNT(*) AS customer_cnt
FROM (
    SELECT
        CustomerID,
        SUM(amount) AS total_spent
    FROM retail_clean2
    GROUP BY CustomerID
) t
GROUP BY customer_level
ORDER BY customer_cnt DESC;

-- =====================
-- 四、补充：每月Top3国家（练习窗口函数）
-- =====================

SELECT *
FROM (
    SELECT
        DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
        Country,
        ROUND(SUM(amount), 2) AS total_sales,
        ROW_NUMBER() OVER (
            PARTITION BY DATE_FORMAT(InvoiceDate, '%Y-%m')
            ORDER BY SUM(amount) DESC
        ) AS rn
    FROM retail_clean2
    GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m'), Country
) t
WHERE rn <= 3;