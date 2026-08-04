-- =====================================================
-- 文件名: 10_check_ods_ingestion_hive.sql
-- 功能: ODS 入仓完整性质量门禁（优化版）
-- 优化点:
--   1. ods_retail_raw_hive 只聚合一次
--   2. 一次计算 Raw 总量、正常 ODS 预期量、Reject 预期量
--   3. 保留 ASSERT_TRUE 阻断能力，不降低质量要求
-- =====================================================

WITH raw_parsed AS (
    SELECT
        invoicedate,
        COALESCE(
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'yyyy-MM-dd HH:mm:ss'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'yyyy-MM-dd HH:mm'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'd/M/yyyy HH:mm:ss'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'd/M/yyyy HH:mm'
            )
        ) AS invoice_timestamp
    FROM ods_retail_raw_hive
    WHERE batch_dt = '${hiveconf:bizdate}'
),

raw_metrics AS (
    SELECT
        COUNT(*) AS raw_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN invoice_timestamp IS NOT NULL
                     AND FROM_UNIXTIME(
                             invoice_timestamp,
                             'yyyy-MM-dd'
                         ) = '${hiveconf:bizdate}'
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS expected_ods_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN invoicedate IS NULL
                      OR TRIM(invoicedate) = ''
                      OR invoice_timestamp IS NULL
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS expected_reject_cnt

    FROM raw_parsed
),

source_metrics AS (
    SELECT
        COUNT(*) AS source_cnt
    FROM retail
),

ods_metrics AS (
    SELECT
        COUNT(*) AS ods_cnt
    FROM ods_retail_hive
    WHERE dt = '${hiveconf:bizdate}'
),

reject_metrics AS (
    SELECT
        COUNT(*) AS reject_cnt
    FROM ods_retail_reject_hive
    WHERE batch_dt = '${hiveconf:bizdate}'
)

SELECT
    s.source_cnt,
    r.raw_cnt,
    s.source_cnt - r.raw_cnt AS source_raw_diff,

    r.expected_ods_cnt,
    o.ods_cnt,
    r.expected_ods_cnt - o.ods_cnt AS expected_ods_diff,

    r.expected_reject_cnt,
    j.reject_cnt,
    r.expected_reject_cnt - j.reject_cnt AS expected_reject_diff,

    ASSERT_TRUE(
        s.source_cnt = r.raw_cnt
    ) AS source_to_raw_gate,

    ASSERT_TRUE(
        r.expected_ods_cnt = o.ods_cnt
    ) AS normal_ods_gate,

    ASSERT_TRUE(
        r.expected_reject_cnt = j.reject_cnt
    ) AS reject_gate

FROM source_metrics s
CROSS JOIN raw_metrics r
CROSS JOIN ods_metrics o
CROSS JOIN reject_metrics j;
