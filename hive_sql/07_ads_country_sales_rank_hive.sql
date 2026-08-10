-- =====================================================
-- File: 07_ads_country_sales_rank_hive.sql
-- Purpose: Build ADS country sales rank table
-- Description:
--   1. Read DWS data within date range [start_dt, end_dt]
--   2. Rank countries by total_sales per dt
--   3. RANK() OVER (PARTITION BY dt ORDER BY total_sales DESC)
--   4. Dynamic partition write by dt
--   5. Single-day mode: start_dt = end_dt = bizdate
-- Usage:
--   hive --hiveconf bizdate=2026-04-08 \
--        --hiveconf start_dt=2026-04-08 \
--        --hiveconf end_dt=2026-04-08 \
--        -f 07_ads_country_sales_rank_hive.sql
-- =====================================================

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

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;

INSERT OVERWRITE TABLE ads_country_sales_rank_hive
PARTITION (dt)
SELECT
    country,
    RANK() OVER (PARTITION BY dt ORDER BY total_sales DESC) AS sales_rank,
    total_orders,
    total_customers,
    total_sales,
    avg_order_value,
    dt
FROM dws_sales_summary_hive
WHERE dt >= '${hiveconf:start_dt}'
  AND dt <= '${hiveconf:end_dt}';
