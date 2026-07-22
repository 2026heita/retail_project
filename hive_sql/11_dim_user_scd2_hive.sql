-- =====================================================
-- 文件名: 11_dim_user_scd2_hive.sql
-- 功能: 创建星型模型 SCD2 用户维度表 dim_user
-- 说明:
--   1. customerid 是用户业务键
--   2. country 是需要保留历史变化的缓慢变化属性
--   3. user_id 是每个历史版本的代理键
--   4. start_date / end_date 表示版本有效区间
--   5. is_current 标识当前有效版本
--   6. 每个 dt 分区保存截至当天的完整 SCD2 历史快照
-- =====================================================

CREATE TABLE IF NOT EXISTS dim_user (
    user_id STRING COMMENT '用户维度版本代理键',
    customerid STRING COMMENT '客户ID（业务键）',
    country STRING COMMENT '客户所在国家（缓慢变化属性）',
    start_date DATE COMMENT '当前版本生效开始日期',
    end_date DATE COMMENT '当前版本生效结束日期',
    is_current BOOLEAN COMMENT '是否为当前有效版本'
)
COMMENT '星型模型用户维度表（每日完整快照式SCD2）'
PARTITIONED BY (
    dt STRING COMMENT '截至该业务日期的完整SCD2快照分区'
)
STORED AS ORC;
