-- =====================================================
-- 文件名: 01_load_canonical_ods.sql
-- 功能: 从 canonical ODS Raw 加载到正常 ODS 和 Reject
-- 说明:
--   1. 仅用于 canonical 数据首次入仓
--   2. 从 canonical_bootstrap_${timestamp} 批次加载
--   3. 按 InvoiceDate 动态分区到正常 ODS
--   4. 无法解析的日期进入 Reject
--   5. 待 Hive 服务器验证
-- =====================================================

-- 参数说明:
-- ${hiveconf:canonical_db} - 目标数据库（必须显式传入）
-- ${hiveconf:bootstrap_timestamp} - 引导时间戳（与 00_load_canonical_raw.sql 一致）

-- 步骤1: 加载正常 ODS（按日期分区）
INSERT INTO TABLE ${hiveconf:canonical_db}.ods_retail_hive
PARTITION (dt)
SELECT
    invoice,
    stockcode,
    description,
    CAST(quantity AS BIGINT) AS quantity,
    invoicedate,
    CAST(price AS DECIMAL(10,2)) AS price,
    customerid,
    country,
    -- 动态分区字段：从 InvoiceDate 提取日期
    COALESCE(
        -- 尝试 yyyy-MM-dd H:mm:ss
        SUBSTR(invoicedate, 1, 10),
        -- 尝试 d/M/yyyy H:mm:ss
        CONCAT(
            SUBSTR(invoicedate, 7, 4), '-',
            LPAD(SUBSTR(invoicedate, 4, 2), 2, '0'), '-',
            LPAD(SUBSTR(invoicedate, 1, 2), 2, '0')
        )
    ) AS dt
FROM ${hiveconf:canonical_db}.ods_retail_raw_hive
WHERE batch_dt = 'canonical_bootstrap_${hiveconf:bootstrap_timestamp}'
  AND (
    invoicedate RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
    OR invoicedate RLIKE '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
  );

-- 步骤2: 加载 Reject（无法解析的日期）
INSERT INTO TABLE ${hiveconf:canonical_db}.ods_retail_reject_hive
PARTITION (batch_dt = 'canonical_bootstrap_${hiveconf:bootstrap_timestamp}')
SELECT
    invoice,
    stockcode,
    description,
    quantity,
    invoicedate,
    price,
    customerid,
    country,
    'DATE_PARSE_FAILED' AS reject_reason,
    CONCAT('Cannot parse InvoiceDate: ', invoicedate) AS reject_detail
FROM ${hiveconf:canonical_db}.ods_retail_raw_hive
WHERE batch_dt = 'canonical_bootstrap_${hiveconf:bootstrap_timestamp}'
  AND NOT (
    invoicedate RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
    OR invoicedate RLIKE '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
  );
