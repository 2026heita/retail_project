-- =====================================================
-- 文件名: 13_data_quality_check.sql
-- 文件属性: 长期保留，提交代码仓库
-- 功能: MySQL DWD / DWS / ADS 核心数据质量门禁
--
-- 运行结果:
--   1. 输出每一项检查的实际值、规则和 PASS/FAIL
--   2. 所有检查通过时正常结束，返回码为 0
--   3. 任意检查失败时抛出 SQLSTATE 45000，
--      使调度脚本返回非零状态并写入 FAILED 日志
-- =====================================================

USE retail_project;

DROP TEMPORARY TABLE IF EXISTS tmp_retail_dq_result;

CREATE TEMPORARY TABLE tmp_retail_dq_result (
    check_order INT NOT NULL,
    check_name VARCHAR(100) NOT NULL,
    actual_value BIGINT NOT NULL,
    expected_rule VARCHAR(50) NOT NULL,
    is_pass TINYINT NOT NULL,
    PRIMARY KEY (check_order)
);


-- 1. DWD 层：清洗结果中不能残留技术异常
INSERT INTO tmp_retail_dq_result
SELECT
    1,
    'dwd_abnormal_quantity',
    COUNT(*),
    '= 0',
    CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM retail_clean2
WHERE Quantity <= 0

UNION ALL

SELECT
    2,
    'dwd_abnormal_price',
    COUNT(*),
    '= 0',
    CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM retail_clean2
WHERE Price <= 0

UNION ALL

SELECT
    3,
    'dwd_null_customer',
    COUNT(*),
    '= 0',
    CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM retail_clean2
WHERE CustomerID IS NULL

UNION ALL

SELECT
    4,
    'dwd_return_order',
    COUNT(*),
    '= 0',
    CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM retail_clean2
WHERE Invoice LIKE 'C%'

UNION ALL

-- 2. DWS 层：客户分层不能为空
SELECT
    5,
    'dws_null_customer_level',
    COUNT(*),
    '= 0',
    CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END
FROM dws_customer_value
WHERE customer_level IS NULL

UNION ALL

-- 3. ADS 层：Top10 商品结果应为 10 行
SELECT
    6,
    'ads_top10_products_row_count',
    COUNT(*),
    '= 10',
    CASE WHEN COUNT(*) = 10 THEN 1 ELSE 0 END
FROM ads_top10_products

UNION ALL

-- 4. ADS 层：核心结果表必须非空
SELECT
    7,
    'ads_repeat_purchase_summary_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_repeat_purchase_summary

UNION ALL

SELECT
    8,
    'ads_monthly_sales_trend_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_monthly_sales_trend

UNION ALL

SELECT
    9,
    'ads_monthly_sales_growth_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_monthly_sales_growth

UNION ALL

SELECT
    10,
    'ads_high_value_customers_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_high_value_customers

UNION ALL

SELECT
    11,
    'ads_country_sales_rank_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_country_sales_rank

UNION ALL

SELECT
    12,
    'ads_customer_revenue_concentration_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_customer_revenue_concentration

UNION ALL

SELECT
    13,
    'ads_country_value_analysis_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_country_value_analysis

UNION ALL

SELECT
    14,
    'ads_customer_level_distribution_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_customer_level_distribution

UNION ALL

SELECT
    15,
    'ads_product_sales_concentration_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_product_sales_concentration

UNION ALL

SELECT
    16,
    'ads_customer_order_frequency_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_customer_order_frequency

UNION ALL

SELECT
    17,
    'ads_high_value_customer_preference_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_high_value_customer_preference

UNION ALL

SELECT
    18,
    'ads_high_value_customer_order_frequency_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_high_value_customer_order_frequency

UNION ALL

SELECT
    19,
    'ads_high_value_customer_country_distribution_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_high_value_customer_country_distribution

UNION ALL

SELECT
    20,
    'ads_high_value_customer_sales_contribution_nonempty',
    COUNT(*),
    '> 0',
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END
FROM ads_high_value_customer_sales_contribution;


-- 5. 展示所有检查结果
SELECT
    check_order,
    check_name,
    actual_value,
    expected_rule,
    CASE WHEN is_pass = 1 THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM tmp_retail_dq_result
ORDER BY check_order;


-- 6. 展示总体结果
SELECT
    COUNT(*) AS total_check_cnt,
    SUM(is_pass = 1) AS passed_check_cnt,
    SUM(is_pass = 0) AS failed_check_cnt,
    CASE
        WHEN SUM(is_pass = 0) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS overall_status
FROM tmp_retail_dq_result;


-- 7. 任意检查失败时，使 mysql 客户端返回非零状态
DROP PROCEDURE IF EXISTS sp_assert_retail_data_quality;

DELIMITER $$

CREATE PROCEDURE sp_assert_retail_data_quality()
BEGIN
    DECLARE v_failed_cnt INT DEFAULT 0;
    DECLARE v_failed_names TEXT DEFAULT NULL;
    DECLARE v_error_message TEXT DEFAULT NULL;

    SELECT
        COUNT(*),
        GROUP_CONCAT(
            check_name
            ORDER BY check_order
            SEPARATOR ', '
        )
    INTO
        v_failed_cnt,
        v_failed_names
    FROM tmp_retail_dq_result
    WHERE is_pass = 0;

    IF v_failed_cnt > 0 THEN
        SET v_error_message = CONCAT(
            'Data quality gate failed: ',
            v_failed_cnt,
            ' check(s). Failed checks: ',
            COALESCE(v_failed_names, 'unknown')
        );

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_message;
    END IF;
END$$

DELIMITER ;

CALL sp_assert_retail_data_quality();

DROP PROCEDURE IF EXISTS sp_assert_retail_data_quality;
