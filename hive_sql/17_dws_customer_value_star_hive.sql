-- =====================================================
-- 文件名: 17_dws_customer_value_star_hive.sql
-- 功能: 创建星型模型客户价值当日汇总表
-- 说明:
--   1. 该表基于 fact_order 当前 dt 分区生成
--   2. 表名使用 dws_customer_value_star_hive，避免与主链路 dws_customer_value_hive 冲突
--   3. 客户层级口径与主链路保持一致：High Value / Medium Value / Low Value
--   4. 当前表统计范围为单个业务日期分区，不包装为历史累计口径
-- =====================================================

CREATE TABLE IF NOT EXISTS dws_customer_value_star_hive (
    user_id STRING COMMENT '用户维度代理键',
    total_orders BIGINT COMMENT '当日订单数',
    total_amount DECIMAL(14,2) COMMENT '当日消费金额',
    customer_level STRING COMMENT '客户价值层级'
)
COMMENT '星型模型客户价值分层当日汇总表'
PARTITIONED BY (dt STRING COMMENT '业务日期分区')
STORED AS ORC;
