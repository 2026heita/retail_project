-- 1. 查看所有日志
SELECT * 
FROM etl_task_log
ORDER BY id DESC;

-- 2. 查看最近批次
SELECT DISTINCT batch_id
FROM etl_task_log
ORDER BY batch_id DESC;

-- 3. 查看某一批次执行详情
SELECT *
FROM etl_task_log
WHERE batch_id = '20260412_153045'
ORDER BY id;