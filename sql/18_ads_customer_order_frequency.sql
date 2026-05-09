USE retail_project;

-- =============================
-- ADS：客户下单频次分布分析
-- =============================

DROP TABLE IF EXISTS ads_customer_order_frequency;

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

-- 查看结果
SELECT * FROM ads_customer_order_frequency;

-- 这个指标把全体客户按下单次数分成四档，用来观察整体客户活跃深度，比单纯复购率更细。