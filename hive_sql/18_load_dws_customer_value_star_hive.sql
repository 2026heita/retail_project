-- =====================================================
-- 文件名: 18_load_dws_customer_value_star_hive.sql
-- 功能: 加载星型模型客户价值当日汇总表
-- 说明:
--   1. 基于 fact_order 当前 dt 分区按用户聚合，统计当日客户价值表现
--   2. COUNT(DISTINCT order_id) 统计订单数，避免订单明细行重复放大订单量
--   3. 客户价值分层口径与主链路保持一致，但统计范围为当前 bizdate 分区
-- =====================================================

INSERT OVERWRITE TABLE dws_customer_value_star_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    f.user_id,
    COUNT(DISTINCT f.order_id) AS total_orders,
    CAST(ROUND(SUM(f.amount), 2) AS DECIMAL(14,2)) AS total_amount,
    CASE
        WHEN SUM(f.amount) >= 5000 THEN 'High Value'
        WHEN SUM(f.amount) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_level
FROM fact_order f
WHERE f.dt = '${hiveconf:bizdate}'
GROUP BY f.user_id;
