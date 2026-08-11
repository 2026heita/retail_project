-- =====================================================
-- File: 03_dws_customer_value_hive.sql
-- Purpose: Build DWS customer value table
-- Description:
--   1. Read DWD data within date range [start_dt, end_dt]
--   2. Group by dt and customerid for daily granularity
--   3. Customer level thresholds:
--      >= 5000: High Value
--      >= 1000: Medium Value
--      others:  Low Value
--   4. Dynamic partition write by dt
--   5. Single-day mode: start_dt = end_dt = bizdate
-- Usage:
--   hive --hiveconf bizdate=2026-04-08 \
--        --hiveconf start_dt=2026-04-08 \
--        --hiveconf end_dt=2026-04-08 \
--        -f 03_dws_customer_value_hive.sql
-- =====================================================

CREATE TABLE IF NOT EXISTS dws_customer_value_hive (
    customerid STRING,
    order_count BIGINT,
    total_spent DECIMAL(12,2),
    customer_level STRING
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;

INSERT OVERWRITE TABLE dws_customer_value_hive
PARTITION (dt)
SELECT
    customerid,
    COUNT(DISTINCT invoice) AS order_count,
    CAST(ROUND(SUM(amount), 2) AS DECIMAL(12,2)) AS total_spent,
    CASE
        WHEN SUM(amount) >= 5000 THEN 'High Value'
        WHEN SUM(amount) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_level,
    dt
FROM dwd_retail_clean_hive
WHERE dt >= '${hiveconf:start_dt}'
  AND dt <= '${hiveconf:end_dt}'
GROUP BY dt, customerid;
