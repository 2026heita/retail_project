-- =====================================================
-- 文件名: 00_ods_retail_hive.sql
-- 功能: 创建 Hive ODS 原始订单分区表
-- 说明:
--   1. ODS 层保存原始订单数据
--   2. 按 dt 分区管理业务日期
--   3. 数据加载由 00_load_ods_retail_hive.sql 负责
-- =====================================================

CREATE TABLE IF NOT EXISTS ods_retail_hive (
    invoice STRING COMMENT '订单编号',
    stockcode STRING COMMENT '商品编码',
    description STRING COMMENT '商品描述',
    quantity BIGINT COMMENT '购买数量',
    invoicedate STRING COMMENT '订单时间',
    price DECIMAL(10,2) COMMENT '商品单价',
    customerid STRING COMMENT '客户编号',
    country STRING COMMENT '国家'
)
COMMENT 'ODS 层原始零售订单分区表'
PARTITIONED BY (dt STRING)
STORED AS ORC;
