-- =====================================================
-- File: 00_load_ods_retail_all_dates_hive.sql
-- Purpose: One-time load all dates from ODS Raw to normal ODS
-- Description:
--   1. For canonical data first ingestion, no date loop
--   2. Dynamic partition, dt parsed from InvoiceDate
--   3. Parse invoice_timestamp, parsed_quantity, parsed_price
--   4. Technical admission: all three must be non-NULL
--   5. Business issues (quantity<=0, returns, empty customerid, etc.)
--      are NOT filtered here; DWD handles those
--   6. Date formats: yyyy-MM-dd HH:mm:ss, yyyy-MM-dd HH:mm,
--      d/M/yyyy HH:mm:ss, d/M/yyyy HH:mm
--   7. INSERT OVERWRITE ensures idempotent result
--   8. Requires hive.exec.dynamic.partition=true and nonstrict
-- Usage:
--   hive --hiveconf batch_dt=2026-08-04 \
--        -f 00_load_ods_retail_all_dates_hive.sql
-- =====================================================

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;

WITH parsed_source AS (
    SELECT
        invoice,
        stockcode,
        description,
        quantity,
        invoicedate,
        price,
        customerid,
        country,
        COALESCE(
            UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm:ss'),
            UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm'),
            UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm:ss'),
            UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm')
        ) AS invoice_timestamp,
        CASE
            WHEN TRIM(CAST(quantity AS STRING)) IS NULL
              OR TRIM(CAST(quantity AS STRING)) = ''
            THEN NULL
            ELSE CAST(TRIM(CAST(quantity AS STRING)) AS BIGINT)
        END AS parsed_quantity,
        CASE
            WHEN TRIM(CAST(price AS STRING)) IS NULL
              OR TRIM(CAST(price AS STRING)) = ''
            THEN NULL
            ELSE CAST(TRIM(CAST(price AS STRING)) AS DECIMAL(10,2))
        END AS parsed_price
    FROM ods_retail_raw_hive
    WHERE batch_dt = '${hiveconf:batch_dt}'
)

INSERT OVERWRITE TABLE ods_retail_hive
PARTITION (dt)
SELECT
    CAST(invoice AS STRING) AS invoice,
    CAST(stockcode AS STRING) AS stockcode,
    CAST(description AS STRING) AS description,
    parsed_quantity AS quantity,
    CAST(invoicedate AS STRING) AS invoicedate,
    parsed_price AS price,
    TRIM(CAST(customerid AS STRING)) AS customerid,
    CAST(country AS STRING) AS country,
    FROM_UNIXTIME(invoice_timestamp, 'yyyy-MM-dd') AS dt
FROM parsed_source
WHERE invoice_timestamp IS NOT NULL
  AND parsed_quantity IS NOT NULL
  AND parsed_price IS NOT NULL;
