-- =====================================================
-- 文件名: 12_load_dim_user_scd2_hive.sql
-- 功能: 加载每日完整快照式 SCD2 用户维度
-- 兼容性:
--   1. 避免 JOIN + LATERAL VIEW STACK + UNION ALL 组合
--   2. 使用临时表物化当天用户和上一快照，降低 CTE 重复展开
--   3. 适配 Hive 3.1.3 + MapReduce 执行环境
--   4. 支持四种日期格式: yyyy-MM-dd HH:mm:ss, yyyy-MM-dd HH:mm,
--      d/M/yyyy HH:mm:ss, d/M/yyyy HH:mm
--   5. 每个 customerid 选择当天时间最新的 country，
--      时间相同时按 country 升序保证唯一
-- 会话隔离要求:
--   1. 该 SQL 必须在每个业务日独立的 Hive CLI 会话中运行
--   2. 临时表由会话自动清理，无需显式 DROP TABLE
--   3. 不允许为了区间化而把多个业务日放入同一个 Hive 会话重复执行该 SQL
--   4. 区间回刷时，每个业务日必须启动独立的 Hive CLI 进程
-- =====================================================


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
                COALESCE(
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm:ss'),
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm'),
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm:ss'),
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm')
                ) DESC,
                country ASC
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
