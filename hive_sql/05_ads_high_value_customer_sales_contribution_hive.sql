-- =====================================================
-- File: 05_ads_high_value_customer_sales_contribution_hive.sql
-- Purpose: Build ADS high-value customer sales contribution table
-- Description:
--   1. Read DWD and DWS data within date range [start_dt, end_dt]
--   2. JOIN condition includes both customerid and dt
--   3. Calculate high-value metrics per dt
--   4. Keep every DWD business date, even when no high-value customer exists
--   5. Division by zero returns 0
--   6. Dynamic partition write by dt
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

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;

WITH total_sales_by_date AS (
    SELECT
        dt,
        CAST(
            ROUND(SUM(amount), 2)
            AS DECIMAL(14,2)
        ) AS total_sales
    FROM dwd_retail_clean_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
    GROUP BY dt
),

high_value_metrics AS (
    SELECT
        d.dt,

        COUNT(DISTINCT cv.customerid)
            AS high_value_customer_cnt,

        COUNT(DISTINCT d.invoice)
            AS high_value_order_cnt,

        CAST(
            ROUND(SUM(d.amount), 2)
            AS DECIMAL(14,2)
        ) AS high_value_total_sales

    FROM dwd_retail_clean_hive d

    JOIN dws_customer_value_hive cv
      ON d.customerid = cv.customerid
     AND d.dt = cv.dt

    WHERE d.dt >= '${hiveconf:start_dt}'
      AND d.dt <= '${hiveconf:end_dt}'

      AND cv.dt >= '${hiveconf:start_dt}'
      AND cv.dt <= '${hiveconf:end_dt}'

      AND cv.customer_level = 'High Value'

    GROUP BY d.dt
)

INSERT OVERWRITE TABLE
    ads_high_value_customer_sales_contribution_hive
PARTITION (dt)

SELECT
    COALESCE(
        h.high_value_customer_cnt,
        CAST(0 AS BIGINT)
    ) AS high_value_customer_cnt,

    COALESCE(
        h.high_value_order_cnt,
        CAST(0 AS BIGINT)
    ) AS high_value_order_cnt,

    COALESCE(
        h.high_value_total_sales,
        CAST(0 AS DECIMAL(14,2))
    ) AS high_value_total_sales,

    t.total_sales,

    CAST(
        ROUND(
            CASE
                WHEN t.total_sales IS NULL
                  OR t.total_sales = 0
                THEN 0

                ELSE
                    COALESCE(
                        h.high_value_total_sales,
                        CAST(0 AS DECIMAL(14,2))
                    )
                    / t.total_sales
                    * 100
            END,
            2
        )
        AS DECIMAL(10,2)
    ) AS sales_contribution_pct,

    CAST(
        ROUND(
            CASE
                WHEN COALESCE(
                    h.high_value_customer_cnt,
                    CAST(0 AS BIGINT)
                ) = 0
                THEN 0

                ELSE
                    h.high_value_total_sales
                    / h.high_value_customer_cnt
            END,
            2
        )
        AS DECIMAL(14,2)
    ) AS avg_sales_per_customer,

    CAST(
        ROUND(
            CASE
                WHEN COALESCE(
                    h.high_value_customer_cnt,
                    CAST(0 AS BIGINT)
                ) = 0
                THEN 0

                ELSE
                    CAST(h.high_value_order_cnt AS DECIMAL(14,2))
                    / h.high_value_customer_cnt
            END,
            2
        )
        AS DECIMAL(10,2)
    ) AS avg_orders_per_customer,

    t.dt

FROM total_sales_by_date t

LEFT JOIN high_value_metrics h
  ON t.dt = h.dt;