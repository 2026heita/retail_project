-- =====================================================
-- 文件名: 00_load_ods_retail_hive.sql
-- 功能: 从 ODS Raw 原始落地表加载指定业务日期的数据
-- 说明:
--   1. 不再直接读取源表 retail
--   2. 数据统一从 ods_retail_raw_hive 进入正常 ODS 链路
--   3. 日期解析兼容 yyyy-MM-dd HH:mm:ss 和 d/M/yyyy HH:mm:ss
--   4. 日期为空或解析失败的数据不会进入正常 ODS
--   5. 异常日期数据由 ods_retail_reject_hive 保存
--   6. 使用 INSERT OVERWRITE 保证同一业务日期重复执行结果一致
-- =====================================================

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
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'yyyy-MM-dd HH:mm:ss'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'd/M/yyyy HH:mm:ss'
            )
        ) AS invoice_timestamp
    FROM ods_retail_raw_hive
    WHERE batch_dt = '${hiveconf:bizdate}'
)

INSERT OVERWRITE TABLE ods_retail_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    CAST(invoice AS STRING) AS invoice,
    CAST(stockcode AS STRING) AS stockcode,
    CAST(description AS STRING) AS description,
    CAST(quantity AS BIGINT) AS quantity,
    CAST(invoicedate AS STRING) AS invoicedate,
    CAST(price AS DECIMAL(10,2)) AS price,
    TRIM(CAST(customerid AS STRING)) AS customerid,
    CAST(country AS STRING) AS country
FROM parsed_source
WHERE invoice_timestamp IS NOT NULL
  AND FROM_UNIXTIME(
          invoice_timestamp,
          'yyyy-MM-dd'
      ) = '${hiveconf:bizdate}';
