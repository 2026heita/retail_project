-- =====================================================
-- 文件名: 05_ads_high_value_customer_sales_contribution_hive.sql
-- 功能: 生成 ADS 高价值客户销售贡献表
-- 优化: 大表 dwd join 小表 dws_customer_value，使用 MAPJOIN
-- =====================================================

CREATE TABLE IF NOT EXISTS ads_high_value_customer_sales_contribution_hive (
    high_value_customer_cnt BIGINT,
    high_value_order_cnt BIGINT,
    high_value_total_sales DECIMAL(14,2),
    total_sales DECIMAL(14,2),
    sales_contribution_pct DECIMAL(10,2),
    avg_sales_per_customer DECIMAL(14,2),
    avg_orders_per_customer DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

INSERT OVERWRITE TABLE ads_high_value_customer_sales_contribution_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    h.high_value_customer_cnt,
    h.high_value_order_cnt,
    h.high_value_total_sales,
    t.total_sales,
    CAST(
        ROUND(
            CASE
                WHEN t.total_sales IS NULL OR t.total_sales = 0 THEN 0
                ELSE h.high_value_total_sales / t.total_sales * 100
            END,
            2
        ) AS DECIMAL(10,2)
    ) AS sales_contribution_pct,
    CAST(
        ROUND(
            CASE
                WHEN h.high_value_customer_cnt = 0 THEN 0
                ELSE h.high_value_total_sales / h.high_value_customer_cnt
            END,
            2
        ) AS DECIMAL(14,2)
    ) AS avg_sales_per_customer,
    CAST(
        ROUND(
            CASE
                WHEN h.high_value_customer_cnt = 0 THEN 0
                ELSE h.high_value_order_cnt / h.high_value_customer_cnt
            END,
            2
        ) AS DECIMAL(10,2)
    ) AS avg_orders_per_customer
FROM (
    SELECT /*+ MAPJOIN(cv) */
        COUNT(DISTINCT cv.customerid) AS high_value_customer_cnt,
        COUNT(DISTINCT d.invoice) AS high_value_order_cnt,
        COALESCE(
            CAST(SUM(d.amount) AS DECIMAL(14,2)),
            CAST(0 AS DECIMAL(14,2))
        ) AS high_value_total_sales
    FROM dwd_retail_clean_hive d
    JOIN dws_customer_value_hive cv
        ON d.customerid = cv.customerid
    WHERE d.dt = '${hiveconf:bizdate}'
      AND cv.dt = '${hiveconf:bizdate}'
      AND cv.customer_level = 'High Value'
) h
JOIN (
    SELECT
    COALESCE(
        CAST(SUM(amount) AS DECIMAL(14,2)),
        CAST(0 AS DECIMAL(14,2))
    ) AS total_sales
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
) t
ON 1=1;