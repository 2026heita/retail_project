-- =====================================================
-- File: 06_ads_customer_level_distribution_hive.sql
-- Purpose: Build ADS customer level distribution table
-- Description:
--   1. Read DWS data within date range [start_dt, end_dt]
--   2. Calculate level stats per dt
--   3. Calculate total stats per dt
--   4. JOIN by dt
--   5. Percentage calculated independently per dt
--   6. Dynamic partition write by dt
--   7. Single-day mode: start_dt = end_dt = bizdate
-- Usage:
--   hive --hiveconf bizdate=2026-04-08 \
--        --hiveconf start_dt=2026-04-08 \
--        --hiveconf end_dt=2026-04-08 \
--        -f 06_ads_customer_level_distribution_hive.sql
-- =====================================================

CREATE TABLE IF NOT EXISTS ads_customer_level_distribution_hive (
    customer_level STRING,
    customer_cnt BIGINT,
    total_spent DECIMAL(14,2),
    customer_cnt_pct DECIMAL(10,2),
    sales_pct DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;

WITH level_stats AS (
    SELECT
        dt,
        customer_level,
        COUNT(DISTINCT customerid) AS customer_cnt,
        CAST(ROUND(COALESCE(SUM(total_spent), 0), 2) AS DECIMAL(14,2)) AS total_spent
    FROM dws_customer_value_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
    GROUP BY dt, customer_level
),

total_stats AS (
    SELECT
        dt,
        COUNT(DISTINCT customerid) AS total_customer_cnt,
        CAST(ROUND(COALESCE(SUM(total_spent), 0), 2) AS DECIMAL(14,2)) AS total_sales
    FROM dws_customer_value_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
    GROUP BY dt
)

INSERT OVERWRITE TABLE ads_customer_level_distribution_hive
PARTITION (dt)
SELECT
    level_stats.customer_level,
    level_stats.customer_cnt,
    level_stats.total_spent,
    CAST(
        ROUND(
            CASE
                WHEN total_stats.total_customer_cnt = 0 THEN 0
                ELSE level_stats.customer_cnt / total_stats.total_customer_cnt * 100
            END,
            2
        ) AS DECIMAL(10,2)
    ) AS customer_cnt_pct,
    CAST(
        ROUND(
            CASE
                WHEN total_stats.total_sales IS NULL OR total_stats.total_sales = 0 THEN 0
                ELSE level_stats.total_spent / total_stats.total_sales * 100
            END,
            2
        ) AS DECIMAL(10,2)
    ) AS sales_pct,
    level_stats.dt
FROM level_stats
JOIN total_stats
    ON level_stats.dt = total_stats.dt;
