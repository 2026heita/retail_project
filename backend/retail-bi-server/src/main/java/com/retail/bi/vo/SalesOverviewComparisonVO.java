package com.retail.bi.vo;

import java.time.LocalDate;

/**
 * 销售概览日环比对比 VO。
 *
 * 作用：
 * 1. 封装当前日与前一日的数据对比结果；
 * 2. 包含环比变化百分比；
 * 3. 当前一日数据不存在时，comparisonAvailable=false，previous 和 changePercent 为 null。
 */
public class SalesOverviewComparisonVO {

    private LocalDate date;
    private LocalDate comparisonDate;
    private boolean comparisonAvailable;
    private SalesOverviewVO current;
    private SalesOverviewVO previous;
    private SalesOverviewChangePercentVO changePercent;

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public LocalDate getComparisonDate() {
        return comparisonDate;
    }

    public void setComparisonDate(LocalDate comparisonDate) {
        this.comparisonDate = comparisonDate;
    }

    public boolean isComparisonAvailable() {
        return comparisonAvailable;
    }

    public void setComparisonAvailable(boolean comparisonAvailable) {
        this.comparisonAvailable = comparisonAvailable;
    }

    public SalesOverviewVO getCurrent() {
        return current;
    }

    public void setCurrent(SalesOverviewVO current) {
        this.current = current;
    }

    public SalesOverviewVO getPrevious() {
        return previous;
    }

    public void setPrevious(SalesOverviewVO previous) {
        this.previous = previous;
    }

    public SalesOverviewChangePercentVO getChangePercent() {
        return changePercent;
    }

    public void setChangePercent(SalesOverviewChangePercentVO changePercent) {
        this.changePercent = changePercent;
    }
}
