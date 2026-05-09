USE retail_project;

-- =====================
-- 客户消费排名
-- =====================

SELECT
    CustomerID,
    ROUND(SUM(amount), 2) AS total_spent,
    RANK() OVER (ORDER BY SUM(amount) DESC) AS rk
FROM retail_clean2
GROUP BY CustomerID;

-- =====================
-- 每个国家消费最高客户
-- =====================

SELECT *
FROM (
    SELECT
        Country,
        CustomerID,
        ROUND(SUM(amount), 2) AS total_spent,
        ROW_NUMBER() OVER (
            PARTITION BY Country
            ORDER BY SUM(amount) DESC
        ) AS rn
    FROM retail_clean2
    GROUP BY Country, CustomerID
) t
WHERE rn = 1;

-- =====================
-- 客户累计消费额
-- =====================

SELECT
    CustomerID,
    InvoiceDate,
    amount,
    ROUND(
        SUM(amount) OVER (
            PARTITION BY CustomerID
            ORDER BY InvoiceDate
        ),
        2
    ) AS cum_spent
FROM retail_clean2;