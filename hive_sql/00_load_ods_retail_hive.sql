-- =====================================================
-- 文件名: 00_load_ods_retail_hive.sql
-- 功能: 将原始 retail 表数据加载到 ODS 分区表
-- 说明:
--   1. 兼容两种源时间格式:
--      yyyy-MM-dd HH:mm:ss，例如 2026-04-08 07:45:00
--      d/M/yyyy HH:mm:ss，例如 8/4/2026 07:45:00
--   2. ODS 保留原始 InvoiceDate 字符串，不在 ODS 层改写源值
--   3. 根据解析后的业务日期写入指定 dt 分区
--   4. 使用 INSERT OVERWRITE 保证同一天可重复执行
-- =====================================================

INSERT OVERWRITE TABLE ods_retail_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    CAST(Invoice AS STRING) AS invoice,
    CAST(StockCode AS STRING) AS stockcode,
    CAST(Description AS STRING) AS description,
    CAST(Quantity AS BIGINT) AS quantity,
    CAST(InvoiceDate AS STRING) AS invoicedate,
    CAST(Price AS DECIMAL(10,2)) AS price,
    TRIM(CAST(CustomerID AS STRING)) AS customerid,
    CAST(Country AS STRING) AS country
FROM retail
WHERE FROM_UNIXTIME(
          COALESCE(
              UNIX_TIMESTAMP(
                  TRIM(CAST(InvoiceDate AS STRING)),
                  'yyyy-MM-dd HH:mm:ss'
              ),
              UNIX_TIMESTAMP(
                  TRIM(CAST(InvoiceDate AS STRING)),
                  'd/M/yyyy HH:mm:ss'
              )
          ),
          'yyyy-MM-dd'
      ) = '${hiveconf:bizdate}';
