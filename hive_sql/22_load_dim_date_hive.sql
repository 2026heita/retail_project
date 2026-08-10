-- =====================================================
-- 文件名: 22_load_dim_date_hive.sql
-- 功能: 加载星型模型日期维度快照
-- 说明:
--   1. 直接使用 canonical 分区日期 dt（已通过全量质量门禁）
--   2. 保证 fact_order 关联 dim_date 时 date_id 可匹配
--   3. 使用 INSERT OVERWRITE 覆盖当前 dt 分区，保证任务幂等
--   4. 由于脚本只处理一个 bizdate 分区，最终生成唯一的一条 date_id
-- =====================================================

INSERT OVERWRITE TABLE dim_date
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    biz_date AS date_id,
    CAST(biz_date AS STRING) AS date_str,
    YEAR(biz_date) AS year_num,
    MONTH(biz_date) AS month_num,
    DAYOFMONTH(biz_date) AS day_num,
    CAST(CEIL(MONTH(biz_date) / 3.0) AS INT) AS quarter_num,
    WEEKOFYEAR(biz_date) AS weekofyear_num,
    CASE
        WHEN PMOD(DATEDIFF(biz_date, '1970-01-04'), 7) IN (0, 6)
        THEN TRUE
        ELSE FALSE
    END AS is_weekend
FROM (
    SELECT CAST('${hiveconf:bizdate}' AS DATE) AS biz_date
) t
WHERE biz_date IS NOT NULL;
