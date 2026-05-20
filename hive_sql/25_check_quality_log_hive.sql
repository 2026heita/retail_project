-- =====================================================
-- 文件名: 25_check_quality_log_hive.sql
-- 功能: 查看 Hive 数据质量检查日志
-- 说明:
--   1. 按 bizdate 查看 quality_log_hive 中的质量检查结果
--   2. 用于验证质量模块是否正常写入
-- =====================================================

SELECT
    dt,
    table_name,
    check_item,
    abnormal_cnt,
    check_status,
    check_time
FROM quality_log_hive
WHERE dt = '${hiveconf:bizdate}'
ORDER BY
    table_name,
    check_item,
    check_time;