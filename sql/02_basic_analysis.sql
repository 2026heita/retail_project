USE retail_project;

-- =====================
-- KPI
-- =====================

-- 总销售额
SELECT ROUND(SUM(amount), 2) AS total_sales
FROM retail_clean2;

-- 总订单数
SELECT COUNT(DISTINCT Invoice) AS total_orders
FROM retail_clean2;

-- 总客户数
SELECT COUNT(DISTINCT CustomerID) AS total_customers
FROM retail_clean2;

-- 客单价
SELECT ROUND(SUM(amount) / COUNT(DISTINCT Invoice), 2) AS avg_order_value
FROM retail_clean2;

-- 人均消费
SELECT ROUND(SUM(amount) / COUNT(DISTINCT CustomerID), 2) AS avg_customer_value
FROM retail_clean2;

-- =====================
-- 商品分析
-- =====================

-- 商品销售额 Top10
SELECT
    StockCode,
    Description,
    ROUND(SUM(amount), 2) AS total
FROM retail_clean2
GROUP BY StockCode, Description
ORDER BY total DESC
LIMIT 10;

-- 商品销量 Top10
SELECT
    StockCode,
    Description,
    SUM(Quantity) AS total_qty
FROM retail_clean2
GROUP BY StockCode, Description
ORDER BY total_qty DESC
LIMIT 10;

-- 商品平均单价 Top10
SELECT
    StockCode,
    Description,
    ROUND(AVG(Price), 2) AS avg_price
FROM retail_clean2
GROUP BY StockCode, Description
ORDER BY avg_price DESC
LIMIT 10;

-- =====================
-- 客户分析
-- =====================

-- 客户消费额 Top10
SELECT
    CustomerID,
    ROUND(SUM(amount), 2) AS total_spent
FROM retail_clean2
GROUP BY CustomerID
ORDER BY total_spent DESC
LIMIT 10;

-- 客户下单次数 Top10
SELECT
    CustomerID,
    COUNT(DISTINCT Invoice) AS order_cnt
FROM retail_clean2
GROUP BY CustomerID
ORDER BY order_cnt DESC
LIMIT 10;

-- 客户平均每单消费 Top10
SELECT
    CustomerID,
    ROUND(SUM(amount) / COUNT(DISTINCT Invoice), 2) AS avg_order_value
FROM retail_clean2
GROUP BY CustomerID
ORDER BY avg_order_value DESC
LIMIT 10;

-- =====================
-- 国家分析
-- =====================

-- 各国销售额
SELECT
    Country,
    ROUND(SUM(amount), 2) AS total_sales
FROM retail_clean2
GROUP BY Country
ORDER BY total_sales DESC;

-- 各国客户数
SELECT
    Country,
    COUNT(DISTINCT CustomerID) AS customer_cnt
FROM retail_clean2
GROUP BY Country
ORDER BY customer_cnt DESC;

-- =====================
-- 时间分析
-- =====================

-- 每月销售额趋势
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
    ROUND(SUM(amount), 2) AS monthly_sales
FROM retail_clean2
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY month;

-- 每月订单数趋势
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
    COUNT(DISTINCT Invoice) AS monthly_orders
FROM retail_clean2
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY month;