-- =====================================================
-- File: 08_ads_high_value_customer_preference_hive.sql
-- Purpose: Build ADS high-value customer preference table
-- Description:
--   1. Read DWD and DWS data within date range [start_dt, end_dt]
--   2. JOIN condition includes both customerid AND dt
--   3. Aggregate by dt, stockcode (NOT description)
--   4. Select one description per dt+stockcode using ROW_NUMBER
--   5. Rank by total_sales per dt
--   6. RANK() OVER (PARTITION BY dt ORDER BY total_sales DESC)
--   7. Dynamic partition write by dt
--   8. Single-day mode: start_dt = end_dt = bizdate
-- Usage:
--   hive --hiveconf bizdate=2026-04-08 \
--        --hiveconf start_dt=2026-04-08 \
--        --hiveconf end_dt=2026-04-08 \
--        -f 08_ads_high_value_customer_preference_hive.sql
-- =====================================================

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

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;

WITH high_value_detail AS (
    SELECT
        dwd.dt,
        dwd.stockcode,
        dwd.description,
        dwd.customerid,
        dwd.invoice,
        dwd.quantity,
        dwd.amount,
        dwd.invoicedate
    FROM dwd_retail_clean_hive dwd
    JOIN dws_customer_value_hive dws
        ON dwd.customerid = dws.customerid
       AND dwd.dt = dws.dt
    WHERE dwd.dt >= '${hiveconf:start_dt}'
      AND dwd.dt <= '${hiveconf:end_dt}'
      AND dws.dt >= '${hiveconf:start_dt}'
      AND dws.dt <= '${hiveconf:end_dt}'
      AND dws.customer_level = 'High Value'
),

product_metrics AS (
    SELECT
        dt,
        stockcode,
        COUNT(DISTINCT customerid) AS high_value_customer_cnt,
        COUNT(DISTINCT invoice) AS high_value_order_cnt,
        SUM(quantity) AS total_quantity,
        CAST(ROUND(SUM(amount), 2) AS DECIMAL(14,2)) AS total_sales
    FROM high_value_detail
    GROUP BY dt, stockcode
),

description_ranked AS (
    SELECT
        dt,
        stockcode,
        description,
        ROW_NUMBER() OVER (
            PARTITION BY dt, stockcode
            ORDER BY
                CASE
                    WHEN description IS NULL OR TRIM(description) = '' THEN 1
                    ELSE 0
                END ASC,
                invoicedate DESC,
                description DESC
        ) AS rn
    FROM high_value_detail
)

INSERT OVERWRITE TABLE ads_high_value_customer_preference_hive
PARTITION (dt)
SELECT
    pm.stockcode,
    dr.description,
    pm.high_value_customer_cnt,
    pm.high_value_order_cnt,
    pm.total_quantity,
    pm.total_sales,
    RANK() OVER (PARTITION BY pm.dt ORDER BY pm.total_sales DESC) AS sales_rank,
    pm.dt
FROM product_metrics pm
LEFT JOIN description_ranked dr
    ON pm.dt = dr.dt
   AND pm.stockcode = dr.stockcode
   AND dr.rn = 1;
