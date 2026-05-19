-- =====================================================
-- 文件名: 19_dim_date_hive.sql
-- 功能: 创建星型模型日期维度表 dim_date
-- 说明:
--   1. 基于 DWD 当前分区中的订单日期生成日期维度快照
--   2. 使用 dt 分区保留每日日期维度快照
-- =====================================================

CREATE TABLE IF NOT EXISTS dim_date (
    date_id DATE COMMENT '日期主键',
    date_str STRING COMMENT '日期字符串 yyyy-MM-dd',
    year_num INT COMMENT '年份',
    month_num INT COMMENT '月份',
    day_num INT COMMENT '日',
    quarter_num INT COMMENT '季度',
    weekofyear_num INT COMMENT '一年中的第几周',
    is_weekend BOOLEAN COMMENT '是否周末'
)
COMMENT '星型模型日期维度表（每日快照）'
PARTITIONED BY (dt STRING COMMENT '业务日期分区')
STORED AS ORC;
