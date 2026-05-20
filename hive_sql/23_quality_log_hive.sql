-- =====================================================
-- 文件名: 23_quality_log_hive.sql
-- 功能: 创建 Hive 数据质量检查日志表
-- 说明:
--   1. 用于记录每次质量检查结果
--   2. 不做复杂规则系统，只记录检查对象、检查项、异常数量和状态
--   3. 按 dt 分区保存业务日期检查结果
-- =====================================================

CREATE TABLE IF NOT EXISTS quality_log_hive (
    table_name STRING COMMENT '被检查表名',
    check_item STRING COMMENT '检查项名称',
    abnormal_cnt BIGINT COMMENT '异常数量',
    check_status STRING COMMENT '检查状态：PASS / FAIL',
    check_time STRING COMMENT '检查时间'
)
COMMENT 'Hive 数据质量检查日志表'
PARTITIONED BY (dt STRING)
STORED AS ORC;