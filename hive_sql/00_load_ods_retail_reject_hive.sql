-- =====================================================
-- 文件名: 00_load_ods_retail_reject_hive.sql
-- 功能: 将日期为空或日期格式无法解析的记录写入 ODS 异常表
-- 说明:
--   1. 数据来源为 ods_retail_raw_hive，不再直接读取源表 retail
--   2. 当前支持 yyyy-MM-dd H:mm:ss、yyyy-MM-dd H:mm、d/M/yyyy H:mm:ss、d/M/yyyy H:mm 四种日期格式
--   3. 使用 INSERT OVERWRITE，保证同一批次重复执行不会产生重复数据
-- =====================================================

INSERT OVERWRITE TABLE ods_retail_reject_hive
PARTITION (batch_dt = '${hiveconf:bizdate}')
SELECT
    invoice,
    stockcode,
    description,
    quantity,
    invoicedate,
    price,
    customerid,
    country,
    CAST(NULL AS STRING) AS parsed_bizdate,
    CASE
        WHEN invoicedate IS NULL OR TRIM(invoicedate) = ''
            THEN 'EMPTY_INVOICE_DATE'
        ELSE 'DATE_PARSE_FAILED'
    END AS reject_code,
    CASE
        WHEN invoicedate IS NULL OR TRIM(invoicedate) = ''
            THEN 'InvoiceDate为空'
        ELSE 'InvoiceDate不符合支持的日期格式'
    END AS reject_reason
FROM ods_retail_raw_hive
WHERE batch_dt = '${hiveconf:bizdate}'
  AND (
        invoicedate IS NULL
        OR TRIM(invoicedate) = ''
        OR COALESCE(
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
           ) IS NULL
      );
