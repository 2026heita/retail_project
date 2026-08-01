-- =====================================================
-- 文件名：29_ads_sales_overview_daily_hive.sql
-- 功能：生成 BI 经营总览日指标
-- 粒度：每个业务日期一行
-- 来源：DWD 有效订单明细
-- =====================================================

CREATE TABLE IF NOT EXISTS ads_sales_overview_daily_hive (
    total_sales DECIMAL(18,2)
        COMMENT '当日有效订单总销售额',

    total_orders BIGINT
        COMMENT '当日去重订单数',

    total_customers BIGINT
        COMMENT '当日去重客户数',

    total_quantity BIGINT
        COMMENT '当日商品销售件数',

    avg_order_value DECIMAL(18,2)
        COMMENT '当日客单价：总销售额/订单数'
)
COMMENT 'BI经营总览日指标表'
PARTITIONED BY (
    dt STRING COMMENT '业务日期，yyyy-MM-dd'
)
STORED AS ORC;


WITH sales_quantity_stat AS (
    SELECT
        CAST(
            COALESCE(SUM(amount), 0)
            AS DECIMAL(18,2)
        ) AS total_sales,

        CAST(
            COALESCE(SUM(quantity), 0)
            AS BIGINT
        ) AS total_quantity

    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
),

order_stat AS (
    SELECT
        COUNT(*) AS total_orders
    FROM (
        SELECT invoice
        FROM dwd_retail_clean_hive
        WHERE dt = '${hiveconf:bizdate}'
          AND invoice IS NOT NULL
        GROUP BY invoice
    ) t
),

customer_stat AS (
    SELECT
        COUNT(*) AS total_customers
    FROM (
        SELECT customerid
        FROM dwd_retail_clean_hive
        WHERE dt = '${hiveconf:bizdate}'
          AND customerid IS NOT NULL
        GROUP BY customerid
    ) t
)

INSERT OVERWRITE TABLE ads_sales_overview_daily_hive
PARTITION (
    dt = '${hiveconf:bizdate}'
)
SELECT
    s.total_sales,
    o.total_orders,
    c.total_customers,
    s.total_quantity,

    CAST(
        CASE
            WHEN o.total_orders = 0 THEN 0
            ELSE s.total_sales / o.total_orders
        END
        AS DECIMAL(18,2)
    ) AS avg_order_value

FROM sales_quantity_stat s
CROSS JOIN order_stat o
CROSS JOIN customer_stat c;