-- =====================================================
-- 文件名: 05_ads_high_value_customer_sales_contribution_hive.sql
-- 功能: 生成 ADS 高价值客户销售贡献表
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
    SELECT
        COUNT(DISTINCT dwd.customerid) AS high_value_customer_cnt,
        COUNT(DISTINCT dwd.invoice) AS high_value_order_cnt,
        CAST(ROUND(COALESCE(SUM(dwd.amount), 0), 2) AS DECIMAL(14,2)) AS high_value_total_sales
    FROM dwd_retail_clean_hive dwd
    JOIN dws_customer_value_hive dws
      ON dwd.customerid = dws.customerid
    WHERE dwd.dt = '${hiveconf:bizdate}'
      AND dws.dt = '${hiveconf:bizdate}'
      AND dws.customer_level = 'High Value'
) h
CROSS JOIN (
    SELECT
        CAST(ROUND(COALESCE(SUM(amount), 0), 2) AS DECIMAL(14,2)) AS total_sales
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
) t;
