-- =====================================================
-- 文件名: 15_fact_order_hive.sql
-- 功能: 创建星型模型订单事实表 fact_order
-- 说明:
--   1. 基于 DWD 清洗明细和维度表生成订单事实表
--   2. 保留订单明细粒度，一张发票可能对应多条商品明细
--   3. order_line_id 为订单明细代理键，order_id 保留原始发票号
--   4. 使用 dt 分区支持指定业务日期重跑
-- =====================================================

CREATE TABLE IF NOT EXISTS fact_order (
    order_line_id STRING COMMENT '订单明细代理键',
    order_id STRING COMMENT '订单编号/发票号',
    user_id STRING COMMENT '用户维度代理键',
    product_id STRING COMMENT '商品维度代理键',
    date_id DATE COMMENT '日期维度主键',
    geo_id STRING COMMENT '地理维度代理键',
    quantity BIGINT COMMENT '购买数量',
    amount DECIMAL(12,2) COMMENT '订单明细金额'
)
COMMENT '星型模型订单事实表'
PARTITIONED BY (dt STRING COMMENT '业务日期分区')
STORED AS ORC;
