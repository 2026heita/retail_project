package com.retail.bi.vo;

import java.math.BigDecimal;

/**
 * 销售概览环比变化百分比 VO。
 *
 * 作用：
 * 1. 封装五项核心指标的环比变化百分比；
 * 2. 字段名明确包含 Percent，表示返回值 12.34 是百分之十二点三四；
 * 3. 当前一日某项指标为 0 时，对应百分比为 null（避免除以 0）。
 */
public class SalesOverviewChangePercentVO {

    private BigDecimal totalSalesPercent;
    private BigDecimal totalOrdersPercent;
    private BigDecimal totalCustomersPercent;
    private BigDecimal totalQuantityPercent;
    private BigDecimal avgOrderValuePercent;

    public BigDecimal getTotalSalesPercent() {
        return totalSalesPercent;
    }

    public void setTotalSalesPercent(BigDecimal totalSalesPercent) {
        this.totalSalesPercent = totalSalesPercent;
    }

    public BigDecimal getTotalOrdersPercent() {
        return totalOrdersPercent;
    }

    public void setTotalOrdersPercent(BigDecimal totalOrdersPercent) {
        this.totalOrdersPercent = totalOrdersPercent;
    }

    public BigDecimal getTotalCustomersPercent() {
        return totalCustomersPercent;
    }

    public void setTotalCustomersPercent(BigDecimal totalCustomersPercent) {
        this.totalCustomersPercent = totalCustomersPercent;
    }

    public BigDecimal getTotalQuantityPercent() {
        return totalQuantityPercent;
    }

    public void setTotalQuantityPercent(BigDecimal totalQuantityPercent) {
        this.totalQuantityPercent = totalQuantityPercent;
    }

    public BigDecimal getAvgOrderValuePercent() {
        return avgOrderValuePercent;
    }

    public void setAvgOrderValuePercent(BigDecimal avgOrderValuePercent) {
        this.avgOrderValuePercent = avgOrderValuePercent;
    }
}
