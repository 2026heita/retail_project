-- =====================================================
-- 文件名: 10_check_ods_retail_hive.sql
-- 功能: ODS 层数据入仓校验
-- 说明:
--   1. 校验指定 bizdate 的 ODS 分区是否有数据
--   2. 校验核心字段空值、异常值、日期解析失败
--   3. 日期解析兼容 yyyy-MM-dd HH:mm:ss 和 d/M/yyyy HH:mm:ss
--   4. 为后续 DWD 标准化事实层提供依据
-- 执行:
--   hive --hiveconf bizdate=2026-04-08 -f hive_sql/10_check_ods_retail_hive.sql
-- =====================================================

-- 1. ODS 分区数据量总览
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    COUNT(*) AS ods_row_cnt,
    COUNT(DISTINCT invoice) AS invoice_cnt,
    COUNT(DISTINCT customerid) AS customer_cnt,
    COUNT(DISTINCT stockcode) AS product_cnt,
    COUNT(DISTINCT country) AS country_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}';


-- 2. 核心字段空值检查
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    SUM(CASE WHEN invoice IS NULL OR TRIM(invoice) = '' THEN 1 ELSE 0 END) AS null_invoice_cnt,
    SUM(CASE WHEN stockcode IS NULL OR TRIM(stockcode) = '' THEN 1 ELSE 0 END) AS null_stockcode_cnt,
    SUM(CASE WHEN description IS NULL OR TRIM(description) = '' THEN 1 ELSE 0 END) AS null_description_cnt,
    SUM(CASE WHEN customerid IS NULL OR TRIM(customerid) = '' THEN 1 ELSE 0 END) AS null_customer_cnt,
    SUM(CASE WHEN country IS NULL OR TRIM(country) = '' THEN 1 ELSE 0 END) AS null_country_cnt,
    SUM(CASE WHEN invoicedate IS NULL OR TRIM(invoicedate) = '' THEN 1 ELSE 0 END) AS null_invoicedate_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}';


-- 3. 数值异常检查
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    SUM(CASE WHEN quantity IS NULL THEN 1 ELSE 0 END) AS null_quantity_cnt,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS null_price_cnt,
    SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END) AS invalid_quantity_cnt,
    SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END) AS invalid_price_cnt,
    SUM(CASE WHEN quantity * price <= 0 THEN 1 ELSE 0 END) AS invalid_amount_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}';


-- 4. 退货订单检查：Invoice 以 C 开头通常代表取消/退货
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    COUNT(*) AS return_order_row_cnt,
    COUNT(DISTINCT invoice) AS return_invoice_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}'
  AND UPPER(TRIM(invoice)) LIKE 'C%';


-- 5. 日期解析失败检查：兼容两种源格式
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    COUNT(*) AS parse_failed_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}'
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
                   'd/M/yyyy HH:mm:ss'
               )
           ) IS NULL
      );


-- 6. 查看样例数据，确认字段是否长得正常
SELECT
    invoice,
    stockcode,
    description,
    quantity,
    invoicedate,
    price,
    customerid,
    country,
    dt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}'
LIMIT 20;
