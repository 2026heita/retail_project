-- =====================================================
-- 文件名: 04_dws_sales_summary_hive.sql
-- 功能: 生成 DWS 国家销售汇总表
-- 优化: country 倾斜处理，两阶段聚合 + 安全 CAST
-- =====================================================

CREATE TABLE IF NOT EXISTS dws_sales_summary_hive (
    country STRING COMMENT '国家',
    total_orders BIGINT COMMENT '订单数',
    total_customers BIGINT COMMENT '客户数',
    total_sales DECIMAL(14,2) COMMENT '销售总额',
    avg_order_value DECIMAL(14,2) COMMENT '平均订单金额'
)
COMMENT 'DWS 国家销售汇总表'
PARTITIONED BY (dt STRING COMMENT '业务日期')
STORED AS ORC;


SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.groupby.skewindata=false;

WITH base AS (
    SELECT
        country,
        invoice,
        customerid,
        CAST(COALESCE(quantity,0) * COALESCE(price,0) AS DECIMAL(14,2)) AS amount
    FROM dwd_retail_clean_hive
    WHERE dt='${hiveconf:bizdate}'
),

-- 1. 对严重倾斜的 United Kingdom 做确定性 salt
--    使用 CRC32 基于稳定业务字段生成盐值，保证同一记录每次执行得到相同盐值
sales_salted AS (
    SELECT
        country,
        CASE
            WHEN country = 'United Kingdom'
            THEN PMOD(
                CRC32(
                    CONCAT_WS('#|#',
                        COALESCE(invoice, ''),
                        COALESCE(stockcode, ''),
                        COALESCE(customerid, ''),
                        COALESCE(invoicedate, '')
                    )
                ),
                20
            )
            ELSE 0
        END AS salt_key,
        amount
    FROM base
),

-- 2. 阶段1聚合
sales_stage1 AS (
    SELECT
        country,
        salt_key,
        SUM(amount) AS partial_sales
    FROM sales_salted
    GROUP BY country, salt_key
),

-- 3. 阶段2汇总回 country
sales_final AS (
    SELECT
        country,
        CAST(SUM(partial_sales) AS DECIMAL(14,2)) AS total_sales
    FROM sales_stage1
    GROUP BY country
),

-- 4. 订单数：按 country+invoice 去重
order_final AS (
    SELECT
        country,
        COUNT(*) AS total_orders
    FROM (
        SELECT country, invoice
        FROM base
        GROUP BY country, invoice
    ) t
    GROUP BY country
),

-- 5. 客户数：按 country+customerid 去重
customer_final AS (
    SELECT
        country,
        COUNT(*) AS total_customers
    FROM (
        SELECT country, customerid
        FROM base
        GROUP BY country, customerid
    ) t
    GROUP BY country
)

-- 6. 最终插入 DWS 表
INSERT OVERWRITE TABLE dws_sales_summary_hive
PARTITION (dt='${hiveconf:bizdate}')
SELECT
    s.country,
    o.total_orders,
    c.total_customers,
    s.total_sales,
    CAST(
        CASE
            WHEN o.total_orders = 0 THEN 0
            ELSE s.total_sales / o.total_orders
        END AS DECIMAL(14,2)
    ) AS avg_order_value
FROM sales_final s
LEFT JOIN order_final o
    ON s.country = o.country
LEFT JOIN customer_final c
    ON s.country = c.country;