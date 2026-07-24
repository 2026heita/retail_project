-- =====================================================
-- 文件名: 12_check_etl_log.sql
-- 文件属性: 长期保留，提交代码仓库
-- 功能: 仅查询调用方传入的当前 ETL 批次日志
--
-- 说明:
--   batch_id 使用 BINARY 精确比较，避免不同 utf8mb4
--   排序规则之间出现 Illegal mix of collations。
--
-- 调用方需先设置:
--   SET @batch_id = '20260724_124053';
-- =====================================================

SELECT
    @batch_id AS requested_batch_id;

SELECT
    id,
    batch_id,
    task_name,
    run_time,
    status,
    remark
FROM etl_task_log
WHERE BINARY batch_id = BINARY @batch_id
ORDER BY id;

SELECT
    @batch_id AS batch_id,
    MIN(run_time) AS start_time,
    MAX(run_time) AS last_update_time,
    COALESCE(SUM(status = 'START'), 0) AS start_log_cnt,
    COALESCE(SUM(status = 'SUCCESS'), 0) AS success_log_cnt,
    COALESCE(SUM(status = 'FAILED'), 0) AS failed_log_cnt,
    CASE
        WHEN COALESCE(SUM(status = 'FAILED'), 0) > 0 THEN 'FAILED'
        WHEN COALESCE(SUM(status = 'SUCCESS'), 0) > 0 THEN 'SUCCESS'
        WHEN COALESCE(SUM(status = 'START'), 0) > 0 THEN 'RUNNING'
        ELSE 'NOT_FOUND'
    END AS batch_status
FROM etl_task_log
WHERE BINARY batch_id = BINARY @batch_id;
