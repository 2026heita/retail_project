CREATE TABLE IF NOT EXISTS dws_sales_summary_hive (
    country STRING,
    total_orders BIGINT,
    total_customers BIGINT,
    total_sales DECIMAL(14,2),
    avg_order_value DECIMAL(14,2)
)
PARTITIONED BY (dt STRING)
STORED AS ORC;


INSERT OVERWRITE TABLE dws_sales_summary_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    country,
    COUNT(DISTINCT invoice) AS total_orders,
    COUNT(DISTINCT customerid) AS total_customers,
    CAST(ROUND(SUM(amount), 2) AS DECIMAL(14,2)) AS total_sales,
    CAST(ROUND(SUM(amount) / COUNT(DISTINCT invoice), 2) AS DECIMAL(14,2)) AS avg_order_value
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY country;