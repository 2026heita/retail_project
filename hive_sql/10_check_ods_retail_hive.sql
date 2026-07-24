-- =====================================================
-- 文件名: 10_check_ods_retail_hive.sql
-- 功能: ODS 层数据内容质量检查
-- 说明:
--   1. 检查指定 bizdate 的正常 ODS 分区数据概况
--   2. 检查核心字段空值和数值异常
--   3. 统计取消/退货订单，不将其直接视为技术异常
--   4. 日期解析异常直接从 ods_retail_reject_hive 统计
--   5. 本文件用于质量分析和告警，不承担入仓完整性阻断
--   6. 入仓完整性门禁由 10_check_ods_ingestion_hive.sql 负责
-- 执行:
--   hive --hiveconf bizdate=2026-04-08 \
--     -f /home/admin/retail_hive_project/hive/10_check_ods_retail_hive.sql
-- =====================================================


-- 1. 正常 ODS 分区数据量总览
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
    COALESCE(SUM(CASE WHEN invoice IS NULL OR TRIM(invoice) = '' THEN 1 ELSE 0 END), 0) AS null_invoice_cnt,
    COALESCE(SUM(CASE WHEN stockcode IS NULL OR TRIM(stockcode) = '' THEN 1 ELSE 0 END), 0) AS null_stockcode_cnt,
    COALESCE(SUM(CASE WHEN description IS NULL OR TRIM(description) = '' THEN 1 ELSE 0 END), 0) AS null_description_cnt,
    COALESCE(SUM(CASE WHEN customerid IS NULL OR TRIM(customerid) = '' THEN 1 ELSE 0 END), 0) AS null_customer_cnt,
    COALESCE(SUM(CASE WHEN country IS NULL OR TRIM(country) = '' THEN 1 ELSE 0 END), 0) AS null_country_cnt,
    COALESCE(SUM(CASE WHEN invoicedate IS NULL OR TRIM(invoicedate) = '' THEN 1 ELSE 0 END), 0) AS null_invoicedate_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}';


-- 3. 数值异常检查
-- quantity <= 0 可能包含退货数据，因此这里只统计，不直接阻断任务
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    COALESCE(SUM(CASE WHEN quantity IS NULL THEN 1 ELSE 0 END), 0) AS null_quantity_cnt,
    COALESCE(SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END), 0) AS null_price_cnt,
    COALESCE(SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END), 0) AS non_positive_quantity_cnt,
    COALESCE(SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END), 0) AS non_positive_price_cnt,
    COALESCE(
        SUM(
            CASE
                WHEN quantity IS NOT NULL
                 AND price IS NOT NULL
                 AND quantity * price <= 0
                THEN 1 ELSE 0
            END
        ),
        0
    ) AS non_positive_amount_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}';


-- 4. 取消/退货订单检查
-- Invoice 以 C 开头通常代表取消或退货订单
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    COUNT(*) AS return_order_row_cnt,
    COUNT(DISTINCT invoice) AS return_invoice_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}'
  AND UPPER(TRIM(invoice)) LIKE 'C%';


-- 5. Reject 异常数据总量
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    COUNT(*) AS reject_row_cnt
FROM ods_retail_reject_hive
WHERE batch_dt = '${hiveconf:bizdate}';


-- 6. Reject 异常数据分类统计
SELECT
    '${hiveconf:bizdate}' AS bizdate,
    reject_code,
    reject_reason,
    COUNT(*) AS reject_cnt
FROM ods_retail_reject_hive
WHERE batch_dt = '${hiveconf:bizdate}'
GROUP BY
    reject_code,
    reject_reason
ORDER BY
    reject_cnt DESC,
    reject_code;


-- 7. 正常 ODS 样例数据
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


-- 8. Reject 样例数据
SELECT
    invoice,
    stockcode,
    description,
    quantity,
    invoicedate,
    price,
    customerid,
    country,
    parsed_bizdate,
    reject_code,
    reject_reason,
    batch_dt
FROM ods_retail_reject_hive
WHERE batch_dt = '${hiveconf:bizdate}'
LIMIT 20;
