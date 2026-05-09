CREATE TABLE IF NOT EXISTS dws_customer_value_hive (
    customerid STRING,
    order_count BIGINT,
    total_spent DECIMAL(12,2),
    customer_level STRING
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

INSERT OVERWRITE TABLE dws_customer_value_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    customerid,
    COUNT(DISTINCT invoice) AS order_count,
    CAST(ROUND(SUM(amount), 2) AS DECIMAL(12,2)) AS total_spent,
    CASE
        WHEN SUM(amount) >= 5000 THEN 'High Value'
        WHEN SUM(amount) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_level
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY customerid;