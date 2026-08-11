-- =====================================================
-- File: 00_load_ods_retail_reject_hive.sql
-- Purpose: Write technically invalid records to ODS Reject table
-- Description:
--   1. Source: ods_retail_raw_hive (STRING columns)
--   2. A Raw record enters Reject if ANY of these fails:
--      - InvoiceDate parsing (4 formats)
--      - quantity -> BIGINT
--      - price -> DECIMAL(10,2)
--   3. Single priority per record (one Raw -> at most one Reject):
--      Priority 1: EMPTY_INVOICE_DATE
--      Priority 2: DATE_PARSE_FAILED
--      Priority 3: EMPTY_QUANTITY
--      Priority 4: QUANTITY_PARSE_FAILED
--      Priority 5: EMPTY_PRICE
--      Priority 6: PRICE_PARSE_FAILED
--   4. parsed_bizdate: parsed date if possible, else NULL
--   5. Uses batch_dt for partition, decoupled from bizdate
-- =====================================================

WITH parsed_raw AS (
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

INSERT OVERWRITE TABLE ods_retail_reject_hive
PARTITION (batch_dt = '${hiveconf:batch_dt}')
SELECT
    invoice,
    stockcode,
    description,
    quantity,
    invoicedate,
    price,
    customerid,
    country,
    CASE
        WHEN invoice_timestamp IS NOT NULL
        THEN FROM_UNIXTIME(invoice_timestamp, 'yyyy-MM-dd')
        ELSE NULL
    END AS parsed_bizdate,
    CASE
        WHEN TRIM(CAST(invoicedate AS STRING)) IS NULL
          OR TRIM(CAST(invoicedate AS STRING)) = ''
            THEN 'EMPTY_INVOICE_DATE'
        WHEN invoice_timestamp IS NULL
            THEN 'DATE_PARSE_FAILED'
        WHEN TRIM(CAST(quantity AS STRING)) IS NULL
          OR TRIM(CAST(quantity AS STRING)) = ''
            THEN 'EMPTY_QUANTITY'
        WHEN parsed_quantity IS NULL
            THEN 'QUANTITY_PARSE_FAILED'
        WHEN TRIM(CAST(price AS STRING)) IS NULL
          OR TRIM(CAST(price AS STRING)) = ''
            THEN 'EMPTY_PRICE'
        WHEN parsed_price IS NULL
            THEN 'PRICE_PARSE_FAILED'
    END AS reject_code,
    CASE
        WHEN TRIM(CAST(invoicedate AS STRING)) IS NULL
          OR TRIM(CAST(invoicedate AS STRING)) = ''
            THEN 'InvoiceDate为空'
        WHEN invoice_timestamp IS NULL
            THEN 'InvoiceDate格式无法解析为支持的四种日期格式'
        WHEN TRIM(CAST(quantity AS STRING)) IS NULL
          OR TRIM(CAST(quantity AS STRING)) = ''
            THEN 'quantity为空'
        WHEN parsed_quantity IS NULL
            THEN 'quantity无法转换为整数'
        WHEN TRIM(CAST(price AS STRING)) IS NULL
          OR TRIM(CAST(price AS STRING)) = ''
            THEN 'price为空'
        WHEN parsed_price IS NULL
            THEN 'price无法转换为DECIMAL(10,2)'
    END AS reject_reason
FROM parsed_raw
WHERE invoice_timestamp IS NULL
   OR parsed_quantity IS NULL
   OR parsed_price IS NULL;
