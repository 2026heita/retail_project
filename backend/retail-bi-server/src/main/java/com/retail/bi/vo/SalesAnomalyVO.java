package com.retail.bi.vo;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * 经营异常查询返回对象。
 *
 * 销售额为核心结果指标；
 * 订单数与客单价用于直接驱动解释；
 * 客户数与销量作为辅助经营指标。
 */
public class SalesAnomalyVO {

    private LocalDate dt;
    private BigDecimal totalSales;
    private Long totalOrders;
    private Long totalCustomers;
    private Long totalQuantity;
    private BigDecimal avgOrderValue;

    private LocalDate prevDt;
    private BigDecimal prevSales;

    private BigDecimal salesChangePct;
    private BigDecimal salesLossAmount;
    private BigDecimal ordersChangePct;
    private BigDecimal customersChangePct;
    private BigDecimal quantityChangePct;
    private BigDecimal aovChangePct;

    private String anomalyLevel;
    private String primaryDriver;
    private String sourceSystem;

    public LocalDate getDt() {
        return dt;
    }

    public void setDt(LocalDate dt) {
        this.dt = dt;
    }

    public BigDecimal getTotalSales() {
        return totalSales;
    }

    public void setTotalSales(BigDecimal totalSales) {
        this.totalSales = totalSales;
    }

    public Long getTotalOrders() {
        return totalOrders;
    }

    public void setTotalOrders(Long totalOrders) {
        this.totalOrders = totalOrders;
    }

    public Long getTotalCustomers() {
        return totalCustomers;
    }

    public void setTotalCustomers(Long totalCustomers) {
        this.totalCustomers = totalCustomers;
    }

    public Long getTotalQuantity() {
        return totalQuantity;
    }

    public void setTotalQuantity(Long totalQuantity) {
        this.totalQuantity = totalQuantity;
    }

    public BigDecimal getAvgOrderValue() {
        return avgOrderValue;
    }

    public void setAvgOrderValue(BigDecimal avgOrderValue) {
        this.avgOrderValue = avgOrderValue;
    }

    public LocalDate getPrevDt() {
        return prevDt;
    }

    public void setPrevDt(LocalDate prevDt) {
        this.prevDt = prevDt;
    }

    public BigDecimal getPrevSales() {
        return prevSales;
    }

    public void setPrevSales(BigDecimal prevSales) {
        this.prevSales = prevSales;
    }

    public BigDecimal getSalesChangePct() {
        return salesChangePct;
    }

    public void setSalesChangePct(BigDecimal salesChangePct) {
        this.salesChangePct = salesChangePct;
    }

    public BigDecimal getSalesLossAmount() {
        return salesLossAmount;
    }

    public void setSalesLossAmount(BigDecimal salesLossAmount) {
        this.salesLossAmount = salesLossAmount;
    }

    public BigDecimal getOrdersChangePct() {
        return ordersChangePct;
    }

    public void setOrdersChangePct(BigDecimal ordersChangePct) {
        this.ordersChangePct = ordersChangePct;
    }

    public BigDecimal getCustomersChangePct() {
        return customersChangePct;
    }

    public void setCustomersChangePct(BigDecimal customersChangePct) {
        this.customersChangePct = customersChangePct;
    }

    public BigDecimal getQuantityChangePct() {
        return quantityChangePct;
    }

    public void setQuantityChangePct(BigDecimal quantityChangePct) {
        this.quantityChangePct = quantityChangePct;
    }

    public BigDecimal getAovChangePct() {
        return aovChangePct;
    }

    public void setAovChangePct(BigDecimal aovChangePct) {
        this.aovChangePct = aovChangePct;
    }

    public String getAnomalyLevel() {
        return anomalyLevel;
    }

    public void setAnomalyLevel(String anomalyLevel) {
        this.anomalyLevel = anomalyLevel;
    }

    public String getPrimaryDriver() {
        return primaryDriver;
    }

    public void setPrimaryDriver(String primaryDriver) {
        this.primaryDriver = primaryDriver;
    }

    public String getSourceSystem() {
        return sourceSystem;
    }

    public void setSourceSystem(String sourceSystem) {
        this.sourceSystem = sourceSystem;
    }
}
