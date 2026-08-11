-- =====================================================
-- 文件名：29_ads_sales_overview_daily_hive.sql
-- 功能：生成 BI 经营总览日指标（范围式动态分区）
-- 粒度：每个真实业务日期一行
-- 来源：DWD 有效订单明细
-- 参数：
--   hiveconf:start_dt  范围起始日期（含）
--   hiveconf:end_dt    范围结束日期（含）
-- 用法示例：
--   hive --database retail_canonical \
--       --hiveconf start_dt=2009-12-01 \
--       --hiveconf end_dt=2011-12-09 \
--       -f 29_ads_sales_overview_daily_hive.sql
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


SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=2000;
SET hive.exec.max.dynamic.partitions.pernode=2000;
SET hive.exec.max.created.files=100000;


WITH sales_quantity_stat AS (
    SELECT
        dt,

        CAST(
            COALESCE(SUM(amount), 0)
            AS DECIMAL(18,2)
        ) AS total_sales,

        CAST(
            COALESCE(SUM(quantity), 0)
            AS BIGINT
        ) AS total_quantity

    FROM dwd_retail_clean_hive
    WHERE dt BETWEEN '${hiveconf:start_dt}' AND '${hiveconf:end_dt}'
    GROUP BY dt
),

order_stat AS (
    SELECT
        dt,
        COUNT(*) AS total_orders
    FROM (
        SELECT
            dt,
            invoice
        FROM dwd_retail_clean_hive
        WHERE dt BETWEEN '${hiveconf:start_dt}' AND '${hiveconf:end_dt}'
          AND invoice IS NOT NULL
        GROUP BY
            dt,
            invoice
    ) t
    GROUP BY dt
),

customer_stat AS (
    SELECT
        dt,
        COUNT(*) AS total_customers
    FROM (
        SELECT
            dt,
            customerid
        FROM dwd_retail_clean_hive
        WHERE dt BETWEEN '${hiveconf:start_dt}' AND '${hiveconf:end_dt}'
          AND customerid IS NOT NULL
        GROUP BY
            dt,
            customerid
    ) t
    GROUP BY dt
)

INSERT OVERWRITE TABLE ads_sales_overview_daily_hive
PARTITION (dt)
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
    ) AS avg_order_value,

    s.dt

FROM sales_quantity_stat s
JOIN order_stat o
    ON s.dt = o.dt
JOIN customer_stat c
    ON s.dt = c.dt;
