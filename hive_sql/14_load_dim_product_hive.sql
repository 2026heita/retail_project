-- =====================================================
-- 文件名: 14_load_dim_product_hive.sql
-- 功能: 加载星型模型商品维度快照
-- 说明:
--   1. 从 dwd_retail_clean_hive 当前 dt 分区抽取商品信息
--   2. 按 stockcode 去重，保证当前分区内 stockcode 唯一
--   3. product_id 使用 stockcode 生成稳定代理键
-- =====================================================

INSERT OVERWRITE TABLE dim_product
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    md5(stockcode) AS product_id,
    stockcode,
    description
FROM (
    SELECT
        stockcode,
        description,
        ROW_NUMBER() OVER (
            PARTITION BY stockcode
            ORDER BY
                CASE WHEN description IS NULL OR TRIM(description) = '' THEN 1 ELSE 0 END,
                description
        ) AS rn
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND stockcode IS NOT NULL
      AND TRIM(stockcode) <> ''
) t
WHERE rn = 1;
