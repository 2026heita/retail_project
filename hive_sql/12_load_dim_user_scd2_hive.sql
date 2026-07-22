-- =====================================================
-- 文件名: 12_load_dim_user_scd2_hive.sql
-- 功能: 加载每日完整快照式 SCD2 用户维度
-- 兼容性:
--   1. 避免 JOIN + LATERAL VIEW STACK + UNION ALL 组合
--   2. 使用临时表物化当天用户和上一快照，降低 CTE 重复展开
--   3. 适配 Hive 3.1.3 + MapReduce 执行环境
-- =====================================================

DROP TABLE IF EXISTS tmp_dim_user_today;
DROP TABLE IF EXISTS tmp_dim_user_prev_all;
DROP TABLE IF EXISTS tmp_dim_user_prev_current;

CREATE TEMPORARY TABLE tmp_dim_user_today
STORED AS ORC
AS
SELECT
    customerid,
    country
FROM (
    SELECT
        customerid,
        country,
        ROW_NUMBER() OVER (
            PARTITION BY customerid
            ORDER BY
                UNIX_TIMESTAMP(
                    invoicedate,
                    'yyyy-MM-dd HH:mm:ss'
                ) DESC,
                country
        ) AS rn
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND customerid IS NOT NULL
      AND TRIM(customerid) <> ''
      AND country IS NOT NULL
      AND TRIM(country) <> ''
) t
WHERE rn = 1;

CREATE TEMPORARY TABLE tmp_dim_user_prev_all
STORED AS ORC
AS
SELECT
    d.user_id,
    d.customerid,
    d.country,
    d.start_date,
    d.end_date,
    d.is_current
FROM dim_user d
JOIN (
    SELECT
        MAX(dt) AS prev_dt
    FROM dim_user
    WHERE dt < '${hiveconf:bizdate}'
) p
  ON d.dt = p.prev_dt;

CREATE TEMPORARY TABLE tmp_dim_user_prev_current
STORED AS ORC
AS
SELECT
    user_id,
    customerid,
    country,
    start_date,
    end_date
FROM tmp_dim_user_prev_all
WHERE is_current = TRUE;

INSERT OVERWRITE TABLE dim_user
PARTITION (dt = '${hiveconf:bizdate}')

SELECT
    user_id,
    customerid,
    country,
    start_date,
    end_date,
    is_current
FROM tmp_dim_user_prev_all
WHERE is_current = FALSE

UNION ALL

SELECT
    p.user_id,
    p.customerid,
    p.country,
    p.start_date,
    p.end_date,
    TRUE AS is_current
FROM tmp_dim_user_prev_current p
LEFT JOIN tmp_dim_user_today t
  ON p.customerid = t.customerid
WHERE t.customerid IS NULL
   OR p.country <=> t.country

UNION ALL

SELECT
    p.user_id,
    p.customerid,
    p.country,
    p.start_date,
    DATE_SUB(
        CAST('${hiveconf:bizdate}' AS DATE),
        1
    ) AS end_date,
    FALSE AS is_current
FROM tmp_dim_user_prev_current p
JOIN tmp_dim_user_today t
  ON p.customerid = t.customerid
WHERE NOT (p.country <=> t.country)

UNION ALL

SELECT
    MD5(
        CONCAT(
            t.customerid,
            '|',
            t.country,
            '|',
            '${hiveconf:bizdate}'
        )
    ) AS user_id,
    t.customerid,
    t.country,
    CAST('${hiveconf:bizdate}' AS DATE) AS start_date,
    CAST('9999-12-31' AS DATE) AS end_date,
    TRUE AS is_current
FROM tmp_dim_user_today t
LEFT JOIN tmp_dim_user_prev_current p
  ON t.customerid = p.customerid
WHERE p.customerid IS NULL
   OR NOT (p.country <=> t.country);
