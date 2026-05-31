CREATE TABLE IF NOT EXISTS ads_high_value_customer_preference_hive (
    stockcode STRING,
    description STRING,
    high_value_customer_cnt BIGINT,
    high_value_order_cnt BIGINT,
    total_quantity BIGINT,
    total_sales DECIMAL(14,2),
    sales_rank BIGINT
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

INSERT OVERWRITE TABLE ads_high_value_customer_preference_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    t.stockcode,
    t.description,
    t.high_value_customer_cnt,
    t.high_value_order_cnt,
    t.total_quantity,
    t.total_sales,
    RANK() OVER (ORDER BY t.total_sales DESC) AS sales_rank
FROM (
    SELECT /*+ MAPJOIN(dws) */
        dwd.stockcode,
        dwd.description,
        COUNT(DISTINCT dwd.customerid) AS high_value_customer_cnt,
        COUNT(DISTINCT dwd.invoice) AS high_value_order_cnt,
        SUM(dwd.quantity) AS total_quantity,
        CAST(ROUND(SUM(dwd.amount), 2) AS DECIMAL(14,2)) AS total_sales
    FROM dwd_retail_clean_hive dwd
    JOIN dws_customer_value_hive dws
        ON dwd.customerid = dws.customerid
    WHERE dwd.dt = '${hiveconf:bizdate}'
      AND dws.dt = '${hiveconf:bizdate}'
      AND dws.customer_level = 'High Value'
    GROUP BY
        dwd.stockcode,
        dwd.description
) t;