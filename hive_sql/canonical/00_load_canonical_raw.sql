-- =====================================================
-- 文件名: 00_load_canonical_raw.sql
-- 功能: 将 canonical 源表数据一次性加载到 ODS Raw
-- 说明:
--   1. 仅用于 canonical 数据首次入仓，不用于日常逐日加载
--   2. 使用独立批次号 canonical_bootstrap_${timestamp}
--   3. 源表 retail 必须已存在且包含完整 canonical 数据
--   4. 不删除现有 ODS Raw 数据，仅追加新批次
--   5. 待 Hive 服务器验证
-- =====================================================

-- 参数说明:
-- ${hiveconf:canonical_db} - 目标数据库（必须显式传入，不能为空或历史库）
-- ${hiveconf:bootstrap_timestamp} - 引导时间戳（格式: yyyyMMdd_HHmmss）

-- 安全检查: 确保目标数据库不是历史库
-- 注意: 此检查需要在 Shell 脚本中实现，SQL 中无法直接判断

INSERT INTO TABLE ${hiveconf:canonical_db}.ods_retail_raw_hive
PARTITION (batch_dt = 'canonical_bootstrap_${hiveconf:bootstrap_timestamp}')
SELECT
    CAST(Invoice AS STRING) AS invoice,
    CAST(StockCode AS STRING) AS stockcode,
    CAST(Description AS STRING) AS description,
    CAST(Quantity AS STRING) AS quantity,
    CAST(InvoiceDate AS STRING) AS invoicedate,
    CAST(Price AS STRING) AS price,
    CAST(`Customer ID` AS STRING) AS customerid,
    CAST(Country AS STRING) AS country,
    FROM_UNIXTIME(UNIX_TIMESTAMP(), 'yyyy-MM-dd HH:mm:ss') AS load_timestamp
FROM ${hiveconf:canonical_db}.retail;
