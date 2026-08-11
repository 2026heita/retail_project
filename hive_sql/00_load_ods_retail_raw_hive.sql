-- =====================================================
-- 文件名: 00_load_ods_retail_raw_hive.sql
-- 功能: 将 Hive 源表 retail 完整落地到 ODS_RAW
-- 说明:
--   1. 不执行 WHERE 过滤
--   2. 不执行数值类型转换
--   3. 使用 INSERT OVERWRITE 保证同一批次重复执行结果一致
--   4. 批次号使用 batch_dt（默认等于 bizdate），与业务日期解耦
-- =====================================================

INSERT OVERWRITE TABLE ods_retail_raw_hive
PARTITION (batch_dt = '${hiveconf:batch_dt}')
SELECT
    CAST(Invoice AS STRING) AS invoice,
    CAST(StockCode AS STRING) AS stockcode,
    CAST(Description AS STRING) AS description,
    CAST(Quantity AS STRING) AS quantity,
    CAST(InvoiceDate AS STRING) AS invoicedate,
    CAST(Price AS STRING) AS price,
    CAST(CustomerID AS STRING) AS customerid,
    CAST(Country AS STRING) AS country
FROM retail;