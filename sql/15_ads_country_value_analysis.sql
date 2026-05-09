USE retail_project;

-- =============================
-- ADS：国家价值分析
-- 统计各国家订单数、客户数、销售额、客单价、人均消费和每客订单数
-- 用于分析不同国家市场的规模与消费质量差异
-- =============================

DROP TABLE IF EXISTS ads_country_value_analysis;

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

-- 查看结果
SELECT * FROM ads_country_value_analysis;