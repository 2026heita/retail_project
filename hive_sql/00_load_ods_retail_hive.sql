-- =====================================================
-- 文件名: 00_load_ods_retail_hive.sql
-- 功能: 将原始 retail 表数据加载到 ODS 分区表
-- 说明:
-- 原始 InvoiceDate 格式为 yyyy-MM-dd HH:mm:ss，例如 2026-04-08 07:45:00
--   2. 使用 unix_timestamp 解析后转换为 yyyy-MM-dd
--   3. 按 bizdate 写入指定 dt 分区
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
    CAST(CAST(CustomerID AS BIGINT) AS STRING) AS customerid,
    CAST(Country AS STRING) AS country
FROM retail
WHERE from_unixtime(
          unix_timestamp(InvoiceDate, 'yyyy-MM-dd HH:mm:ss'),
          'yyyy-MM-dd'
      ) = '${hiveconf:bizdate}';
