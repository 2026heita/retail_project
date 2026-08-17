CREATE DATABASE IF NOT EXISTS retail_bi
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE retail_bi;

CREATE TABLE IF NOT EXISTS bi_sales_anomaly_daily (
    dt DATE NOT NULL COMMENT '业务日期',

    total_sales DECIMAL(18,2) NOT NULL DEFAULT 0.00
        COMMENT '当日有效订单总销售额',

    total_orders BIGINT NOT NULL DEFAULT 0
        COMMENT '当日去重订单数',

    total_customers BIGINT NOT NULL DEFAULT 0
        COMMENT '当日去重客户数',

    total_quantity BIGINT NOT NULL DEFAULT 0
        COMMENT '当日商品销售件数',

    avg_order_value DECIMAL(18,2) NOT NULL DEFAULT 0.00
        COMMENT '当日客单价',

    prev_dt DATE NULL COMMENT '上一可用业务日期',

    prev_sales DECIMAL(18,2) NULL
        COMMENT '上一可用业务日销售额',

    sales_change_pct DECIMAL(18,2) NULL
        COMMENT '销售额相对上一可用业务日变化率（百分比）',

    sales_loss_amount DECIMAL(18,2) NULL
        COMMENT '销售额变化金额；下降为正，上升为负',

    orders_change_pct DECIMAL(18,2) NULL
        COMMENT '订单数变化率（百分比）',

    customers_change_pct DECIMAL(18,2) NULL
        COMMENT '客户数变化率（百分比）',

    quantity_change_pct DECIMAL(18,2) NULL
        COMMENT '销量变化率（百分比）',

    aov_change_pct DECIMAL(18,2) NULL
        COMMENT '客单价变化率（百分比）',

    anomaly_level VARCHAR(16) NOT NULL DEFAULT 'NORMAL'
        COMMENT '异常等级',

    primary_driver VARCHAR(32) NULL
        COMMENT '主要直接驱动因素',

    source_system VARCHAR(32) NOT NULL DEFAULT 'hive_ads_anomaly'
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
COMMENT = 'BI经营异常分析日指标表';