USE retail_project;

-- =============================
-- ADS：高价值客户国家分布分析
-- =============================

DROP TABLE IF EXISTS ads_high_value_customer_country_distribution;

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

-- 查看结果
SELECT * FROM ads_high_value_customer_country_distribution;

-- 进一步分析了高价值客户的国家分布，统计各国家高价值客户数量、销售贡献、人均价值和订单密度，用于识别高价值客户更集中的重点市场，为区域化客户运营提供依据