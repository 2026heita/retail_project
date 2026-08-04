-- =====================================================
-- 文件名: 02_load_dwd_retail_clean_hive.sql
-- 功能: 从 ODS 分区表加载零售订单数据到 DWD 清洗表
-- 说明:
--   1. 只处理当前 bizdate 对应的 ODS 分区
--   2. 过滤无效数量、无效价格、空客户 ID、退货订单和不可解析时间
--   3. ODS 保留源时间，DWD 将时间统一为 yyyy-MM-dd HH:mm:ss
--   4. 使用 INSERT OVERWRITE 保证同一天可重复执行
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

        COALESCE(
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'yyyy-MM-dd HH:mm:ss'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'd/M/yyyy HH:mm:ss'
            )
        ) AS invoice_ts

    FROM ods_retail_hive
    WHERE dt = '${hiveconf:bizdate}'
)

INSERT OVERWRITE TABLE dwd_retail_clean_hive
PARTITION (dt = '${hiveconf:bizdate}')
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
    -- Normalize CustomerID: strip trailing ".0" from pure-numeric IDs,
    -- preserve original value for non-numeric IDs.
    CASE
        WHEN CAST(customerid AS STRING) RLIKE '^[0-9]+\\.0$'
        THEN REGEXP_REPLACE(CAST(customerid AS STRING), '\\.0$', '')
        ELSE CAST(customerid AS STRING)
    END AS customerid,
    TRIM(country) AS country,
    CAST(ROUND(quantity * price, 2) AS DECIMAL(12,2)) AS amount

FROM ods_parsed
WHERE quantity > 0
  AND price > 0
  AND customerid IS NOT NULL
  AND TRIM(customerid) <> ''
  AND invoice IS NOT NULL
  AND TRIM(invoice) <> ''
  AND UPPER(TRIM(invoice)) NOT LIKE 'C%'
  AND stockcode IS NOT NULL
  AND TRIM(stockcode) <> ''
  AND country IS NOT NULL
  AND TRIM(country) <> ''
  AND invoicedate IS NOT NULL
  AND TRIM(invoicedate) <> ''
  AND invoice_ts IS NOT NULL;
