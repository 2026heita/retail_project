-- =====================================================
-- 文件名: 32_dwd_normalization_validation_hive.sql
-- 功能: DWD 字段标准化效果验证（只读统计，不修改数据）
-- 说明:
--   1. 用于验证 DWD 字段标准化（TRIM、UPPER、CustomerID .0 剥离）的效果
--   2. 通过 --hiveconf bizdate=... 接收业务日期
--   3. 输出 DWD 总行数、去重订单数、去重客户数、去重商品数、数量合计、金额合计
--   4. 输出各字段首尾空格数量、CustomerID 以 .0 结尾数量
--   5. 重跑 DWD 前后分别执行，对比结果验证标准化效果
-- 用法:
--   hive --hiveconf bizdate=2026-04-08 -f 32_dwd_normalization_validation_hive.sql
-- =====================================================

-- ---------------------------------------------------
-- 1. DWD 基础统计（行数、订单数、客户数、商品数、数量、金额）
-- ---------------------------------------------------
SELECT
    'dwd_basic_stats' AS check_type,
    COUNT(*) AS row_count,
    COUNT(DISTINCT invoice) AS distinct_invoices,
    COUNT(DISTINCT customerid) AS distinct_customers,
    COUNT(DISTINCT stockcode) AS distinct_products,
    SUM(quantity) AS total_quantity,
    SUM(amount) AS total_amount
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';

-- ---------------------------------------------------
-- 2. 各字段首尾空格数量
-- ---------------------------------------------------
SELECT
    'field_whitespace_stats' AS check_type,
    SUM(CASE WHEN invoice <> TRIM(invoice) THEN 1 ELSE 0 END) AS invoice_with_whitespace,
    SUM(CASE WHEN stockcode <> TRIM(stockcode) THEN 1 ELSE 0 END) AS stockcode_with_whitespace,
    SUM(CASE WHEN description <> TRIM(description) THEN 1 ELSE 0 END) AS description_with_whitespace,
    SUM(CASE WHEN country <> TRIM(country) THEN 1 ELSE 0 END) AS country_with_whitespace,
    SUM(CASE WHEN customerid <> TRIM(customerid) THEN 1 ELSE 0 END) AS customerid_with_whitespace
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';

-- ---------------------------------------------------
-- 3. CustomerID 以 .0 结尾数量
-- ---------------------------------------------------
SELECT
    'customerid_dot_zero_stats' AS check_type,
    SUM(CASE WHEN customerid RLIKE '\\.0$' THEN 1 ELSE 0 END) AS customerid_ending_with_dot_zero,
    COUNT(*) AS total_rows
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';

-- ---------------------------------------------------
-- 4. CustomerID 标准化影响分析
--    统计标准化前后 customerid 值发生变化的记录数
--    （通过比较原始 customerid 和标准化后的 customerid）
-- ---------------------------------------------------
SELECT
    'customerid_normalization_impact' AS check_type,
    -- 假设 ODS 中 customerid 可能包含 .0，DWD 中已剥离
    -- 这里统计 DWD 中 customerid 是纯数字的记录数（已剥离 .0 的）
    SUM(CASE WHEN customerid RLIKE '^[0-9]+$' THEN 1 ELSE 0 END) AS numeric_customerid_count,
    -- 非纯数字 customerid 的记录数（保留原值的）
    SUM(CASE WHEN customerid NOT RLIKE '^[0-9]+$' THEN 1 ELSE 0 END) AS non_numeric_customerid_count,
    COUNT(*) AS total_rows
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';

-- ---------------------------------------------------
-- 5. StockCode 大写标准化效果
-- ---------------------------------------------------
SELECT
    'stockcode_uppercase_stats' AS check_type,
    -- 统计 stockcode 是否全部为大写
    SUM(CASE WHEN stockcode = UPPER(stockcode) THEN 1 ELSE 0 END) AS uppercase_stockcode_count,
    SUM(CASE WHEN stockcode <> UPPER(stockcode) THEN 1 ELSE 0 END) AS non_uppercase_stockcode_count,
    COUNT(*) AS total_rows
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';

-- ---------------------------------------------------
-- 6. 详细字段样例（前 10 条）
-- ---------------------------------------------------
SELECT
    invoice,
    stockcode,
    description,
    customerid,
    country,
    quantity,
    amount
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
LIMIT 10;

-- ---------------------------------------------------
-- 验证说明
-- ---------------------------------------------------
-- 重跑 DWD 前后分别执行本 SQL，对比以下指标：
--
-- 1. 基础统计（行数、订单数、客户数、商品数、数量、金额）：
--    - 行数不应意外下降
--    - 数量和金额原则上不应变化
--    - 客户数、订单数、商品数可能因空格或 .0 标准化小幅下降
--
-- 2. 首尾空格统计：
--    - 标准化后应为 0（所有字段已 TRIM）
--
-- 3. CustomerID 以 .0 结尾数量：
--    - 标准化后应为 0（纯数字 ID 已剥离 .0）
--
-- 4. CustomerID 标准化影响：
--    - numeric_customerid_count 应增加（原 .0 结尾的已剥离）
--    - non_numeric_customerid_count 保持不变（非纯数字保留原值）
--
-- 5. StockCode 大写统计：
--    - uppercase_stockcode_count 应等于 total_rows（全部已 UPPER）
