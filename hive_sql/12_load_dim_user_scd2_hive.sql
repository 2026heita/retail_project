-- =====================================================
-- 文件名: 12_load_dim_user_scd2_hive.sql
-- 功能: 加载星型模型用户维度快照
-- 说明:
--   1. 从 dwd_retail_clean_hive 当前 dt 分区抽取客户信息
--   2. 每个 customerid + country 生成一条当前有效用户维度记录
--   3. user_id 不拼接 bizdate，保证同一客户代理键稳定
--   4. 当前项目不使用 Hive ACID UPDATE，采用每日快照表达简化 SCD2
-- =====================================================

INSERT OVERWRITE TABLE dim_user
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    md5(CONCAT(customerid, '|', country)) AS user_id,
    customerid,
    country,
    CAST('${hiveconf:bizdate}' AS DATE) AS start_date,
    CAST('9999-12-31' AS DATE) AS end_date,
    TRUE AS is_current
FROM (
    SELECT DISTINCT
        customerid,
        country
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND customerid IS NOT NULL
      AND TRIM(customerid) <> ''
      AND country IS NOT NULL
      AND TRIM(country) <> ''
) t;
