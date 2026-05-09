USE retail_project;

-- =============================
-- ADS：高价值客户销售贡献分析
-- 统计高价值客户人数、订单数、销售额及其销售贡献占比
-- 用于衡量平台收入对高价值客户的依赖程度
-- =============================

DROP TABLE IF EXISTS ads_high_value_customer_sales_contribution;

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

-- 查看结果
SELECT * FROM ads_high_value_customer_sales_contribution;