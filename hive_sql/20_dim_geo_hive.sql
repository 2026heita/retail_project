-- =====================================================
-- 文件名: 20_dim_geo_hive.sql
-- 功能: 创建星型模型地理维度表 dim_geo
-- 说明:
--   1. 基于 DWD 当前分区中的国家字段生成地理维度快照
--   2. geo_id 使用 country 生成稳定代理键
--   3. 使用 dt 分区保留每日地理维度快照
-- =====================================================

CREATE TABLE IF NOT EXISTS dim_geo (
    geo_id STRING COMMENT '地理维度代理键',
    country STRING COMMENT '国家名称'
)
COMMENT '星型模型地理维度表（每日快照）'
PARTITIONED BY (dt STRING COMMENT '业务日期分区')
STORED AS ORC;
