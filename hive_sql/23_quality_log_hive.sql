CREATE TABLE IF NOT EXISTS quality_log_hive (
    table_name STRING COMMENT '被检查表名',
    check_item STRING COMMENT '检查项名称',
    abnormal_cnt BIGINT COMMENT '异常记录数',
    check_status STRING COMMENT '检查状态：PASS / FAIL',
    check_time STRING COMMENT '检查时间',

    rule_code STRING COMMENT '质量规则唯一编码',
    check_level STRING COMMENT '规则级别：BLOCK / WARN',
    actual_value DECIMAL(38,6) COMMENT '实际指标值',
    threshold_value STRING COMMENT '规则阈值或判断条件',
    check_detail STRING COMMENT '检查结果详细说明'
)
COMMENT 'Hive数据质量检查日志表'
PARTITIONED BY (dt STRING)
STORED AS ORC;