-- =====================================================
-- 文件名: 21_load_dim_geo_hive.sql
-- 功能: 加载星型模型地理维度快照
-- 说明:
--   1. 从 dwd_retail_clean_hive 当前 dt 分区抽取国家信息
--   2. 按 country 去重，保证当前分区内 country 唯一
-- =====================================================

INSERT OVERWRITE TABLE dim_geo
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    md5(country) AS geo_id,
    country
FROM (
    SELECT DISTINCT
        country
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND country IS NOT NULL
      AND TRIM(country) <> ''
) t;
