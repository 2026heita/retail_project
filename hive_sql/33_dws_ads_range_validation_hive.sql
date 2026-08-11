-- =====================================================
-- File: 33_dws_ads_range_validation_hive.sql
-- Purpose: Validate DWS and ADS results for a date range
--
-- Required Hive parameters:
--   start_dt
--   end_dt
--
-- Notes:
--   1. The expected date count comes from DWD business-date partitions,
--      not from the number of natural calendar days.
--   2. High-value customer preference may be empty on low-volume dates,
--      so it is reported but not used as a blocking date-coverage gate.
-- =====================================================

WITH dwd_metrics AS (
    SELECT
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT dt) AS date_cnt,
        COALESCE(SUM(amount), 0) AS total_amount
    FROM dwd_retail_clean_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

dws_customer_metrics AS (
    SELECT
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT dt) AS date_cnt,
        COALESCE(SUM(total_spent), 0) AS total_amount
    FROM dws_customer_value_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

dws_sales_metrics AS (
    SELECT
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT dt) AS date_cnt,
        COALESCE(SUM(total_sales), 0) AS total_amount
    FROM dws_sales_summary_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

ads_contribution_metrics AS (
    SELECT
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT dt) AS date_cnt,

        COALESCE(
            SUM(
                CASE
                    WHEN sales_contribution_pct < 0
                      OR sales_contribution_pct > 100
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS invalid_pct_cnt

    FROM ads_high_value_customer_sales_contribution_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

ads_level_metrics AS (
    SELECT
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT dt) AS date_cnt
    FROM ads_customer_level_distribution_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

ads_country_metrics AS (
    SELECT
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT dt) AS date_cnt
    FROM ads_country_sales_rank_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

ads_preference_metrics AS (
    SELECT
        COUNT(*) AS row_cnt,
        COUNT(DISTINCT dt) AS date_cnt
    FROM ads_high_value_customer_preference_hive
    WHERE dt >= '${hiveconf:start_dt}'
      AND dt <= '${hiveconf:end_dt}'
),

level_pct_bad_dates AS (
    SELECT
        COUNT(*) AS bad_date_cnt
    FROM (
        SELECT
            dt
        FROM ads_customer_level_distribution_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
        GROUP BY dt
        HAVING ABS(
            COALESCE(SUM(customer_cnt_pct), 0) - 100.00
        ) > 0.05
    ) t
),

missing_dws_customer_dates AS (
    SELECT
        COUNT(*) AS missing_date_cnt
    FROM (
        SELECT DISTINCT dt
        FROM dwd_retail_clean_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) d
    LEFT JOIN (
        SELECT DISTINCT dt
        FROM dws_customer_value_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) r
      ON d.dt = r.dt
    WHERE r.dt IS NULL
),

missing_dws_sales_dates AS (
    SELECT
        COUNT(*) AS missing_date_cnt
    FROM (
        SELECT DISTINCT dt
        FROM dwd_retail_clean_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) d
    LEFT JOIN (
        SELECT DISTINCT dt
        FROM dws_sales_summary_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) r
      ON d.dt = r.dt
    WHERE r.dt IS NULL
),

missing_contribution_dates AS (
    SELECT
        COUNT(*) AS missing_date_cnt
    FROM (
        SELECT DISTINCT dt
        FROM dwd_retail_clean_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) d
    LEFT JOIN (
        SELECT DISTINCT dt
        FROM ads_high_value_customer_sales_contribution_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) r
      ON d.dt = r.dt
    WHERE r.dt IS NULL
),

missing_level_dates AS (
    SELECT
        COUNT(*) AS missing_date_cnt
    FROM (
        SELECT DISTINCT dt
        FROM dwd_retail_clean_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) d
    LEFT JOIN (
        SELECT DISTINCT dt
        FROM ads_customer_level_distribution_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) r
      ON d.dt = r.dt
    WHERE r.dt IS NULL
),

missing_country_dates AS (
    SELECT
        COUNT(*) AS missing_date_cnt
    FROM (
        SELECT DISTINCT dt
        FROM dwd_retail_clean_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) d
    LEFT JOIN (
        SELECT DISTINCT dt
        FROM ads_country_sales_rank_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) r
      ON d.dt = r.dt
    WHERE r.dt IS NULL
),

missing_preference_dates AS (
    SELECT
        COUNT(*) AS missing_date_cnt
    FROM (
        SELECT DISTINCT dt
        FROM dwd_retail_clean_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) d
    LEFT JOIN (
        SELECT DISTINCT dt
        FROM ads_high_value_customer_preference_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
    ) r
      ON d.dt = r.dt
    WHERE r.dt IS NULL
),

preference_duplicate_keys AS (
    SELECT
        COUNT(*) AS duplicate_key_cnt
    FROM (
        SELECT
            dt,
            stockcode
        FROM ads_high_value_customer_preference_hive
        WHERE dt >= '${hiveconf:start_dt}'
          AND dt <= '${hiveconf:end_dt}'
        GROUP BY dt, stockcode
        HAVING COUNT(*) > 1
    ) dup_keys
)

SELECT
    dwd.row_cnt AS dwd_row_cnt,
    dwd.date_cnt AS dwd_date_cnt,
    CAST(dwd.total_amount AS DECIMAL(18,2))
        AS dwd_total_amount,

    dc.row_cnt AS dws_customer_row_cnt,
    dc.date_cnt AS dws_customer_date_cnt,
    CAST(dc.total_amount AS DECIMAL(18,2))
        AS dws_customer_total_amount,

    ds.row_cnt AS dws_sales_row_cnt,
    ds.date_cnt AS dws_sales_date_cnt,
    CAST(ds.total_amount AS DECIMAL(18,2))
        AS dws_sales_total_amount,

    ac.row_cnt AS ads_contribution_row_cnt,
    ac.date_cnt AS ads_contribution_date_cnt,

    al.row_cnt AS ads_level_row_cnt,
    al.date_cnt AS ads_level_date_cnt,

    ag.row_cnt AS ads_country_row_cnt,
    ag.date_cnt AS ads_country_date_cnt,

    ap.row_cnt AS ads_preference_row_cnt,
    ap.date_cnt AS ads_preference_date_cnt,

    lp.bad_date_cnt AS level_pct_bad_date_cnt,
    ac.invalid_pct_cnt AS contribution_invalid_pct_cnt,

    mdc.missing_date_cnt AS missing_dws_customer_date_cnt,
    mds.missing_date_cnt AS missing_dws_sales_date_cnt,
    mac.missing_date_cnt AS missing_contribution_date_cnt,
    mal.missing_date_cnt AS missing_level_date_cnt,
    mag.missing_date_cnt AS missing_country_date_cnt,

    -- WARN only: some low-volume dates may have no high-value preference rows.
    mp.missing_date_cnt AS missing_preference_date_warn_cnt,

    -- Blocking gate: each dt+stockcode must appear at most once in preference table.
    pdk.duplicate_key_cnt AS preference_duplicate_key_cnt,

    ASSERT_TRUE(
        dwd.row_cnt > 0
    ) AS dwd_nonempty_gate,

    ASSERT_TRUE(
        dc.row_cnt > 0
    ) AS dws_customer_nonempty_gate,

    ASSERT_TRUE(
        ds.row_cnt > 0
    ) AS dws_sales_nonempty_gate,

    ASSERT_TRUE(
        ac.row_cnt > 0
    ) AS contribution_nonempty_gate,

    ASSERT_TRUE(
        al.row_cnt > 0
    ) AS level_nonempty_gate,

    ASSERT_TRUE(
        ag.row_cnt > 0
    ) AS country_nonempty_gate,

    ASSERT_TRUE(
        dc.date_cnt = dwd.date_cnt
    ) AS dws_customer_date_count_gate,

    ASSERT_TRUE(
        ds.date_cnt = dwd.date_cnt
    ) AS dws_sales_date_count_gate,

    ASSERT_TRUE(
        ac.date_cnt = dwd.date_cnt
    ) AS contribution_date_count_gate,

    ASSERT_TRUE(
        al.date_cnt = dwd.date_cnt
    ) AS level_date_count_gate,

    ASSERT_TRUE(
        ag.date_cnt = dwd.date_cnt
    ) AS country_date_count_gate,

    ASSERT_TRUE(
        mdc.missing_date_cnt = 0
    ) AS dws_customer_date_coverage_gate,

    ASSERT_TRUE(
        mds.missing_date_cnt = 0
    ) AS dws_sales_date_coverage_gate,

    ASSERT_TRUE(
        mac.missing_date_cnt = 0
    ) AS contribution_date_coverage_gate,

    ASSERT_TRUE(
        mal.missing_date_cnt = 0
    ) AS level_date_coverage_gate,

    ASSERT_TRUE(
        mag.missing_date_cnt = 0
    ) AS country_date_coverage_gate,

    ASSERT_TRUE(
        ABS(dwd.total_amount - dc.total_amount) <= 0.01
    ) AS customer_amount_gate,

    ASSERT_TRUE(
        ABS(dwd.total_amount - ds.total_amount) <= 0.01
    ) AS sales_amount_gate,

    ASSERT_TRUE(
        lp.bad_date_cnt = 0
    ) AS level_pct_gate,

    ASSERT_TRUE(
        ac.invalid_pct_cnt = 0
    ) AS contribution_pct_gate,

    ASSERT_TRUE(
        pdk.duplicate_key_cnt = 0
    ) AS preference_duplicate_key_gate

FROM dwd_metrics dwd
CROSS JOIN dws_customer_metrics dc
CROSS JOIN dws_sales_metrics ds
CROSS JOIN ads_contribution_metrics ac
CROSS JOIN ads_level_metrics al
CROSS JOIN ads_country_metrics ag
CROSS JOIN ads_preference_metrics ap
CROSS JOIN level_pct_bad_dates lp
CROSS JOIN missing_dws_customer_dates mdc
CROSS JOIN missing_dws_sales_dates mds
CROSS JOIN missing_contribution_dates mac
CROSS JOIN missing_level_dates mal
CROSS JOIN missing_country_dates mag
CROSS JOIN missing_preference_dates mp
CROSS JOIN preference_duplicate_keys pdk;