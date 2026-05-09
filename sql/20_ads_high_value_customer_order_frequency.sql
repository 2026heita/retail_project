USE retail_project;

-- =============================
-- ADS：高价值客户下单频次分布分析
-- 统计高价值客户在不同下单频次区间的人数及占比
-- 用于判断高价值客户是一次性高消费还是持续高频复购
-- =============================

DROP TABLE IF EXISTS ads_high_value_customer_order_frequency;

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

-- 查看结果
SELECT * FROM ads_high_value_customer_order_frequency;