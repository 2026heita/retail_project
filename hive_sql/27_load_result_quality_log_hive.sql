-- =====================================================
-- 文件名: 27_load_result_quality_log_hive.sql
-- 功能:
--   1. 对 DWS / ADS 结果做后置质量检查
--   2. 将检查结果写入独立的结果质量日志表
--   3. BLOCK 失败用于阻断主任务，WARN 只记录不阻断
-- 说明:
--   与 DWD 前置门禁分表保存，避免重复执行时污染已有质量日志。
-- =====================================================

CREATE TABLE IF NOT EXISTS result_quality_log_hive (
    table_name STRING COMMENT '被检查表名',
    check_item STRING COMMENT '检查项名称',
    abnormal_cnt BIGINT COMMENT '异常记录数',
    check_status STRING COMMENT '检查状态：PASS / FAIL',
    check_time STRING COMMENT '检查时间',
    rule_code STRING COMMENT '质量规则唯一编码',
    check_level STRING COMMENT '规则级别：BLOCK / WARN',
    actual_value DECIMAL(38,6) COMMENT '实际指标值',
    threshold_value STRING COMMENT '规则阈值或判断条件',
    check_detail STRING COMMENT '检查结果详细说明'
)
COMMENT 'Hive DWS和ADS结果质量检查日志表'
PARTITIONED BY (dt STRING COMMENT '业务日期')
STORED AS ORC;


WITH dwd_metrics AS (
    SELECT
        CAST(
            ROUND(COALESCE(SUM(amount), 0), 2)
            AS DECIMAL(38,6)
        ) AS dwd_total_sales
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
),

dws_customer_metrics AS (
    SELECT
        COUNT(1) AS dws_customer_row_cnt,
        CAST(
            ROUND(COALESCE(SUM(total_spent), 0), 2)
            AS DECIMAL(38,6)
        ) AS dws_customer_total_sales
    FROM dws_customer_value_hive
    WHERE dt = '${hiveconf:bizdate}'
),

dws_sales_metrics AS (
    SELECT
        COUNT(1) AS dws_sales_row_cnt,
        CAST(
            ROUND(COALESCE(SUM(total_sales), 0), 2)
            AS DECIMAL(38,6)
        ) AS dws_country_total_sales
    FROM dws_sales_summary_hive
    WHERE dt = '${hiveconf:bizdate}'
),

ads_contribution_metrics AS (
    SELECT
        COUNT(1) AS ads_contribution_row_cnt,
        COALESCE(
            SUM(
                CASE
                    WHEN sales_contribution_pct IS NULL
                      OR sales_contribution_pct < 0
                      OR sales_contribution_pct > 100
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS invalid_contribution_pct_cnt
    FROM ads_high_value_customer_sales_contribution_hive
    WHERE dt = '${hiveconf:bizdate}'
),

ads_level_metrics AS (
    SELECT
        COUNT(1) AS ads_level_row_cnt,

        CAST(
            ROUND(COALESCE(SUM(customer_cnt_pct), 0), 2)
            AS DECIMAL(38,6)
        ) AS customer_pct_sum,

        CAST(
            ROUND(COALESCE(SUM(sales_pct), 0), 2)
            AS DECIMAL(38,6)
        ) AS sales_pct_sum

    FROM ads_customer_level_distribution_hive
    WHERE dt = '${hiveconf:bizdate}'
),

ads_country_metrics AS (
    SELECT
        COUNT(1) AS ads_country_row_cnt
    FROM ads_country_sales_rank_hive
    WHERE dt = '${hiveconf:bizdate}'
),

ads_preference_metrics AS (
    SELECT
        COUNT(1) AS ads_preference_row_cnt
    FROM ads_high_value_customer_preference_hive
    WHERE dt = '${hiveconf:bizdate}'
),

all_metrics AS (
    SELECT
        dwd.dwd_total_sales,
        dc.dws_customer_row_cnt,
        dc.dws_customer_total_sales,
        ds.dws_sales_row_cnt,
        ds.dws_country_total_sales,
        ac.ads_contribution_row_cnt,
        ac.invalid_contribution_pct_cnt,
        al.ads_level_row_cnt,
        al.customer_pct_sum,
        al.sales_pct_sum,
        ar.ads_country_row_cnt,
        ap.ads_preference_row_cnt
    FROM dwd_metrics dwd
    CROSS JOIN dws_customer_metrics dc
    CROSS JOIN dws_sales_metrics ds
    CROSS JOIN ads_contribution_metrics ac
    CROSS JOIN ads_level_metrics al
    CROSS JOIN ads_country_metrics ar
    CROSS JOIN ads_preference_metrics ap
)

INSERT OVERWRITE TABLE result_quality_log_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    rule_result.table_name,
    rule_result.check_item,
    rule_result.abnormal_cnt,

    CASE
        WHEN rule_result.abnormal_cnt = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status,

    CAST(CURRENT_TIMESTAMP AS STRING) AS check_time,
    rule_result.rule_code,
    rule_result.check_level,
    rule_result.actual_value,
    rule_result.threshold_value,
    rule_result.check_detail

FROM all_metrics m

LATERAL VIEW STACK(
    11,

    'dws_customer_value_hive',
    'RESULT_001',
    'dws_customer_partition_not_empty',
    'BLOCK',
    CAST(
        CASE WHEN m.dws_customer_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.dws_customer_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'DWS customer value row count: ',
        CAST(m.dws_customer_row_cnt AS STRING),
        ', expected > 0'
    ),

    'dws_sales_summary_hive',
    'RESULT_002',
    'dws_sales_partition_not_empty',
    'BLOCK',
    CAST(
        CASE WHEN m.dws_sales_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.dws_sales_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'DWS sales summary row count: ',
        CAST(m.dws_sales_row_cnt AS STRING),
        ', expected > 0'
    ),

    'dws_customer_value_hive',
    'RESULT_003',
    'dwd_dws_customer_sales_match',
    'BLOCK',
    CAST(
        CASE
            WHEN ABS(
                m.dwd_total_sales - m.dws_customer_total_sales
            ) <= CAST(0.01 AS DECIMAL(38,6))
            THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(
        ABS(m.dwd_total_sales - m.dws_customer_total_sales)
        AS DECIMAL(38,6)
    ),
    '<= 0.01',
    CONCAT(
        'DWD total sales: ',
        CAST(m.dwd_total_sales AS STRING),
        ', DWS customer total sales: ',
        CAST(m.dws_customer_total_sales AS STRING),
        ', difference: ',
        CAST(
            ABS(m.dwd_total_sales - m.dws_customer_total_sales)
            AS STRING
        )
    ),

    'dws_sales_summary_hive',
    'RESULT_004',
    'dwd_dws_country_sales_match',
    'BLOCK',
    CAST(
        CASE
            WHEN ABS(
                m.dwd_total_sales - m.dws_country_total_sales
            ) <= CAST(0.01 AS DECIMAL(38,6))
            THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(
        ABS(m.dwd_total_sales - m.dws_country_total_sales)
        AS DECIMAL(38,6)
    ),
    '<= 0.01',
    CONCAT(
        'DWD total sales: ',
        CAST(m.dwd_total_sales AS STRING),
        ', DWS country total sales: ',
        CAST(m.dws_country_total_sales AS STRING),
        ', difference: ',
        CAST(
            ABS(m.dwd_total_sales - m.dws_country_total_sales)
            AS STRING
        )
    ),

    'ads_high_value_customer_sales_contribution_hive',
    'RESULT_005',
    'ads_contribution_partition_not_empty',
    'BLOCK',
    CAST(
        CASE WHEN m.ads_contribution_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.ads_contribution_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'ADS contribution row count: ',
        CAST(m.ads_contribution_row_cnt AS STRING),
        ', expected > 0'
    ),

    'ads_customer_level_distribution_hive',
    'RESULT_006',
    'ads_level_partition_not_empty',
    'BLOCK',
    CAST(
        CASE WHEN m.ads_level_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.ads_level_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'ADS customer level row count: ',
        CAST(m.ads_level_row_cnt AS STRING),
        ', expected > 0'
    ),

    'ads_country_sales_rank_hive',
    'RESULT_007',
    'ads_country_partition_not_empty',
    'BLOCK',
    CAST(
        CASE WHEN m.ads_country_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.ads_country_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'ADS country rank row count: ',
        CAST(m.ads_country_row_cnt AS STRING),
        ', expected > 0'
    ),

    'ads_high_value_customer_preference_hive',
    'RESULT_008',
    'ads_preference_partition_not_empty',
    'WARN',
    CAST(
        CASE WHEN m.ads_preference_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.ads_preference_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'ADS high-value preference row count: ',
        CAST(m.ads_preference_row_cnt AS STRING),
        ', expected > 0; WARN because a low-volume date may have no high-value customer'
    ),

    'ads_customer_level_distribution_hive',
    'RESULT_009',
    'ads_customer_pct_sum_near_100',
    'BLOCK',
    CAST(
        CASE
            WHEN ABS(
                m.customer_pct_sum - CAST(100 AS DECIMAL(38,6))
            ) <= CAST(0.05 AS DECIMAL(38,6))
            THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(m.customer_pct_sum AS DECIMAL(38,6)),
    '99.95 ~ 100.05',
    CONCAT(
        'Customer percentage sum: ',
        CAST(m.customer_pct_sum AS STRING),
        ', expected near 100'
    ),

    'ads_customer_level_distribution_hive',
    'RESULT_010',
    'ads_sales_pct_sum_near_100',
    'BLOCK',
    CAST(
        CASE
            WHEN ABS(
                m.sales_pct_sum - CAST(100 AS DECIMAL(38,6))
            ) <= CAST(0.05 AS DECIMAL(38,6))
            THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(m.sales_pct_sum AS DECIMAL(38,6)),
    '99.95 ~ 100.05',
    CONCAT(
        'Sales percentage sum: ',
        CAST(m.sales_pct_sum AS STRING),
        ', expected near 100'
    ),

    'ads_high_value_customer_sales_contribution_hive',
    'RESULT_011',
    'ads_contribution_pct_valid',
    'BLOCK',
    CAST(m.invalid_contribution_pct_cnt AS BIGINT),
    CAST(m.invalid_contribution_pct_cnt AS DECIMAL(38,6)),
    '= 0',
    CONCAT(
        'Invalid sales contribution percentage rows: ',
        CAST(m.invalid_contribution_pct_cnt AS STRING),
        ', expected 0'
    )

) rule_result AS
    table_name,
    rule_code,
    check_item,
    check_level,
    abnormal_cnt,
    actual_value,
    threshold_value,
    check_detail;
