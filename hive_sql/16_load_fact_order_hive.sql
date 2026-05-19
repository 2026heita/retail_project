-- =====================================================
-- 文件名: 16_load_fact_order_hive.sql
-- 功能: 加载星型模型订单事实表
-- 说明:
--   1. 从 DWD 当前 dt 分区读取订单明细
--   2. 关联用户、商品、日期、地理维度当前 dt 快照
--   3. 使用 INSERT OVERWRITE 覆盖当前 dt 分区，保证任务幂等
--   4. order_line_id 增加 duplicate_seq，降低完全相同订单明细导致代理键重复的风险
-- =====================================================

WITH dwd_parsed AS (
    SELECT
        invoice,
        customerid,
        country,
        stockcode,
        quantity,
        amount,
        CAST(
            FROM_UNIXTIME(
                UNIX_TIMESTAMP(invoicedate, 'd/M/yyyy HH:mm:ss'),
                'yyyy-MM-dd'
            ) AS DATE
        ) AS invoice_date
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
),
dwd_base AS (
    SELECT
        invoice,
        customerid,
        country,
        stockcode,
        quantity,
        amount,
        invoice_date,
        ROW_NUMBER() OVER (
            PARTITION BY
                invoice,
                customerid,
                country,
                stockcode,
                invoice_date,
                quantity,
                amount
            ORDER BY
                invoice,
                stockcode,
                customerid,
                country
        ) AS duplicate_seq
    FROM dwd_parsed
    WHERE invoice_date IS NOT NULL
)

INSERT OVERWRITE TABLE fact_order
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    md5(CONCAT(
        COALESCE(b.invoice, ''), '|',
        COALESCE(b.customerid, ''), '|',
        COALESCE(b.country, ''), '|',
        COALESCE(b.stockcode, ''), '|',
        COALESCE(CAST(b.invoice_date AS STRING), ''), '|',
        COALESCE(CAST(b.quantity AS STRING), ''), '|',
        COALESCE(CAST(b.amount AS STRING), ''), '|',
        COALESCE(CAST(b.duplicate_seq AS STRING), '')
    )) AS order_line_id,
    b.invoice AS order_id,
    u.user_id,
    p.product_id,
    d.date_id,
    g.geo_id,
    b.quantity,
    CAST(b.amount AS DECIMAL(12,2)) AS amount
FROM dwd_base b
JOIN dim_user u
  ON b.customerid = u.customerid
 AND b.country = u.country
 AND u.dt = '${hiveconf:bizdate}'
 AND u.is_current = TRUE
JOIN dim_product p
  ON b.stockcode = p.stockcode
 AND p.dt = '${hiveconf:bizdate}'
JOIN dim_date d
  ON b.invoice_date = d.date_id
 AND d.dt = '${hiveconf:bizdate}'
JOIN dim_geo g
  ON b.country = g.country
 AND g.dt = '${hiveconf:bizdate}';
