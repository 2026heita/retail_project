CREATE TABLE IF NOT EXISTS ads_country_sales_rank_hive (
    country STRING,
    sales_rank BIGINT,
    total_orders BIGINT,
    total_customers BIGINT,
    total_sales DECIMAL(14,2),
    avg_order_value DECIMAL(14,2)
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

INSERT OVERWRITE TABLE ads_country_sales_rank_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT 
    country,
    RANK() OVER (ORDER BY total_sales DESC) AS sales_rank,
    total_orders,
    total_customers,
    total_sales,
    avg_order_value
FROM dws_sales_summary_hive
WHERE dt = '${hiveconf:bizdate}';