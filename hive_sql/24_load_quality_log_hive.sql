-- =====================================================
-- 文件名: 24_load_quality_log_hive.sql
-- 功能: 写入 DWD 数据质量检查日志
-- 说明:
--   1. 将 DWD 清洗质量检查结果写入 quality_log_hive
--   2. 当前只记录最核心异常项
--   3. abnormal_cnt = 0 记为 PASS，否则记为 FAIL
-- =====================================================

INSERT OVERWRITE TABLE quality_log_hive
PARTITION (dt='${hiveconf:bizdate}')

SELECT
    'dwd_retail_clean_hive' AS table_name,
    'invalid_quantity_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status,

    CURRENT_TIMESTAMP() AS check_time

FROM dwd_retail_clean_hive
WHERE dt='${hiveconf:bizdate}'
  AND quantity <= 0


UNION ALL


SELECT
    'dwd_retail_clean_hive' AS table_name,
    'invalid_price_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status,

    CURRENT_TIMESTAMP() AS check_time

FROM dwd_retail_clean_hive
WHERE dt='${hiveconf:bizdate}'
  AND price <= 0


UNION ALL


SELECT
    'dwd_retail_clean_hive' AS table_name,
    'null_customerid_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status,

    CURRENT_TIMESTAMP() AS check_time

FROM dwd_retail_clean_hive
WHERE dt='${hiveconf:bizdate}'
  AND (customerid IS NULL OR TRIM(customerid)='');