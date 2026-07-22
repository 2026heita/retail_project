-- =====================================================
-- 文件名: 00_bootstrap_sample_source_hive.sql
-- 功能: 从本地完整 CSV 重建 Hive 源表 retail
-- 用法:
--   hive \
--     --hiveconf source_file=/home/admin/retail_hive_project/data/retail.csv \
--     -f 00_bootstrap_sample_source_hive.sql
--
-- 说明:
--   1. retail 是可由本地 CSV 重建的源表。
--   2. 使用 DROP ... PURGE 清理旧表及损坏的 HDFS 文件记录。
--   3. OpenCSVSerde 用于正确解析带引号、字段内含逗号的 CSV。
--   4. 建表、表属性、数据加载分开执行，降低 Hive 版本解析差异。
-- =====================================================

DROP TABLE IF EXISTS retail PURGE;

CREATE TABLE retail (
    Invoice STRING,
    StockCode STRING,
    Description STRING,
    Quantity STRING,
    InvoiceDate STRING,
    Price STRING,
    CustomerID STRING,
    Country STRING
)
ROW FORMAT SERDE
    'org.apache.hadoop.hive.serde2.OpenCSVSerde'
STORED AS TEXTFILE;

ALTER TABLE retail SET TBLPROPERTIES (
    'skip.header.line.count' = '1'
);

LOAD DATA LOCAL INPATH '${hiveconf:source_file}'
OVERWRITE INTO TABLE retail;
