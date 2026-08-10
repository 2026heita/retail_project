-- =====================================================
-- 文件名: 16_load_fact_order_hive.sql
-- 功能: 加载星型模型订单事实表
-- 说明:
--   1. 从 DWD 当前 dt 分区读取订单明细
--   2. date_id 使用 canonical 分区日期 dt（已通过全量质量门禁）
--   3. invoicedate 仍是原始交易时间字段但不承担日期键解析
--   4. 用户维度按 customerid + 业务日期关联对应的 SCD2 历史版本
--   5. 商品、日期、地理维度关联当前 dt 快照
--   6. 使用 INSERT OVERWRITE 覆盖当前 dt 分区，保证任务幂等
--   7. order_line_id 增加 duplicate_seq，降低完全相同明细代理键重复风险
-- =====================================================

WITH dwd_base AS (
    SELECT
        invoice,
        customerid,
        country,
        stockcode,
        quantity,
        amount,
        CAST(dt AS DATE) AS invoice_date,

        ROW_NUMBER() OVER (
            PARTITION BY
                invoice,
                customerid,
                country,
                stockcode,
                CAST(dt AS DATE),
                quantity,
                amount
            ORDER BY
                invoice,
                stockcode,
                customerid,
                country
        ) AS duplicate_seq

    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
)

INSERT OVERWRITE TABLE fact_order
PARTITION (dt = '${hiveconf:bizdate}')

SELECT
    MD5(
        CONCAT(
            COALESCE(b.invoice, ''), '|',
            COALESCE(b.customerid, ''), '|',
            COALESCE(b.country, ''), '|',
            COALESCE(b.stockcode, ''), '|',
            COALESCE(CAST(b.invoice_date AS STRING), ''), '|',
            COALESCE(CAST(b.quantity AS STRING), ''), '|',
            COALESCE(CAST(b.amount AS STRING), ''), '|',
            COALESCE(CAST(b.duplicate_seq AS STRING), '')
        )
    ) AS order_line_id,

    b.invoice AS order_id,
    u.user_id,
    p.product_id,
    d.date_id,
    g.geo_id,
    b.quantity,
    CAST(b.amount AS DECIMAL(12,2)) AS amount

FROM dwd_base b

-- SCD2 关联不能只取 is_current=true；
-- 必须根据事实发生日期命中当时有效的用户版本。
JOIN dim_user u
  ON b.customerid = u.customerid
 AND b.invoice_date >= u.start_date
 AND b.invoice_date <= u.end_date
 AND u.dt = '${hiveconf:bizdate}'

JOIN dim_product p
  ON b.stockcode = p.stockcode
 AND p.dt = '${hiveconf:bizdate}'

JOIN dim_date d
  ON b.invoice_date = d.date_id
 AND d.dt = '${hiveconf:bizdate}'

JOIN dim_geo g
  ON b.country = g.country
 AND g.dt = '${hiveconf:bizdate}';
