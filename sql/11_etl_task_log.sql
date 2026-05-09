-- =====================================================
-- 文件名: 11_etl_task_log.sql
-- 功能: 创建 ETL 任务日志表（带批次号）
-- =====================================================


CREATE TABLE IF NOT EXISTS etl_task_log (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '自增主键',
    batch_id VARCHAR(50) NOT NULL COMMENT '批次号',
    task_name VARCHAR(100) NOT NULL COMMENT '任务名称',
    run_time DATETIME NOT NULL COMMENT '执行时间',
    status VARCHAR(20) NOT NULL COMMENT '执行状态：START/SUCCESS/FAILED',
    remark VARCHAR(255) DEFAULT NULL COMMENT '备注说明'
);