-- =====================================================
-- 文件名: 14_load_dim_product_hive.sql
-- 功能: 加载星型模型商品维度快照
-- 说明:
--   1. 从 dwd_retail_clean_hive 当前 dt 分区抽取商品信息
--   2. 按 stockcode 去重，保证当前分区内 stockcode 唯一
--   3. product_id 使用 stockcode 生成稳定代理键
--   4. 支持四种日期格式: yyyy-MM-dd HH:mm:ss, yyyy-MM-dd HH:mm,
--      d/M/yyyy HH:mm:ss, d/M/yyyy HH:mm
--   5. 每个 stockcode 选择最新非空 description，
--      时间相同时按 description 降序保证唯一
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
                CASE WHEN description IS NULL OR TRIM(description) = '' THEN 1 ELSE 0 END ASC,
                COALESCE(
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm:ss'),
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm'),
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm:ss'),
                    UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm')
                ) DESC,
                description DESC
        ) AS rn
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND stockcode IS NOT NULL
      AND TRIM(stockcode) <> ''
) t
WHERE rn = 1;
