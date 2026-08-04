-- =====================================================
-- 文件名: 31_dim_quality_audit_hive.sql
-- 功能: 维表数据质量审计 —— 冲突检测与统计
-- 说明:
--   1. 本文件仅用于审计和诊断，不修改 dim_product 或 dim_user 的业务语义。
--   2. 发现冲突不代表当前维表加载逻辑错误，只记录数据形态供后续决策。
--   3. 使用 bizdate 参数指定审计的 dt 分区。
-- 用法:
--   hive --hiveconf bizdate=2026-04-08 -f 31_dim_quality_audit_hive.sql
-- =====================================================

-- ---------------------------------------------------
-- 1. dim_product: 一个 stockcode 对应多个 description 的数量
-- ---------------------------------------------------
SELECT
    'dim_product' AS table_name,
    'multi_description_per_stockcode' AS check_item,
    COUNT(*) AS stockcode_with_conflict,
    MAX(desc_count) AS max_descriptions,
    AVG(desc_count) AS avg_descriptions
FROM (
    SELECT
        stockcode,
        COUNT(DISTINCT description) AS desc_count
    FROM dim_product
    WHERE dt = '${hiveconf:bizdate}'
      AND stockcode IS NOT NULL
      AND TRIM(stockcode) <> ''
    GROUP BY stockcode
    HAVING COUNT(DISTINCT description) > 1
) t;

-- ---------------------------------------------------
-- 2. dim_product: 冲突样例（前 20 条）
-- ---------------------------------------------------
SELECT
    stockcode,
    COLLECT_SET(description) AS conflicting_descriptions,
    COUNT(DISTINCT description) AS desc_count
FROM dim_product
WHERE dt = '${hiveconf:bizdate}'
  AND stockcode IS NOT NULL
  AND TRIM(stockcode) <> ''
GROUP BY stockcode
HAVING COUNT(DISTINCT description) > 1
ORDER BY desc_count DESC
LIMIT 20;

-- ---------------------------------------------------
-- 3. dim_product: 总体统计
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
-- 4. dim_user: 当前版本中一个 customerid 对应多个 country 的数量
--    （仅在 is_current = TRUE 的版本中检查）
-- ---------------------------------------------------
SELECT
    'dim_user' AS table_name,
    'multi_country_per_customer_current' AS check_item,
    COUNT(*) AS customerid_with_conflict,
    MAX(country_count) AS max_countries,
    AVG(country_count) AS avg_countries
FROM (
    SELECT
        customerid,
        COUNT(DISTINCT country) AS country_count
    FROM dim_user
    WHERE dt = '${hiveconf:bizdate}'
      AND is_current = TRUE
      AND customerid IS NOT NULL
      AND TRIM(customerid) <> ''
    GROUP BY customerid
    HAVING COUNT(DISTINCT country) > 1
) t;

-- ---------------------------------------------------
-- 5. dim_user: 冲突样例（前 20 条）
-- ---------------------------------------------------
SELECT
    customerid,
    COLLECT_SET(country) AS conflicting_countries,
    COUNT(DISTINCT country) AS country_count
FROM dim_user
WHERE dt = '${hiveconf:bizdate}'
  AND is_current = TRUE
  AND customerid IS NOT NULL
  AND TRIM(customerid) <> ''
GROUP BY customerid
HAVING COUNT(DISTINCT country) > 1
ORDER BY country_count DESC
LIMIT 20;

-- ---------------------------------------------------
-- 6. dim_user: 总体统计
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
-- 7. dim_user: 版本分布（每个 customerid 的版本数分布）
-- ---------------------------------------------------
SELECT
    'dim_user' AS table_name,
    'version_distribution' AS check_item,
    version_count,
    COUNT(*) AS customer_count
FROM (
    SELECT
        customerid,
        COUNT(*) AS version_count
    FROM dim_user
    WHERE dt = '${hiveconf:bizdate}'
      AND customerid IS NOT NULL
      AND TRIM(customerid) <> ''
    GROUP BY customerid
) t
GROUP BY version_count
ORDER BY version_count;

-- ---------------------------------------------------
-- 审计说明
-- ---------------------------------------------------
-- 上述查询仅用于诊断 dim_product 和 dim_user 的数据质量。
-- 
-- 取值策略说明（当前 dim_product 加载逻辑）:
--   - 从 DWD 中按 stockcode 分组，使用 ROW_NUMBER() 选择一条 description。
--   - 优先选择非空 description，其次按字典序选择。
--   - 当同一 stockcode 在 DWD 中有多条不同 description 时，只保留一条。
--   这是一种"代表值"策略，不等同于独立商品主数据系统。
--
-- 取值策略说明（当前 dim_user 加载逻辑）:
--   - 从 DWD 中按 customerid 分组，选择当天最新时间戳的 country。
--   - 当同一 customerid 在同一天有多个 country 时，按 country 字典序选择。
--   这是一种"最近一条"策略，不保证 country 是客户的实际所在地。
--
-- 如果审计发现冲突数量显著，且业务上需要更准确的取值规则，
-- 再根据明确的业务规则修改 dim_product 和 dim_user 的加载逻辑。