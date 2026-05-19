-- =====================================================
-- 文件名: 02_load_dwd_retail_clean_hive.sql
-- 功能: 从 ODS 分区表加载零售订单数据到 DWD 清洗表
-- 说明:
--   1. 只处理当前 bizdate 对应的 ODS 分区
--   2. 过滤无效数量、无效价格、空客户 ID 和退货订单
--   3. 使用 INSERT OVERWRITE 保证同一天可重复执行
-- =====================================================

INSERT OVERWRITE TABLE dwd_retail_clean_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    invoice,
    stockcode,
    description,
    quantity,
    invoicedate,
    CAST(price AS DECIMAL(10,2)) AS price,
    CAST(customerid AS STRING) AS customerid,
    country,
    CAST(ROUND(quantity * price, 2) AS DECIMAL(12,2)) AS amount
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}'
  AND quantity > 0
  AND price > 0
  AND customerid IS NOT NULL
  AND TRIM(customerid) <> ''
  AND invoice IS NOT NULL
  AND UPPER(TRIM(invoice)) NOT LIKE 'C%';
  AND TRIM(invoice) <> ''
  AND stockcode IS NOT NULL AND TRIM(stockcode) <> ''
  AND country IS NOT NULL AND TRIM(country) <> ''
  AND invoicedate IS NOT NULL AND TRIM(invoicedate) <> ''
