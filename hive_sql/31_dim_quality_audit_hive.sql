-- =====================================================
-- 文件名: 31_dim_quality_audit_hive.sql
-- 功能: 维表数据质量审计 —— 源数据冲突检测与统计
-- 说明:
--   1. 本文件从 dwd_retail_clean_hive 源数据审计冲突，而非已去重的维表。
--   2. 发现冲突不代表当前维表加载逻辑错误，只记录数据形态供后续决策。
--   3. 使用 bizdate 参数指定审计的 dt 分区。
-- 用法:
--   hive --hiveconf bizdate=2026-04-08 -f 31_dim_quality_audit_hive.sql
-- =====================================================

-- ---------------------------------------------------
-- 1. 商品冲突: 从 DWD 审计同一 stockcode 对应多个非空 description
-- ---------------------------------------------------
SELECT
    'dwd_product' AS table_name,
    'multi_description_per_stockcode' AS check_item,
    COUNT(*) AS stockcode_with_conflict,
    MAX(desc_count) AS max_descriptions,
    AVG(desc_count) AS avg_descriptions
FROM (
    SELECT
        stockcode,
        COUNT(DISTINCT description) AS desc_count
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND stockcode IS NOT NULL
      AND TRIM(stockcode) <> ''
      AND description IS NOT NULL
      AND TRIM(description) <> ''
    GROUP BY stockcode
    HAVING COUNT(DISTINCT description) > 1
) t;

-- ---------------------------------------------------
-- 2. 商品冲突样例（前 20 条）
-- ---------------------------------------------------
SELECT
    stockcode,
    COLLECT_SET(description) AS conflicting_descriptions,
    COUNT(DISTINCT description) AS desc_count
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND stockcode IS NOT NULL
  AND TRIM(stockcode) <> ''
  AND description IS NOT NULL
  AND TRIM(description) <> ''
GROUP BY stockcode
HAVING COUNT(DISTINCT description) > 1
ORDER BY desc_count DESC
LIMIT 20;

-- ---------------------------------------------------
-- 3. DWD 商品业务键总体统计
-- ---------------------------------------------------
SELECT
    'dwd_product' AS table_name,
    'summary' AS check_item,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT stockcode) AS unique_stockcodes,
    COUNT(DISTINCT description) AS unique_descriptions
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND stockcode IS NOT NULL
  AND TRIM(stockcode) <> '';

-- ---------------------------------------------------
-- 4. 客户国家冲突: 从 DWD 审计同一 customerid 当天对应多个非空 country
-- ---------------------------------------------------
SELECT
    'dwd_user' AS table_name,
    'multi_country_per_customer' AS check_item,
    COUNT(*) AS customerid_with_conflict,
    MAX(country_count) AS max_countries,
    AVG(country_count) AS avg_countries
FROM (
    SELECT
        customerid,
        COUNT(DISTINCT country) AS country_count
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
      AND customerid IS NOT NULL
      AND TRIM(customerid) <> ''
      AND country IS NOT NULL
      AND TRIM(country) <> ''
    GROUP BY customerid
    HAVING COUNT(DISTINCT country) > 1
) t;

-- ---------------------------------------------------
-- 5. 客户国家冲突样例（前 20 条）
-- ---------------------------------------------------
SELECT
    customerid,
    COLLECT_SET(country) AS conflicting_countries,
    COUNT(DISTINCT country) AS country_count
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customerid IS NOT NULL
  AND TRIM(customerid) <> ''
  AND country IS NOT NULL
  AND TRIM(country) <> ''
GROUP BY customerid
HAVING COUNT(DISTINCT country) > 1
ORDER BY country_count DESC
LIMIT 20;

-- ---------------------------------------------------
-- 6. DWD 客户总体统计
-- ---------------------------------------------------
SELECT
    'dwd_user' AS table_name,
    'summary' AS check_item,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customerid) AS unique_customers,
    COUNT(DISTINCT country) AS unique_countries
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customerid IS NOT NULL
  AND TRIM(customerid) <> '';

-- ---------------------------------------------------
-- 7. dim_product 当前分区唯一性汇总（保留用于对比）
-- ---------------------------------------------------
SELECT
    'dim_product' AS table_name,
    'summary' AS check_item,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT stockcode) AS unique_stockcodes,
    COUNT(DISTINCT description) AS unique_descriptions
FROM dim_product
WHERE dt = '${hiveconf:bizdate}';

-- ---------------------------------------------------
-- 8. dim_user 当前分区唯一性汇总（保留用于对比）
-- ---------------------------------------------------
SELECT
    'dim_user' AS table_name,
    'summary' AS check_item,
    COUNT(*) AS total_versions,
    SUM(CASE WHEN is_current = TRUE THEN 1 ELSE 0 END) AS current_versions,
    COUNT(DISTINCT customerid) AS unique_customers,
    COUNT(DISTINCT country) AS unique_countries
FROM dim_user
WHERE dt = '${hiveconf:bizdate}';

-- ---------------------------------------------------
-- 审计说明
-- ---------------------------------------------------
-- 上述查询从 dwd_retail_clean_hive 源数据审计冲突，而非已去重的维表。
-- 
-- 数据来源说明:
--   - 商品冲突审计来自 DWD，统计同一 stockcode 对应多个非空 description。
--   - 客户国家冲突审计来自 DWD，统计同一 customerid 当天对应多个非空 country。
--   - 维表汇总统计仅用于对比，不用于冲突检测。
--
-- 取值策略说明（当前 dim_product 加载逻辑）:
--   - 从 DWD 中按 stockcode 分组，使用 ROW_NUMBER() 选择最新非空 description。
--   - 优先选择非空 description，其次按 invoicedate 最新优先。
--   - 时间相同时按 description 降序保证唯一。
--   这是一种"最新非空描述代表值"策略。
--
-- 取值策略说明（当前 dim_user 加载逻辑）:
--   - 从 DWD 中按 customerid 分组，选择当天最新交易时间的 country。
--   - 支持四种日期格式解析 invoicedate。
--   - 时间相同时按 country 升序保证唯一。
--   这是一种"当天最新交易 country 驱动 SCD2"策略。
--
-- 源数据冲突审计不等于维度加载失败:
--   - 维表加载逻辑已通过 ROW_NUMBER() 选择代表值，保证维度唯一性。
--   - 冲突显著时说明源数据存在不一致，需要业务主数据规则进一步治理。
--   - 本审计仅记录数据形态，供后续决策参考。