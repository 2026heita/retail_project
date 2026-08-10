-- =====================================================
-- File: 02_load_dwd_retail_clean_all_dates_hive.sql
-- Purpose: Load all canonical ODS business-date partitions into DWD
-- Notes:
--   1. Read all partitions from ods_retail_hive
--   2. Apply exactly the same cleaning rules as the daily DWD loader
--   3. Write DWD partitions dynamically using the source ODS dt
--   4. Use INSERT OVERWRITE for reproducible full canonical loading
-- =====================================================

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;

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
WHERE dt >= '${hiveconf:start_dt}'
  AND dt <= '${hiveconf:end_dt}'
)

INSERT OVERWRITE TABLE dwd_retail_clean_hive
PARTITION (dt)

SELECT
    TRIM(invoice) AS invoice,

    UPPER(TRIM(stockcode)) AS stockcode,

    TRIM(description) AS description,

    quantity,

    FROM_UNIXTIME(
        invoice_ts,
        'yyyy-MM-dd HH:mm:ss'
    ) AS invoicedate,

    CAST(price AS DECIMAL(10,2)) AS price,

    CASE
        WHEN TRIM(CAST(customerid AS STRING))
             RLIKE '^[0-9]+[.]0$'
        THEN REGEXP_REPLACE(
            TRIM(CAST(customerid AS STRING)),
            '[.]0$',
            ''
        )
        ELSE TRIM(CAST(customerid AS STRING))
    END AS customerid,

    TRIM(country) AS country,

    CAST(
        ROUND(quantity * price, 2)
        AS DECIMAL(12,2)
    ) AS amount,

    dt

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
  AND TRIM(dt) <> '';