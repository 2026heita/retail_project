-- =====================================================
-- 文件名: 24_load_quality_log_hive.sql
-- 功能: 将 DWD 核心质量检查结果覆盖写入指定业务日期分区
-- 规则: abnormal_cnt = 0 记为 PASS，否则记为 FAIL
-- =====================================================

INSERT OVERWRITE TABLE quality_log_hive
PARTITION (dt='${hiveconf:bizdate}')
SELECT
    table_name,
    check_item,
    abnormal_cnt,
    check_status,
    check_time
FROM
(
    SELECT
        'dwd_retail_clean_hive' AS table_name,
        'invalid_quantity_cnt' AS check_item,
        COUNT(1) AS abnormal_cnt,
        CASE WHEN COUNT(1) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        CAST(CURRENT_TIMESTAMP AS STRING) AS check_time
    FROM dwd_retail_clean_hive
    WHERE dt='${hiveconf:bizdate}'
      AND quantity <= 0

    UNION ALL

    SELECT
        'dwd_retail_clean_hive' AS table_name,
        'invalid_price_cnt' AS check_item,
        COUNT(1) AS abnormal_cnt,
        CASE WHEN COUNT(1) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        CAST(CURRENT_TIMESTAMP AS STRING) AS check_time
    FROM dwd_retail_clean_hive
    WHERE dt='${hiveconf:bizdate}'
      AND price <= 0

    UNION ALL

    SELECT
        'dwd_retail_clean_hive' AS table_name,
        'null_customerid_cnt' AS check_item,
        COUNT(1) AS abnormal_cnt,
        CASE WHEN COUNT(1) = 0 THEN 'PASS' ELSE 'FAIL' END AS check_status,
        CAST(CURRENT_TIMESTAMP AS STRING) AS check_time
    FROM dwd_retail_clean_hive
    WHERE dt='${hiveconf:bizdate}'
      AND (customerid IS NULL OR TRIM(customerid) = '')
) quality_result;
