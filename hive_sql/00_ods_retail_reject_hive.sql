CREATE TABLE IF NOT EXISTS ods_retail_reject_hive (
    invoice STRING COMMENT '原始订单编号',
    stockcode STRING COMMENT '原始商品编码',
    description STRING COMMENT '原始商品描述',
    quantity STRING COMMENT '原始购买数量',
    invoicedate STRING COMMENT '原始订单时间',
    price STRING COMMENT '原始商品单价',
    customerid STRING COMMENT '原始客户编号',
    country STRING COMMENT '原始国家',
    parsed_bizdate STRING COMMENT '解析后的业务日期',
    reject_code STRING COMMENT '异常类型编码',
    reject_reason STRING COMMENT '异常原因'
)
COMMENT 'ODS异常数据表'
PARTITIONED BY (
    batch_dt STRING COMMENT 'ETL处理批次日期'
)
STORED AS ORC;
