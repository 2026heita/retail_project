USE retail_project;

-- =============================
-- ADS：商品销售集中度分析
-- =============================

DROP TABLE IF EXISTS ads_product_sales_concentration;

CREATE TABLE ads_product_sales_concentration AS
WITH product_sales AS (
    SELECT
        StockCode,
        Description,
        ROUND(SUM(amount), 2) AS total_sales
    FROM retail_clean2
    GROUP BY StockCode, Description
),
ranked_products AS (
    SELECT
        StockCode,
        Description,
        total_sales,
        ROW_NUMBER() OVER (ORDER BY total_sales DESC) AS rn
    FROM product_sales
),
total_base AS (
    SELECT ROUND(SUM(total_sales), 2) AS total_sales_all
    FROM product_sales
)
SELECT
    'TOP10' AS product_group,
    COUNT(*) AS product_count,
    ROUND(SUM(total_sales), 2) AS group_sales,
    ROUND(SUM(total_sales) / MAX(total_sales_all) * 100, 2) AS sales_contribution_pct
FROM ranked_products
CROSS JOIN total_base
WHERE rn <= 10

UNION ALL

SELECT
    'TOP50' AS product_group,
    COUNT(*) AS product_count,
    ROUND(SUM(total_sales), 2) AS group_sales,
    ROUND(SUM(total_sales) / MAX(total_sales_all) * 100, 2) AS sales_contribution_pct
FROM ranked_products
CROSS JOIN total_base
WHERE rn <= 50;

-- 查看结果
SELECT * FROM ads_product_sales_concentration;

-- 这个指标是看平台销售是否过度依赖少数爆款商品。相比单纯做 Top10 商品排行，这张表更强调商品结构是否健康。