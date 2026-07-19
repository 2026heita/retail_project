-- =====================================================
-- 文件名: 00_bootstrap_sample_source_hive.sql
-- 功能: 使用仓库样例 CSV 初始化 Hive 源表 retail
-- 说明:
--   1. 仅用于本地演示和最小链路复现
--   2. 不属于每日 ODS-DWD-DWS-ADS 调度任务
--   3. source_file 由命令行参数传入
-- =====================================================

CREATE TABLE IF NOT EXISTS retail (
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
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"'
)
STORED AS TEXTFILE
TBLPROPERTIES (
    'skip.header.line.count' = '1'
);

LOAD DATA LOCAL INPATH '${hiveconf:source_file}'
OVERWRITE INTO TABLE retail;