-- =====================================================
-- 文件名: 13_data_quality_check.sql
-- 功能: 核心结果校验
-- =====================================================

-- 1. 检查 DWD 层是否还有异常数量
SELECT COUNT(*) AS abnormal_quantity_cnt
FROM retail_clean2
WHERE Quantity <= 0;

-- 2. 检查 DWD 层是否还有异常价格
SELECT COUNT(*) AS abnormal_price_cnt
FROM retail_clean2
WHERE Price <= 0;

-- 3. 检查 DWD 层是否还有空客户
SELECT COUNT(*) AS null_customer_cnt
FROM retail_clean2
WHERE CustomerID IS NULL;

-- 4. 检查 DWD 层是否还有退货单
SELECT COUNT(*) AS return_order_cnt
FROM retail_clean2
WHERE Invoice LIKE 'C%';

-- 5. 检查 DWS 客户分层是否为空
SELECT COUNT(*) AS null_customer_level_cnt
FROM dws_customer_value
WHERE customer_level IS NULL;

-- 6. 检查 ADS Top10 是否确实只有 10 行
SELECT COUNT(*) AS top10_cnt
FROM ads_top10_products;

-- 7. 检查月度销售趋势表是否为空
SELECT COUNT(*) AS monthly_sales_trend_cnt
FROM ads_monthly_sales_trend;

-- 8. 检查月度增长表是否为空
SELECT COUNT(*) AS monthly_sales_growth_cnt
FROM ads_monthly_sales_growth;

-- 9. 检查高价值客户表是否为空
SELECT COUNT(*) AS high_value_customer_cnt
FROM ads_high_value_customers;

-- 10. 检查国家销售排名表是否为空
SELECT COUNT(*) AS country_sales_rank_cnt
FROM ads_country_sales_rank;

-- 11. 检查客户收入集中度表是否为空
SELECT COUNT(*) AS customer_revenue_concentration_cnt
FROM ads_customer_revenue_concentration;

-- 12. 检查国家价值分析表是否为空
SELECT COUNT(*) AS country_value_analysis_cnt
FROM ads_country_value_analysis;

-- 13. 检查客户分层分布表是否为空
SELECT COUNT(*) AS customer_level_distribution_cnt
FROM ads_customer_level_distribution;

-- 14. 检查商品销售集中度表是否为空
SELECT COUNT(*) AS product_sales_concentration_cnt
FROM ads_product_sales_concentration;

-- 15. 检查客户下单频次分布表是否为空
SELECT COUNT(*) AS customer_order_frequency_cnt
FROM ads_customer_order_frequency;

-- 16. 检查高价值客户偏好商品表是否为空
SELECT COUNT(*) AS high_value_customer_preference_cnt
FROM ads_high_value_customer_preference;

-- 17. 检查高价值客户下单频次分布表是否为空
SELECT COUNT(*) AS high_value_customer_order_frequency_cnt
FROM ads_high_value_customer_order_frequency;

-- 18. 检查高价值客户国家分布表是否为空
SELECT COUNT(*) AS high_value_customer_country_distribution_cnt
FROM ads_high_value_customer_country_distribution;

-- 19. 检查高价值客户销售贡献表是否为空
SELECT COUNT(*) AS high_value_customer_sales_contribution_cnt
FROM ads_high_value_customer_sales_contribution;