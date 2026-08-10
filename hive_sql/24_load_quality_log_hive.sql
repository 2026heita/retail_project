-- =====================================================
-- 文件名: 24_load_quality_log_hive.sql
-- 功能:
--   1. 检查 DWD 基础数据质量
--   2. 检查 DWD 分区是否为空
--   3. 对账 ODS 理论有效行数与 DWD 实际行数
--   4. 检查 DWD 时间是否已标准化为 yyyy-MM-dd HH:mm:ss
-- =====================================================

WITH source_metrics AS (

    -- 计算 DWD 当日分区指标
    SELECT
        COUNT(1) AS dwd_row_cnt,

        COALESCE(
            SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END),
            0
        ) AS bad_quantity_cnt,

        COALESCE(
            SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END),
            0
        ) AS bad_price_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN customerid IS NULL
                      OR TRIM(customerid) = ''
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS empty_customer_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN invoicedate IS NULL
                      OR TRIM(invoicedate) = ''
                      OR UNIX_TIMESTAMP(
                            TRIM(invoicedate),
                            'yyyy-MM-dd HH:mm:ss'
                         ) IS NULL
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS invalid_invoice_time_cnt,

        CAST(0 AS BIGINT) AS ods_total_cnt,
        CAST(0 AS BIGINT) AS ods_expected_dwd_cnt

    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'

    UNION ALL

    -- 按 DWD 的同一清洗口径，计算 ODS 理论有效行数
    SELECT
        CAST(0 AS BIGINT) AS dwd_row_cnt,
        CAST(0 AS BIGINT) AS bad_quantity_cnt,
        CAST(0 AS BIGINT) AS bad_price_cnt,
        CAST(0 AS BIGINT) AS empty_customer_cnt,
        CAST(0 AS BIGINT) AS invalid_invoice_time_cnt,

        COUNT(1) AS ods_total_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN quantity > 0
                     AND price > 0
                     AND customerid IS NOT NULL
                     AND TRIM(customerid) <> ''
                     AND invoice IS NOT NULL
                     AND TRIM(invoice) <> ''
                     AND UPPER(TRIM(invoice)) NOT LIKE 'C%'
                     AND stockcode IS NOT NULL
                     AND TRIM(stockcode) <> ''
                     AND country IS NOT NULL
                     AND TRIM(country) <> ''
                     AND invoicedate IS NOT NULL
                     AND TRIM(invoicedate) <> ''
                     AND COALESCE(
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
                         ) IS NOT NULL
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS ods_expected_dwd_cnt

    FROM ods_retail_hive
    WHERE dt = '${hiveconf:bizdate}'
),

quality_metrics AS (
    SELECT
        SUM(dwd_row_cnt) AS dwd_row_cnt,
        SUM(bad_quantity_cnt) AS bad_quantity_cnt,
        SUM(bad_price_cnt) AS bad_price_cnt,
        SUM(empty_customer_cnt) AS empty_customer_cnt,
        SUM(invalid_invoice_time_cnt) AS invalid_invoice_time_cnt,
        SUM(ods_total_cnt) AS ods_total_cnt,
        SUM(ods_expected_dwd_cnt) AS ods_expected_dwd_cnt
    FROM source_metrics
)

INSERT OVERWRITE TABLE quality_log_hive
PARTITION (dt = '${hiveconf:bizdate}')

SELECT
    'dwd_retail_clean_hive' AS table_name,
    rule_result.check_item,
    rule_result.abnormal_cnt,

    CASE
        WHEN rule_result.abnormal_cnt = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status,

    CAST(CURRENT_TIMESTAMP AS STRING) AS check_time,
    rule_result.rule_code,
    'BLOCK' AS check_level,
    CAST(rule_result.actual_value AS DECIMAL(38,6)) AS actual_value,
    rule_result.threshold_value,
    rule_result.check_detail

FROM quality_metrics qm

LATERAL VIEW STACK(
    6,

    'DWD_001',
    'invalid_quantity_cnt',
    CAST(qm.bad_quantity_cnt AS BIGINT),
    CAST(qm.bad_quantity_cnt AS BIGINT),
    '= 0',
    CONCAT(
        'quantity <= 0 count: ',
        CAST(qm.bad_quantity_cnt AS STRING)
    ),

    'DWD_002',
    'invalid_price_cnt',
    CAST(qm.bad_price_cnt AS BIGINT),
    CAST(qm.bad_price_cnt AS BIGINT),
    '= 0',
    CONCAT(
        'price <= 0 count: ',
        CAST(qm.bad_price_cnt AS STRING)
    ),

    'DWD_003',
    'null_customerid_cnt',
    CAST(qm.empty_customer_cnt AS BIGINT),
    CAST(qm.empty_customer_cnt AS BIGINT),
    '= 0',
    CONCAT(
        'empty customerid count: ',
        CAST(qm.empty_customer_cnt AS STRING)
    ),

    'DWD_004',
    'partition_not_empty',
    CAST(
        CASE
            WHEN qm.dwd_row_cnt > 0 THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(qm.dwd_row_cnt AS BIGINT),
    '> 0',
    CONCAT(
        'partition row count: ',
        CAST(qm.dwd_row_cnt AS STRING),
        ', expected > 0'
    ),

    'DWD_005',
    'ods_dwd_row_count_match',
    CAST(
        CASE
            WHEN qm.ods_expected_dwd_cnt = qm.dwd_row_cnt THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(
        ABS(qm.ods_expected_dwd_cnt - qm.dwd_row_cnt)
        AS BIGINT
    ),
    '= 0',
    CONCAT(
        'ODS total rows: ',
        CAST(qm.ods_total_cnt AS STRING),
        ', ODS expected DWD rows: ',
        CAST(qm.ods_expected_dwd_cnt AS STRING),
        ', DWD actual rows: ',
        CAST(qm.dwd_row_cnt AS STRING),
        ', difference: ',
        CAST(
            ABS(qm.ods_expected_dwd_cnt - qm.dwd_row_cnt)
            AS STRING
        )
    ),

    'DWD_006',
    'invalid_invoicedate_format_cnt',
    CAST(qm.invalid_invoice_time_cnt AS BIGINT),
    CAST(qm.invalid_invoice_time_cnt AS BIGINT),
    '= 0',
    CONCAT(
        'DWD unparseable invoicedate count: ',
        CAST(qm.invalid_invoice_time_cnt AS STRING),
        ', expected standardized format: yyyy-MM-dd HH:mm:ss'
    )

) rule_result AS
    rule_code,
    check_item,
    abnormal_cnt,
    actual_value,
    threshold_value,
    check_detail;
