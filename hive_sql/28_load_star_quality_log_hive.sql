-- =====================================================
-- 文件名: 28_load_star_quality_log_hive.sql
-- 功能:
--   1. 校验星型模型维表、事实表和汇总表
--   2. 检查 SCD2 版本、维度唯一性、事实完整性和金额守恒
--   3. 将结果写入 star_quality_log_hive
-- =====================================================

CREATE TABLE IF NOT EXISTS star_quality_log_hive (
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
COMMENT 'Hive星型模型质量检查日志表'
PARTITIONED BY (dt STRING COMMENT '业务日期')
STORED AS ORC;


WITH dwd_metrics AS (
    SELECT
        COUNT(1) AS dwd_row_cnt,
        CAST(
            ROUND(COALESCE(SUM(amount), 0), 2)
            AS DECIMAL(38,6)
        ) AS dwd_total_amount
    FROM dwd_retail_clean_hive
    WHERE dt = '${hiveconf:bizdate}'
),

dim_user_metrics AS (
    SELECT
        COUNT(1) AS dim_user_row_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN start_date IS NULL
                      OR end_date IS NULL
                      OR start_date > end_date
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS invalid_date_range_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN is_current = TRUE
                     AND end_date <> CAST('9999-12-31' AS DATE)
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS invalid_current_end_date_cnt

    FROM dim_user
    WHERE dt = '${hiveconf:bizdate}'
),

duplicate_current_user_metrics AS (
    SELECT
        COUNT(1) AS duplicate_current_customer_cnt
    FROM (
        SELECT
            customerid
        FROM dim_user
        WHERE dt = '${hiveconf:bizdate}'
          AND is_current = TRUE
        GROUP BY customerid
        HAVING COUNT(1) > 1
    ) t
),

dim_product_metrics AS (
    SELECT
        COUNT(1) AS dim_product_row_cnt,
        COUNT(DISTINCT stockcode) AS distinct_stockcode_cnt
    FROM dim_product
    WHERE dt = '${hiveconf:bizdate}'
),

dim_geo_metrics AS (
    SELECT
        COUNT(1) AS dim_geo_row_cnt,
        COUNT(DISTINCT country) AS distinct_country_cnt
    FROM dim_geo
    WHERE dt = '${hiveconf:bizdate}'
),

dim_date_metrics AS (
    SELECT
        COUNT(1) AS dim_date_row_cnt,
        COUNT(DISTINCT date_id) AS distinct_date_id_cnt
    FROM dim_date
    WHERE dt = '${hiveconf:bizdate}'
),

fact_metrics AS (
    SELECT
        COUNT(1) AS fact_row_cnt,
        COUNT(DISTINCT order_line_id) AS distinct_order_line_id_cnt,
        COUNT(DISTINCT user_id) AS fact_user_cnt,

        CAST(
            ROUND(COALESCE(SUM(amount), 0), 2)
            AS DECIMAL(38,6)
        ) AS fact_total_amount

    FROM fact_order
    WHERE dt = '${hiveconf:bizdate}'
),

star_dws_metrics AS (
    SELECT
        COUNT(1) AS star_dws_row_cnt,

        CAST(
            ROUND(COALESCE(SUM(total_amount), 0), 2)
            AS DECIMAL(38,6)
        ) AS star_dws_total_amount

    FROM dws_customer_value_star_hive
    WHERE dt = '${hiveconf:bizdate}'
),

all_metrics AS (
    SELECT
        dwd.dwd_row_cnt,
        dwd.dwd_total_amount,

        du.dim_user_row_cnt,
        du.invalid_date_range_cnt,
        du.invalid_current_end_date_cnt,
        duc.duplicate_current_customer_cnt,

        dp.dim_product_row_cnt,
        dp.distinct_stockcode_cnt,

        dg.dim_geo_row_cnt,
        dg.distinct_country_cnt,

        dd.dim_date_row_cnt,
        dd.distinct_date_id_cnt,

        f.fact_row_cnt,
        f.distinct_order_line_id_cnt,
        f.fact_user_cnt,
        f.fact_total_amount,

        sd.star_dws_row_cnt,
        sd.star_dws_total_amount

    FROM dwd_metrics dwd
    CROSS JOIN dim_user_metrics du
    CROSS JOIN duplicate_current_user_metrics duc
    CROSS JOIN dim_product_metrics dp
    CROSS JOIN dim_geo_metrics dg
    CROSS JOIN dim_date_metrics dd
    CROSS JOIN fact_metrics f
    CROSS JOIN star_dws_metrics sd
)

INSERT OVERWRITE TABLE star_quality_log_hive
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
    12,

    'dim_user',
    'STAR_001',
    'dim_user_partition_not_empty',
    'BLOCK',
    CAST(
        CASE WHEN m.dim_user_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.dim_user_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'dim_user row count: ',
        CAST(m.dim_user_row_cnt AS STRING),
        ', expected > 0'
    ),

    'dim_user',
    'STAR_002',
    'one_current_version_per_customer',
    'BLOCK',
    CAST(m.duplicate_current_customer_cnt AS BIGINT),
    CAST(m.duplicate_current_customer_cnt AS DECIMAL(38,6)),
    '= 0',
    CONCAT(
        'Customers with multiple current versions: ',
        CAST(m.duplicate_current_customer_cnt AS STRING),
        ', expected 0'
    ),

    'dim_user',
    'STAR_003',
    'scd2_date_range_valid',
    'BLOCK',
    CAST(m.invalid_date_range_cnt AS BIGINT),
    CAST(m.invalid_date_range_cnt AS DECIMAL(38,6)),
    '= 0',
    CONCAT(
        'Invalid SCD2 date ranges: ',
        CAST(m.invalid_date_range_cnt AS STRING),
        ', expected 0'
    ),

    'dim_user',
    'STAR_004',
    'current_version_end_date_valid',
    'BLOCK',
    CAST(m.invalid_current_end_date_cnt AS BIGINT),
    CAST(m.invalid_current_end_date_cnt AS DECIMAL(38,6)),
    '= 0',
    CONCAT(
        'Current versions whose end_date is not 9999-12-31: ',
        CAST(m.invalid_current_end_date_cnt AS STRING),
        ', expected 0'
    ),

    'dim_product',
    'STAR_005',
    'product_business_key_unique',
    'BLOCK',
    CAST(
        m.dim_product_row_cnt - m.distinct_stockcode_cnt
        AS BIGINT
    ),
    CAST(
        m.dim_product_row_cnt - m.distinct_stockcode_cnt
        AS DECIMAL(38,6)
    ),
    '= 0',
    CONCAT(
        'Product duplicate rows by stockcode: ',
        CAST(
            m.dim_product_row_cnt - m.distinct_stockcode_cnt
            AS STRING
        ),
        ', expected 0'
    ),

    'dim_geo',
    'STAR_006',
    'geo_business_key_unique',
    'BLOCK',
    CAST(
        m.dim_geo_row_cnt - m.distinct_country_cnt
        AS BIGINT
    ),
    CAST(
        m.dim_geo_row_cnt - m.distinct_country_cnt
        AS DECIMAL(38,6)
    ),
    '= 0',
    CONCAT(
        'Geo duplicate rows by country: ',
        CAST(
            m.dim_geo_row_cnt - m.distinct_country_cnt
            AS STRING
        ),
        ', expected 0'
    ),

    'dim_date',
    'STAR_007',
    'date_business_key_unique',
    'BLOCK',
    CAST(
        m.dim_date_row_cnt - m.distinct_date_id_cnt
        AS BIGINT
    ),
    CAST(
        m.dim_date_row_cnt - m.distinct_date_id_cnt
        AS DECIMAL(38,6)
    ),
    '= 0',
    CONCAT(
        'Date duplicate rows by date_id: ',
        CAST(
            m.dim_date_row_cnt - m.distinct_date_id_cnt
            AS STRING
        ),
        ', expected 0'
    ),

    'fact_order',
    'STAR_008',
    'fact_partition_not_empty',
    'BLOCK',
    CAST(
        CASE WHEN m.fact_row_cnt > 0 THEN 0 ELSE 1 END
        AS BIGINT
    ),
    CAST(m.fact_row_cnt AS DECIMAL(38,6)),
    '> 0',
    CONCAT(
        'fact_order row count: ',
        CAST(m.fact_row_cnt AS STRING),
        ', expected > 0'
    ),

    'fact_order',
    'STAR_009',
    'dwd_fact_row_count_match',
    'BLOCK',
    CAST(
        CASE
            WHEN m.dwd_row_cnt = m.fact_row_cnt THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(
        ABS(m.dwd_row_cnt - m.fact_row_cnt)
        AS DECIMAL(38,6)
    ),
    '= 0',
    CONCAT(
        'DWD rows: ',
        CAST(m.dwd_row_cnt AS STRING),
        ', fact rows: ',
        CAST(m.fact_row_cnt AS STRING),
        ', difference: ',
        CAST(ABS(m.dwd_row_cnt - m.fact_row_cnt) AS STRING)
    ),

    'fact_order',
    'STAR_010',
    'dwd_fact_amount_match',
    'BLOCK',
    CAST(
        CASE
            WHEN ABS(
                m.dwd_total_amount - m.fact_total_amount
            ) <= CAST(0.01 AS DECIMAL(38,6))
            THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(
        ABS(m.dwd_total_amount - m.fact_total_amount)
        AS DECIMAL(38,6)
    ),
    '<= 0.01',
    CONCAT(
        'DWD amount: ',
        CAST(m.dwd_total_amount AS STRING),
        ', fact amount: ',
        CAST(m.fact_total_amount AS STRING),
        ', difference: ',
        CAST(
            ABS(m.dwd_total_amount - m.fact_total_amount)
            AS STRING
        )
    ),

    'fact_order',
    'STAR_011',
    'order_line_id_unique',
    'BLOCK',
    CAST(
        m.fact_row_cnt - m.distinct_order_line_id_cnt
        AS BIGINT
    ),
    CAST(
        m.fact_row_cnt - m.distinct_order_line_id_cnt
        AS DECIMAL(38,6)
    ),
    '= 0',
    CONCAT(
        'Duplicate fact order_line_id rows: ',
        CAST(
            m.fact_row_cnt - m.distinct_order_line_id_cnt
            AS STRING
        ),
        ', expected 0'
    ),

    'dws_customer_value_star_hive',
    'STAR_012',
    'fact_star_dws_match',
    'BLOCK',
    CAST(
        CASE
            WHEN m.star_dws_row_cnt = m.fact_user_cnt
             AND ABS(
                    m.star_dws_total_amount - m.fact_total_amount
                 ) <= CAST(0.01 AS DECIMAL(38,6))
            THEN 0
            ELSE 1
        END AS BIGINT
    ),
    CAST(
        ABS(m.star_dws_total_amount - m.fact_total_amount)
        AS DECIMAL(38,6)
    ),
    'row count = fact distinct users and amount difference <= 0.01',
    CONCAT(
        'Fact distinct users: ',
        CAST(m.fact_user_cnt AS STRING),
        ', star DWS rows: ',
        CAST(m.star_dws_row_cnt AS STRING),
        ', fact amount: ',
        CAST(m.fact_total_amount AS STRING),
        ', star DWS amount: ',
        CAST(m.star_dws_total_amount AS STRING)
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
