USE retail_project;

-- =============================
-- ADS：高价值客户偏好商品分析
-- 统计高价值客户购买商品的客户覆盖人数、订单数、销量和销售额
-- 用于识别更受核心客群欢迎的商品
-- =============================

DROP TABLE IF EXISTS ads_high_value_customer_preference;

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

-- 查看结果
SELECT * FROM ads_high_value_customer_preference;