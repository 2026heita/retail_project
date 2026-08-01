-- ============================================================
-- 文件名：01_create_retail_bi_tables.sql
-- 功能：创建零售 BI 应用数据库和经营总览日指标表
-- 数据来源：Hive ads_sales_overview_daily_hive
-- 表粒度：一个业务日期一行
-- ============================================================

CREATE DATABASE IF NOT EXISTS retail_bi
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE retail_bi;


CREATE TABLE IF NOT EXISTS bi_sales_overview_daily (
    dt DATE NOT NULL COMMENT '业务日期',

    total_sales DECIMAL(18, 2) NOT NULL DEFAULT 0.00
        COMMENT '当日有效订单总销售额',

    total_orders BIGINT NOT NULL DEFAULT 0
        COMMENT '当日去重订单数',

    total_customers BIGINT NOT NULL DEFAULT 0
        COMMENT '当日去重客户数',

    total_quantity BIGINT NOT NULL DEFAULT 0
        COMMENT '当日商品销售件数',

    avg_order_value DECIMAL(18, 2) NOT NULL DEFAULT 0.00
        COMMENT '当日客单价：总销售额/订单数',

    source_system VARCHAR(32) NOT NULL DEFAULT 'hive_ads'
        COMMENT '数据来源系统',

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        COMMENT '首次写入时间',

    updated_at TIMESTAMP NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP
        COMMENT '最近更新时间',

    PRIMARY KEY (dt)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8mb4
COLLATE = utf8mb4_unicode_ci
COMMENT = 'BI经营总览日指标表';