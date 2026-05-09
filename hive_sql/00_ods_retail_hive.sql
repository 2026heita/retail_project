-- =====================================================
-- 文件名: 00_ods_retail_hive.sql
-- 功能: 创建 Hive ODS 原始订单表
-- 说明:
--   1. 该表用于存放原始零售订单数据
--   2. DWD 层会基于该表进行数据清洗
--   3. 如果 Hive 中已经存在 retail 表，可直接跳过建表或重复执行本脚本
-- =====================================================

CREATE TABLE IF NOT EXISTS retail (
    Invoice STRING COMMENT '订单编号',
    StockCode STRING COMMENT '商品编码',
    Description STRING COMMENT '商品描述',
    Quantity BIGINT COMMENT '购买数量',
    InvoiceDate STRING COMMENT '订单时间',
    Price DECIMAL(10,2) COMMENT '商品单价',
    CustomerID STRING COMMENT '客户编号',
    Country STRING COMMENT '国家'
)
COMMENT 'ODS 层原始零售订单表'
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE;

-- =====================================================
-- 可选：加载本地 CSV 数据
-- 如果原始数据已经提前导入 Hive，可以不执行下面语句
--
-- 注意：
-- 1. 请根据实际文件路径修改 /path/to/retail.csv
-- 2. 如果 CSV 文件包含表头，建议先去掉表头后再加载
-- 3. 如果商品描述字段中存在英文逗号，普通逗号分隔可能会解析异常，
--    这种情况下建议先在 MySQL 或其他工具中清洗后再导入 Hive
-- =====================================================

-- LOAD DATA LOCAL INPATH '/path/to/retail.csv'
-- OVERWRITE INTO TABLE retail;