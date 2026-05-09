CREATE TABLE IF NOT EXISTS dwd_retail_clean_hive (
    invoice STRING,
    stockcode STRING,
    description STRING,
    quantity BIGINT,
    invoicedate STRING,
    price DECIMAL(10,2),
    customerid STRING,
    country STRING,
    amount DECIMAL(12,2)
)
PARTITIONED BY (dt STRING)
STORED AS ORC;