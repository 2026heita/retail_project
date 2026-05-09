INSERT OVERWRITE TABLE dwd_retail_clean_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT 
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    CAST(Price AS DECIMAL(10,2)),
    CAST(CustomerID AS STRING),
    Country,
    CAST(ROUND(Quantity * Price, 2) AS DECIMAL(12,2))
FROM retail
WHERE Quantity > 0
  AND Price > 0
  AND CustomerID IS NOT NULL
  AND Invoice NOT LIKE 'C%';