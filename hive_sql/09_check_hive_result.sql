-- =====================================================
-- 文件名: 09_check_hive_result.sql
-- 功能: Hive 数仓结果校验脚本
-- 说明:
--   1. bizdate 由 --hiveconf 传入
--   2. 检查 ODS / DWD / DWS / ADS 各层分区数据量
--   3. 检查 DWD 清洗质量、DWS 客户分层边界和 ADS 指标合理性
-- =====================================================

-- Check 1: Partition row count check

SELECT 'ods_retail_hive' AS table_name, COUNT(*) AS row_cnt
FROM ods_retail_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT 'dwd_retail_clean_hive' AS table_name, COUNT(*) AS row_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT 'dws_customer_value_hive' AS table_name, COUNT(*) AS row_cnt
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT 'dws_sales_summary_hive' AS table_name, COUNT(*) AS row_cnt
FROM dws_sales_summary_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT 'ads_high_value_customer_sales_contribution_hive' AS table_name, COUNT(*) AS row_cnt
FROM ads_high_value_customer_sales_contribution_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT 'ads_customer_level_distribution_hive' AS table_name, COUNT(*) AS row_cnt
FROM ads_customer_level_distribution_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT 'ads_country_sales_rank_hive' AS table_name, COUNT(*) AS row_cnt
FROM ads_country_sales_rank_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT 'ads_high_value_customer_preference_hive' AS table_name, COUNT(*) AS row_cnt
FROM ads_high_value_customer_preference_hive
WHERE dt = '${hiveconf:bizdate}';

-- Check 2: DWD cleaning quality check

SELECT
    'dwd_invalid_quantity_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND quantity <= 0;

SELECT
    'dwd_invalid_price_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND price <= 0;

SELECT
    'dwd_null_or_blank_customerid_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND (customerid IS NULL OR TRIM(customerid) = '');

SELECT
    'dwd_cancel_invoice_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND UPPER(TRIM(invoice)) LIKE 'C%';

SELECT
    'dwd_invalid_amount_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND (amount IS NULL OR amount <= 0);

-- Check 3: DWS customer value level quality check

SELECT
    customer_level,
    COUNT(*) AS customer_cnt,
    CAST(ROUND(SUM(total_spent), 2) AS DECIMAL(14,2)) AS total_spent
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY customer_level;

SELECT
    'dws_null_customer_level_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customer_level IS NULL;

SELECT
    'dws_invalid_customer_level_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customer_level NOT IN ('High Value', 'Medium Value', 'Low Value');

SELECT
    'dws_high_value_boundary_error_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customer_level = 'High Value'
  AND total_spent < 5000;

SELECT
    'dws_medium_value_boundary_error_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customer_level = 'Medium Value'
  AND (total_spent < 1000 OR total_spent >= 5000);

SELECT
    'dws_low_value_boundary_error_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customer_level = 'Low Value'
  AND total_spent >= 1000;

-- Check 4: ADS metric consistency check

SELECT
    'ads_high_value_sales_contribution_pct_error_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM ads_high_value_customer_sales_contribution_hive
WHERE dt = '${hiveconf:bizdate}'
  AND (sales_contribution_pct IS NULL OR sales_contribution_pct < 0 OR sales_contribution_pct > 100);

SELECT
    'ads_customer_level_customer_pct_sum' AS check_item,
    CAST(ROUND(SUM(customer_cnt_pct), 2) AS DECIMAL(10,2)) AS pct_sum
FROM ads_customer_level_distribution_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT
    'ads_customer_level_sales_pct_sum' AS check_item,
    CAST(ROUND(SUM(sales_pct), 2) AS DECIMAL(10,2)) AS pct_sum
FROM ads_customer_level_distribution_hive
WHERE dt = '${hiveconf:bizdate}';

SELECT
    'ads_country_sales_rank_null_rank_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM ads_country_sales_rank_hive
WHERE dt = '${hiveconf:bizdate}'
  AND sales_rank IS NULL;

SELECT
    'ads_country_sales_rank_invalid_sales_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM ads_country_sales_rank_hive
WHERE dt = '${hiveconf:bizdate}'
  AND (total_sales IS NULL OR total_sales <= 0);

SELECT
    'ads_high_value_customer_preference_null_rank_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM ads_high_value_customer_preference_hive
WHERE dt = '${hiveconf:bizdate}'
  AND sales_rank IS NULL;

SELECT
    'ads_high_value_customer_preference_invalid_sales_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM ads_high_value_customer_preference_hive
WHERE dt = '${hiveconf:bizdate}'
  AND (total_sales IS NULL OR total_sales <= 0);

SELECT
    'ads_high_value_customer_preference_invalid_quantity_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM ads_high_value_customer_preference_hive
WHERE dt = '${hiveconf:bizdate}'
  AND (total_quantity IS NULL OR total_quantity <= 0);
