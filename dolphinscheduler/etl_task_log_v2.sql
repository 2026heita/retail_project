-- =====================================================
-- 文件名: etl_task_log_v2.sql
-- 功能: DolphinScheduler 调度任务日志表
-- 说明:
--   1. 用于记录工作流名称、任务名称、业务日期、批次号和执行状态
--   2. 比原 etl_task_log 增加了 bizdate、workflow_name、start_time、end_time
--   3. 主要用于项目工程化展示和调度执行追踪
--   4. 本脚本为 MySQL 元数据/任务日志表，不是 Hive 建表脚本
-- =====================================================

CREATE DATABASE IF NOT EXISTS retail_project DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE retail_project;

CREATE TABLE IF NOT EXISTS etl_task_log_v2 (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '自增主键',
    workflow_name VARCHAR(100) NOT NULL COMMENT '工作流名称',
    task_name VARCHAR(100) NOT NULL COMMENT '任务名称',
    bizdate VARCHAR(20) NOT NULL COMMENT '业务日期',
    batch_id VARCHAR(50) NOT NULL COMMENT '批次号',
    start_time DATETIME DEFAULT NULL COMMENT '开始时间',
    end_time DATETIME DEFAULT NULL COMMENT '结束时间',
    status VARCHAR(20) NOT NULL COMMENT '执行状态：START/SUCCESS/FAILED',
    remark VARCHAR(255) DEFAULT NULL COMMENT '备注说明',
    KEY idx_workflow_bizdate (workflow_name, bizdate),
    KEY idx_task_bizdate (task_name, bizdate),
    KEY idx_batch_id (batch_id),
    KEY idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='DolphinScheduler 调度任务日志表';
