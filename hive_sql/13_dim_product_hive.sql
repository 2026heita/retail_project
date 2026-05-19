-- =====================================================
-- 文件名: 13_dim_product_hive.sql
-- 功能: 创建星型模型商品维度表 dim_product
-- 说明:
--   1. 基于 DWD 清洗明细生成商品维度快照
--   2. product_id 使用 stockcode 生成稳定代理键
--   3. 使用 dt 分区保留每日商品维度快照
-- =====================================================

CREATE TABLE IF NOT EXISTS dim_product (
    product_id STRING COMMENT '商品维度代理键',
    stockcode STRING COMMENT '商品编码（原始业务键）',
    description STRING COMMENT '商品描述'
)
COMMENT '星型模型商品维度表（每日快照）'
PARTITIONED BY (dt STRING COMMENT '业务日期分区')
STORED AS ORC;
