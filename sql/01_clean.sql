-- 1. 使用数据库
USE retail_project;

-- 2. 查看原始表
SHOW TABLES;
DESC retail;

-- 3. 创建清洗表 retail_clean
CREATE TABLE if not EXISTS retail_clean AS
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    CustomerID,
    Country,
    Quantity * Price AS amount
FROM retail
WHERE Quantity > 0
  AND Price > 0
  AND CustomerID IS NOT NULL
  AND Invoice NOT LIKE 'C%';

-- 4. 创建修正金额后的表 retail_clean2
CREATE TABLE if not EXISTS retail_clean2 AS
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    CustomerID,
    Country,
    ROUND(Quantity * Price, 2) AS amount
FROM retail_clean;

-- 5. 验证
SELECT * FROM retail_clean2 LIMIT 10;
DESC retail_clean2;