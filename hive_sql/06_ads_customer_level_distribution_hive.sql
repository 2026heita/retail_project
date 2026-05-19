-- =====================================================
-- 文件名: 06_ads_customer_level_distribution_hive.sql
-- 功能: 生成 ADS 客户价值分层分布表
-- =====================================================

CREATE TABLE IF NOT EXISTS ads_customer_level_distribution_hive (
    customer_level STRING,
    customer_cnt BIGINT,
    total_spent DECIMAL(14,2),
    customer_cnt_pct DECIMAL(10,2),
    sales_pct DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

WITH level_stats AS (
    SELECT
        customer_level,
        COUNT(DISTINCT customerid) AS customer_cnt,
        CAST(ROUND(COALESCE(SUM(total_spent), 0), 2) AS DECIMAL(14,2)) AS total_spent
    FROM dws_customer_value_hive
    WHERE dt = '${hiveconf:bizdate}'
    GROUP BY customer_level
),

total_stats AS (
    SELECT
        COUNT(DISTINCT customerid) AS total_customer_cnt,
        CAST(ROUND(COALESCE(SUM(total_spent), 0), 2) AS DECIMAL(14,2)) AS total_sales
    FROM dws_customer_value_hive
    WHERE dt = '${hiveconf:bizdate}'
)

INSERT OVERWRITE TABLE ads_customer_level_distribution_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    level_stats.customer_level,
    level_stats.customer_cnt,
    level_stats.total_spent,

    CAST(
        ROUND(
            CASE
                WHEN total_stats.total_customer_cnt = 0 THEN 0
                ELSE level_stats.customer_cnt / total_stats.total_customer_cnt * 100
            END,
            2
        ) AS DECIMAL(10,2)
    ) AS customer_cnt_pct,

    CAST(
        ROUND(
            CASE
                WHEN total_stats.total_sales IS NULL OR total_stats.total_sales = 0 THEN 0
                ELSE level_stats.total_spent / total_stats.total_sales * 100
            END,
            2
        ) AS DECIMAL(10,2)
    ) AS sales_pct

FROM level_stats
CROSS JOIN total_stats;
