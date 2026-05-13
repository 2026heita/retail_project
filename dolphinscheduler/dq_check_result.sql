-- =====================================================
-- 文件名: dq_check_result.sql
-- 功能: 数据质量校验结果表
-- 说明:
--   1. 用于保存每次调度后的数据质量校验结果
--   2. 不只看 SQL 是否执行成功，还检查结果数据是否可用
--   3. 后续可扩展为 DolphinScheduler 告警依据
--   4. 本脚本为 MySQL 元数据/结果记录表，不是 Hive 建表脚本
-- =====================================================

CREATE DATABASE IF NOT EXISTS retail_project DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE retail_project;

CREATE TABLE IF NOT EXISTS dq_check_result (
    id INT PRIMARY KEY AUTO_INCREMENT COMMENT '自增主键',
    workflow_name VARCHAR(100) NOT NULL COMMENT '工作流名称',
    task_name VARCHAR(100) NOT NULL COMMENT '任务名称',
    bizdate VARCHAR(20) NOT NULL COMMENT '业务日期',
    check_item VARCHAR(100) NOT NULL COMMENT '校验项',
    check_result DECIMAL(18,2) NOT NULL COMMENT '校验结果',
    expected_rule VARCHAR(100) NOT NULL COMMENT '期望规则',
    status VARCHAR(20) NOT NULL COMMENT '校验状态：PASS/FAILED',
    check_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '校验时间',
    remark VARCHAR(255) DEFAULT NULL COMMENT '备注说明',
    KEY idx_workflow_bizdate (workflow_name, bizdate),
    KEY idx_task_bizdate (task_name, bizdate),
    KEY idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数据质量校验结果表';
