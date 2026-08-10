-- =====================================================
-- File: 32_dwd_canonical_full_validation_hive.sql
-- Purpose: Validate the complete canonical DWD load
-- Notes:
--   1. Recalculate valid source rows using the daily DWD rules
--   2. Compare valid ODS rows with the complete DWD result
--   3. Validate partitions, date range, field normalization, and amount
-- =====================================================

WITH ods_parsed AS (
    SELECT
        invoice,
        stockcode,
        description,
        quantity,
        invoicedate,
        price,
        customerid,
        country,
        dt,

        COALESCE(
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'yyyy-MM-dd HH:mm:ss'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'yyyy-MM-dd HH:mm'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'd/M/yyyy HH:mm:ss'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'd/M/yyyy HH:mm'
            )
        ) AS invoice_ts

    FROM ods_retail_hive
),

ods_metrics AS (
    SELECT
        COUNT(*) AS ods_total_count,
        COUNT(DISTINCT dt) AS ods_partition_count
    FROM ods_retail_hive
),

valid_source_metrics AS (
    SELECT
        COUNT(*) AS valid_source_count,
        COUNT(DISTINCT dt) AS valid_source_partition_count,
        MIN(dt) AS valid_source_min_dt,
        MAX(dt) AS valid_source_max_dt
    FROM ods_parsed
    WHERE quantity > 0
      AND price > 0

      AND customerid IS NOT NULL
      AND TRIM(CAST(customerid AS STRING)) <> ''

      AND invoice IS NOT NULL
      AND TRIM(invoice) <> ''
      AND UPPER(TRIM(invoice)) NOT LIKE 'C%'

      AND stockcode IS NOT NULL
      AND TRIM(stockcode) <> ''

      AND country IS NOT NULL
      AND TRIM(country) <> ''

      AND invoicedate IS NOT NULL
      AND TRIM(invoicedate) <> ''

      AND invoice_ts IS NOT NULL

      AND dt IS NOT NULL
      AND TRIM(dt) <> ''
),

dwd_metrics AS (
    SELECT
        COUNT(*) AS dwd_total_count,
        COUNT(DISTINCT dt) AS dwd_partition_count,
        MIN(dt) AS dwd_min_dt,
        MAX(dt) AS dwd_max_dt,

        SUM(
            CASE
                WHEN customerid LIKE '%.0'
                THEN 1
                ELSE 0
            END
        ) AS customerid_dot0_count,

        SUM(
            CASE
                WHEN invoice <> TRIM(invoice)
                THEN 1
                ELSE 0
            END
        ) AS invoice_space_count,

        SUM(
            CASE
                WHEN stockcode <> UPPER(TRIM(stockcode))
                THEN 1
                ELSE 0
            END
        ) AS stockcode_invalid_count,

        SUM(
            CASE
                WHEN amount <= 0
                THEN 1
                ELSE 0
            END
        ) AS invalid_amount_count,

        SUM(
            CASE
                WHEN dt < '2009-12-01'
                  OR dt > '2011-12-09'
                  OR dt IS NULL
                THEN 1
                ELSE 0
            END
        ) AS outside_date_range_count

    FROM dwd_retail_clean_hive
)

SELECT
    o.ods_total_count,
    o.ods_partition_count,

    v.valid_source_count,
    v.valid_source_partition_count,
    v.valid_source_min_dt,
    v.valid_source_max_dt,

    d.dwd_total_count,
    d.dwd_partition_count,
    d.dwd_min_dt,
    d.dwd_max_dt,

    d.customerid_dot0_count,
    d.invoice_space_count,
    d.stockcode_invalid_count,
    d.invalid_amount_count,
    d.outside_date_range_count,

    ASSERT_TRUE(
        d.dwd_total_count = v.valid_source_count
    ) AS row_count_gate,

    ASSERT_TRUE(
        d.dwd_partition_count = v.valid_source_partition_count
    ) AS partition_count_gate,

    ASSERT_TRUE(
        d.customerid_dot0_count = 0
    ) AS customerid_dot0_gate,

    ASSERT_TRUE(
        d.invoice_space_count = 0
    ) AS invoice_space_gate,

    ASSERT_TRUE(
        d.stockcode_invalid_count = 0
    ) AS stockcode_normalization_gate,

    ASSERT_TRUE(
        d.invalid_amount_count = 0
    ) AS amount_gate,

    ASSERT_TRUE(
        d.outside_date_range_count = 0
    ) AS date_range_gate,

    ASSERT_TRUE(
        d.dwd_min_dt = '2009-12-01'
    ) AS min_date_gate,

    ASSERT_TRUE(
        d.dwd_max_dt = '2011-12-09'
    ) AS max_date_gate

FROM ods_metrics o
CROSS JOIN valid_source_metrics v
CROSS JOIN dwd_metrics d;