-- =====================================================
-- File: 10_check_ods_ingestion_hive.sql
-- Purpose: ODS ingestion completeness quality gate
-- Description:
--   1. Raw 批次包含完整源表（整个 retail 表）
--   2. 正常 ODS 是指定业务日期（bizdate）的技术合格记录
--   3. Reject 是技术解析失败的记录（日期/数量/价格解析异常）
--   4. 合法的其他日期记录属于 expected_other_date_cnt（不是 Reject）
--   5. 三个集合互斥且覆盖整个 Raw 批次：
--      raw_cnt = expected_ods_cnt + expected_reject_cnt + expected_other_date_cnt
--   6. Use EXACTLY the same parsing logic as load scripts
--   7. Technical admission: invoice_timestamp, parsed_quantity,
--      parsed_price must all be non-NULL for normal ODS
--   8. Reject: any of the three is NULL
--   9. Date formats: yyyy-MM-dd HH:mm:ss, yyyy-MM-dd HH:mm,
--      d/M/yyyy HH:mm:ss, d/M/yyyy HH:mm
-- =====================================================

WITH raw_parsed AS (
    SELECT
        invoice,
        stockcode,
        description,
        quantity,
        invoicedate,
        price,
        customerid,
        country,
        COALESCE(
            UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm:ss'),
            UNIX_TIMESTAMP(TRIM(invoicedate), 'yyyy-MM-dd HH:mm'),
            UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm:ss'),
            UNIX_TIMESTAMP(TRIM(invoicedate), 'd/M/yyyy HH:mm')
        ) AS invoice_timestamp,
        CASE
            WHEN TRIM(CAST(quantity AS STRING)) IS NULL
              OR TRIM(CAST(quantity AS STRING)) = ''
            THEN NULL
            ELSE CAST(TRIM(CAST(quantity AS STRING)) AS BIGINT)
        END AS parsed_quantity,
        CASE
            WHEN TRIM(CAST(price AS STRING)) IS NULL
              OR TRIM(CAST(price AS STRING)) = ''
            THEN NULL
            ELSE CAST(TRIM(CAST(price AS STRING)) AS DECIMAL(10,2))
        END AS parsed_price
    FROM ods_retail_raw_hive
    WHERE batch_dt = '${hiveconf:batch_dt}'
),

raw_metrics AS (
    SELECT
        COUNT(*) AS raw_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN invoice_timestamp IS NOT NULL
                     AND parsed_quantity IS NOT NULL
                     AND parsed_price IS NOT NULL
                     AND FROM_UNIXTIME(invoice_timestamp, 'yyyy-MM-dd') = '${hiveconf:bizdate}'
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS expected_ods_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN invoice_timestamp IS NULL
                      OR parsed_quantity IS NULL
                      OR parsed_price IS NULL
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS expected_reject_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN invoice_timestamp IS NOT NULL
                     AND parsed_quantity IS NOT NULL
                     AND parsed_price IS NOT NULL
                     AND FROM_UNIXTIME(invoice_timestamp, 'yyyy-MM-dd') <> '${hiveconf:bizdate}'
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS expected_other_date_cnt

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
    WHERE batch_dt = '${hiveconf:batch_dt}'
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

    r.expected_other_date_cnt,

    r.expected_ods_cnt + r.expected_reject_cnt + r.expected_other_date_cnt AS expected_total,
    r.raw_cnt AS actual_total,
    r.raw_cnt - (r.expected_ods_cnt + r.expected_reject_cnt + r.expected_other_date_cnt) AS balance_diff,

    ASSERT_TRUE(
        s.source_cnt = r.raw_cnt
    ) AS source_to_raw_gate,

    ASSERT_TRUE(
        r.expected_ods_cnt = o.ods_cnt
    ) AS normal_ods_gate,

    ASSERT_TRUE(
        r.expected_reject_cnt = j.reject_cnt
    ) AS reject_gate,

    ASSERT_TRUE(
        r.raw_cnt = r.expected_ods_cnt + r.expected_reject_cnt + r.expected_other_date_cnt
    ) AS balance_gate

FROM source_metrics s
CROSS JOIN raw_metrics r
CROSS JOIN ods_metrics o
CROSS JOIN reject_metrics j;
