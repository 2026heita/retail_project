-- =====================================================
-- 文件名：34_ads_sales_anomaly_daily_hive.sql
-- 功能：零售经营异常检测日结果 ADS
-- 粒度：每个真实业务日期一行
-- =====================================================

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=1000;
SET hive.exec.max.dynamic.partitions.pernode=1000;

DROP TABLE IF EXISTS ads_sales_anomaly_daily_hive;

CREATE TABLE ads_sales_anomaly_daily_hive (
    total_sales DECIMAL(18,2),
    total_orders BIGINT,
    total_customers BIGINT,
    total_quantity BIGINT,
    avg_order_value DECIMAL(18,2),

    prev_dt STRING,
    prev_sales DECIMAL(18,2),

    sales_change_pct DECIMAL(18,2),
    sales_loss_amount DECIMAL(18,2),

    orders_change_pct DECIMAL(18,2),
    customers_change_pct DECIMAL(18,2),
    quantity_change_pct DECIMAL(18,2),
    aov_change_pct DECIMAL(18,2),

    anomaly_level STRING,
    primary_driver STRING
)
COMMENT '零售经营异常检测日结果 ADS'
PARTITIONED BY (
    dt STRING COMMENT '业务日期，yyyy-MM-dd'
)
STORED AS ORC;

WITH base AS (
    SELECT
        dt,
        total_sales,
        total_orders,
        total_customers,
        total_quantity,
        avg_order_value,

        LAG(dt, 1) OVER (ORDER BY dt) AS prev_dt,
        LAG(total_sales, 1) OVER (ORDER BY dt) AS prev_sales,
        LAG(total_orders, 1) OVER (ORDER BY dt) AS prev_orders,
        LAG(total_customers, 1) OVER (ORDER BY dt) AS prev_customers,
        LAG(total_quantity, 1) OVER (ORDER BY dt) AS prev_quantity

    FROM ads_sales_overview_daily_hive
),

calc AS (
    SELECT
        dt,
        total_sales,
        total_orders,
        total_customers,
        total_quantity,
        avg_order_value,

        prev_dt,
        prev_sales,
        prev_orders,
        prev_customers,
        prev_quantity,

        CASE
            WHEN prev_sales IS NULL OR prev_sales = 0
            THEN NULL
            ELSE
                (total_sales - prev_sales)
                / prev_sales * 100
        END AS sales_change_pct_raw,

        CASE
            WHEN prev_sales IS NULL
            THEN NULL
            ELSE prev_sales - total_sales
        END AS sales_loss_amount_raw,

        CASE
            WHEN prev_orders IS NULL OR prev_orders = 0
            THEN NULL
            ELSE
                (total_orders - prev_orders)
                / CAST(prev_orders AS DECIMAL(18,6)) * 100
        END AS orders_change_pct_raw,

        CASE
            WHEN prev_customers IS NULL OR prev_customers = 0
            THEN NULL
            ELSE
                (total_customers - prev_customers)
                / CAST(prev_customers AS DECIMAL(18,6)) * 100
        END AS customers_change_pct_raw,

        CASE
            WHEN prev_quantity IS NULL OR prev_quantity = 0
            THEN NULL
            ELSE
                (total_quantity - prev_quantity)
                / CAST(prev_quantity AS DECIMAL(18,6)) * 100
        END AS quantity_change_pct_raw,

        CASE
            WHEN prev_orders IS NULL
              OR prev_orders = 0
            THEN NULL
            ELSE
                (
                    (
                        total_sales
                        / CAST(total_orders AS DECIMAL(18,6))
                    )
                    -
                    (
                        prev_sales
                        / CAST(prev_orders AS DECIMAL(18,6))
                    )
                )
                /
                (
                    prev_sales
                    / CAST(prev_orders AS DECIMAL(18,6))
                )
                * 100
        END AS aov_change_pct_raw

    FROM base
)

INSERT OVERWRITE TABLE ads_sales_anomaly_daily_hive
PARTITION (dt)

SELECT
    total_sales,
    total_orders,
    total_customers,
    total_quantity,
    avg_order_value,

    prev_dt,
    prev_sales,

    CAST(sales_change_pct_raw AS DECIMAL(18,2)),
    CAST(sales_loss_amount_raw AS DECIMAL(18,2)),

    CAST(orders_change_pct_raw AS DECIMAL(18,2)),
    CAST(customers_change_pct_raw AS DECIMAL(18,2)),
    CAST(quantity_change_pct_raw AS DECIMAL(18,2)),
    CAST(aov_change_pct_raw AS DECIMAL(18,2)),

    CASE
        WHEN prev_dt IS NULL
            THEN 'NOT_EVALUATED'

        WHEN sales_change_pct_raw <= -50
         AND sales_loss_amount_raw >= 30000
         AND (
                orders_change_pct_raw <= -40
                OR customers_change_pct_raw <= -40
                OR quantity_change_pct_raw <= -40
                OR aov_change_pct_raw <= -40
             )
            THEN 'HIGH'

        WHEN sales_change_pct_raw <= -40
         AND sales_loss_amount_raw >= 20000
            THEN 'MEDIUM'

        ELSE 'NORMAL'
    END AS anomaly_level,

        CASE
        WHEN prev_dt IS NULL THEN NULL

        WHEN orders_change_pct_raw <= aov_change_pct_raw
            THEN 'ORDERS'

        WHEN aov_change_pct_raw < orders_change_pct_raw
            THEN 'AVG_ORDER_VALUE'

        ELSE NULL
    END AS primary_driver,

    dt

FROM calc;