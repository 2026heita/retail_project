-- =====================================================
-- 文件名: 00_ods_retail_raw_hive.sql
-- 功能: 创建零售源数据原始落地表
-- 说明:
--   1. 所有业务字段均使用 STRING，保证原始值不因类型转换而丢失
--   2. 不在原始落地层执行清洗、过滤和日期解析
--   3. batch_dt 表示本次 ETL 批次处理的业务日期
-- =====================================================

CREATE TABLE IF NOT EXISTS ods_retail_raw_hive (
    invoice STRING COMMENT '原始订单编号',
    stockcode STRING COMMENT '原始商品编码',
    description STRING COMMENT '原始商品描述',
    quantity STRING COMMENT '原始购买数量',
    invoicedate STRING COMMENT '原始订单时间',
    price STRING COMMENT '原始商品单价',
    customerid STRING COMMENT '原始客户编号',
    country STRING COMMENT '原始国家'
)
COMMENT 'ODS原始落地表，完整保存源数据'
PARTITIONED BY (
    batch_dt STRING COMMENT 'ETL处理批次日期'
)
STORED AS ORC;