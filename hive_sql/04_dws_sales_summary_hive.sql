-- =====================================================
-- File: 04_dws_sales_summary_hive.sql
-- Purpose: Build DWS country sales summary table
-- Description:
--   1. Read DWD data within date range [start_dt, end_dt]
--   2. All stages carry dt for daily granularity
--   3. Deterministic CRC32 salt for United Kingdom skew
--   4. Two-phase aggregation: salt -> country
--   5. Use existing amount field from DWD (not quantity * price)
--   6. Dynamic partition write by dt
--   7. Single-day mode: start_dt = end_dt = bizdate
-- Usage:
--   hive --hiveconf bizdate=2026-04-08 \
--        --hiveconf start_dt=2026-04-08 \
--        --hiveconf end_dt=2026-04-08 \
--        -f 04_dws_sales_summary_hive.sql
-- =====================================================

CREATE TABLE IF NOT EXISTS dws_sales_summary_hive (
    country STRING COMMENT 'Country',
    total_orders BIGINT COMMENT 'Order count',
    total_customers BIGINT COMMENT 'Customer count',
    total_sales DECIMAL(14,2) COMMENT 'Total sales',
    avg_order_value DECIMAL(14,2) COMMENT 'Average order value'
)
COMMENT 'DWS country sales summary'
PARTITIONED BY (dt STRING COMMENT 'Business date')
STORED AS ORC;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;
SET hive.groupby.skewindata=false;

WITH base AS (
    SELECT
        dt,
        country,
        invoice,
        stockcode,
        customerid,
        invoicedate,
        amount
    FROM dwd_retail_clean_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

-- 1. Deterministic salt for United Kingdom skew
sales_salted AS (
    SELECT
        dt,
        country,
        CASE
            WHEN country = 'United Kingdom'
            THEN PMOD(
                CRC32(
                    CONCAT_WS('#|#',
                        COALESCE(invoice, ''),
                        COALESCE(stockcode, ''),
                        COALESCE(customerid, ''),
                        COALESCE(invoicedate, '')
                    )
                ),
                20
            )
            ELSE 0
        END AS salt_key,
        amount
    FROM base
),

-- 2. Phase 1 aggregation by dt, country, salt_key
sales_stage1 AS (
    SELECT
        dt,
        country,
        salt_key,
        SUM(amount) AS partial_sales
    FROM sales_salted
    GROUP BY dt, country, salt_key
),

-- 3. Phase 2 aggregation back to country by dt
sales_final AS (
    SELECT
        dt,
        country,
        CAST(SUM(partial_sales) AS DECIMAL(14,2)) AS total_sales
    FROM sales_stage1
    GROUP BY dt, country
),

-- 4. Order count: deduplicate by dt, country, invoice
order_final AS (
    SELECT
        dt,
        country,
        COUNT(*) AS total_orders
    FROM (
        SELECT dt, country, invoice
        FROM base
        GROUP BY dt, country, invoice
    ) t
    GROUP BY dt, country
),

-- 5. Customer count: deduplicate by dt, country, customerid
customer_final AS (
    SELECT
        dt,
        country,
        COUNT(*) AS total_customers
    FROM (
        SELECT dt, country, customerid
        FROM base
        GROUP BY dt, country, customerid
    ) t
    GROUP BY dt, country
)

-- 6. Final insert with dynamic partition
INSERT OVERWRITE TABLE dws_sales_summary_hive
PARTITION (dt)
SELECT
    s.country,
    o.total_orders,
    c.total_customers,
    s.total_sales,
    CAST(
        CASE
            WHEN o.total_orders = 0 THEN 0
            ELSE s.total_sales / o.total_orders
        END AS DECIMAL(14,2)
    ) AS avg_order_value,
    s.dt
FROM sales_final s
LEFT JOIN order_final o
    ON s.dt = o.dt
   AND s.country = o.country
LEFT JOIN customer_final c
    ON s.dt = c.dt
   AND s.country = c.country;
