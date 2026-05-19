-- =====================================================
-- 文件名: 11_dim_user_scd2_hive.sql
-- 功能: 创建星型模型用户维度表 dim_user
-- 说明:
--   1. 基于 DWD 清洗明细生成用户维度快照
--   2. user_id 使用 customerid + country 生成稳定代理键
--   3. 保留 start_date / end_date / is_current 字段，表达简化 SCD2 思路
--   4. 使用 dt 分区保留每日维度快照，避免覆盖历史分区
-- =====================================================

CREATE TABLE IF NOT EXISTS dim_user (
    user_id STRING COMMENT '用户维度代理键',
    customerid STRING COMMENT '客户ID（原始业务键）',
    country STRING COMMENT '客户所在国家',
    start_date DATE COMMENT '维度记录生效开始日期',
    end_date DATE COMMENT '维度记录生效结束日期',
    is_current BOOLEAN COMMENT '当前有效标识'
)
COMMENT '星型模型用户维度表（简化 SCD2 + 每日快照）'
PARTITIONED BY (dt STRING COMMENT '业务日期分区')
STORED AS ORC;
