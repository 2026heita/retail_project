package com.retail.bi.dto;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PastOrPresent;

import java.time.LocalDate;

/**
 * 销售趋势查询参数对象。
 *
 * 作用：
 * 1. 封装销售趋势的开始日期和结束日期；
 * 2. 在请求进入业务层前完成基础参数校验；
 * 3. 防止日期缺失、查询未来日期或日期范围颠倒。
 */
public class SalesTrendQueryDTO {

    /**
     * 查询开始日期。
     */
    @NotNull(message = "开始日期不能为空")
    @PastOrPresent(message = "开始日期不能晚于当前日期")
    private LocalDate startDate;

    /**
     * 查询结束日期。
     */
    @NotNull(message = "结束日期不能为空")
    @PastOrPresent(message = "结束日期不能晚于当前日期")
    private LocalDate endDate;

    /**
     * 校验开始日期不能晚于结束日期。
     *
     * 日期为空时交给 @NotNull 处理，避免返回重复错误。
     */
    @AssertTrue(message = "开始日期不能晚于结束日期")
    public boolean isDateRangeValid() {
        return startDate == null
                || endDate == null
                || !startDate.isAfter(endDate);
    }

    public LocalDate getStartDate() {
        return startDate;
    }

    public void setStartDate(LocalDate startDate) {
        this.startDate = startDate;
    }

    public LocalDate getEndDate() {
        return endDate;
    }

    public void setEndDate(LocalDate endDate) {
        this.endDate = endDate;
    }
}