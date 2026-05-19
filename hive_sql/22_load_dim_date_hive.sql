-- =====================================================
-- 文件名: 22_load_dim_date_hive.sql
-- 功能: 加载星型模型日期维度快照
-- 说明:
--   1. 从 dwd_retail_clean_hive 当前 dt 分区解析订单日期
--   2. 保证 fact_order 关联 dim_date 时 date_id 可匹配
--   3. 使用 INSERT OVERWRITE 覆盖当前 dt 分区，保证任务幂等
-- =====================================================

INSERT OVERWRITE TABLE dim_date
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    invoice_date AS date_id,
    CAST(invoice_date AS STRING) AS date_str,
    YEAR(invoice_date) AS year_num,
    MONTH(invoice_date) AS month_num,
    DAYOFMONTH(invoice_date) AS day_num,
    CAST(CEIL(MONTH(invoice_date) / 3.0) AS INT) AS quarter_num,
    WEEKOFYEAR(invoice_date) AS weekofyear_num,
    CASE
        WHEN PMOD(DATEDIFF(invoice_date, '1970-01-04'), 7) IN (0, 6)
        THEN TRUE
        ELSE FALSE
    END AS is_weekend
FROM (
    SELECT DISTINCT
        CAST(
            FROM_UNIXTIME(
                UNIX_TIMESTAMP(invoicedate, 'd/M/yyyy HH:mm:ss'),
                'yyyy-MM-dd'
            ) AS DATE
        ) AS invoice_date
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND invoicedate IS NOT NULL
      AND UNIX_TIMESTAMP(invoicedate, 'd/M/yyyy HH:mm:ss') IS NOT NULL
) t
WHERE invoice_date IS NOT NULL;
