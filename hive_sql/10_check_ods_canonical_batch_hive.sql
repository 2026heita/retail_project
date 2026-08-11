-- =====================================================
-- File: 10_check_ods_canonical_batch_hive.sql
-- Purpose: Validate canonical batch ingestion completeness
-- Description:
--   1. Count rows in ODS Raw, Reject, and normal ODS
--   2. Assert raw_cnt = 1067371
--   3. Assert reject_cnt = 0
--   4. Assert ods_cnt = 1067371
--   5. Assert raw_cnt = ods_cnt + reject_cnt
--   6. Assert min_dt = '2009-12-01'
--   7. Assert max_dt = '2011-12-09'
--   8. Assert COUNT(DISTINCT dt) > 0
--   9. Assert no rows outside expected date range
-- Usage:
--   hive --hiveconf batch_dt=2026-08-04 \
--        -f 10_check_ods_canonical_batch_hive.sql
-- =====================================================

WITH raw_metrics AS (
    SELECT COUNT(*) AS raw_cnt
    FROM ods_retail_raw_hive
    WHERE batch_dt = '${hiveconf:batch_dt}'
),

reject_metrics AS (
    SELECT COUNT(*) AS reject_cnt
    FROM ods_retail_reject_hive
    WHERE batch_dt = '${hiveconf:batch_dt}'
),

ods_metrics AS (
    SELECT
        COUNT(*) AS ods_cnt,
        MIN(dt) AS min_dt,
        MAX(dt) AS max_dt,
        COUNT(DISTINCT dt) AS dt_cnt
    FROM ods_retail_hive
),

outside_range_metrics AS (
    SELECT COUNT(*) AS outside_cnt
    FROM ods_retail_hive
    WHERE dt < '2009-12-01'
       OR dt > '2011-12-09'
       OR dt IS NULL
)

SELECT
    r.raw_cnt,
    j.reject_cnt,
    o.ods_cnt,
    o.min_dt,
    o.max_dt,
    o.dt_cnt,
    x.outside_cnt,
    ASSERT_TRUE(
        r.raw_cnt = 1067371
    ) AS raw_count_gate,
    ASSERT_TRUE(
        j.reject_cnt = 0
    ) AS reject_count_gate,
    ASSERT_TRUE(
        o.ods_cnt = 1067371
    ) AS ods_count_gate,
    ASSERT_TRUE(
        r.raw_cnt = o.ods_cnt + j.reject_cnt
    ) AS balance_gate,
    ASSERT_TRUE(
        o.min_dt = '2009-12-01'
    ) AS min_date_gate,
    ASSERT_TRUE(
        o.max_dt = '2011-12-09'
    ) AS max_date_gate,
    ASSERT_TRUE(
        o.dt_cnt > 0
    ) AS partition_count_gate,
    ASSERT_TRUE(
        x.outside_cnt = 0
    ) AS date_range_gate
FROM raw_metrics r
CROSS JOIN reject_metrics j
CROSS JOIN ods_metrics o
CROSS JOIN outside_range_metrics x;
