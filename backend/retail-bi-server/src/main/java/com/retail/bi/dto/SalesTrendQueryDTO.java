package com.retail.bi.dto;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PastOrPresent;
import org.springframework.format.annotation.DateTimeFormat;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

/**
 * 销售趋势查询参数对象。
 *
 * 作用：
 * 1. 封装趋势查询的开始日期和结束日期；
 * 2. 在请求进入业务层前完成基础参数校验；
 * 3. 防止日期缺失、日期顺序错误或查询范围过大。
 */
public class SalesTrendQueryDTO {

    /**
     * 单次趋势查询最多包含的自然日数量。
     */
    private static final long MAX_RANGE_DAYS = 31L;

    /**
     * 查询开始日期。
     */
    @NotNull(message = "开始日期不能为空")
    @PastOrPresent(message = "开始日期不能晚于当前日期")
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
    private LocalDate startDate;

    /**
     * 查询结束日期。
     */
    @NotNull(message = "结束日期不能为空")
    @PastOrPresent(message = "结束日期不能晚于当前日期")
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
    private LocalDate endDate;

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

    /**
     * 校验开始日期不能晚于结束日期。
     *
     * 日期缺失时由字段上的 @NotNull 处理，
     * 避免同时产生多个重复错误。
     */
    @AssertTrue(message = "开始日期不能晚于结束日期")
    public boolean isDateOrderValid() {
        if (startDate == null || endDate == null) {
            return true;
        }

        return !startDate.isAfter(endDate);
    }

    /**
     * 校验查询范围最多包含 31 个自然日。
     *
     * 例如：
     * 2026-04-01 至 2026-05-01，
     * 首尾日期都计算在内，一共 31 天，可以查询。
     */
    @AssertTrue(message = "查询日期范围不能超过31天")
    public boolean isDateRangeWithinLimit() {
        if (startDate == null || endDate == null) {
            return true;
        }

        // 日期顺序错误交给 isDateOrderValid() 处理。
        if (startDate.isAfter(endDate)) {
            return true;
        }

        long inclusiveDays =
                ChronoUnit.DAYS.between(startDate, endDate) + 1;

        return inclusiveDays <= MAX_RANGE_DAYS;
    }
}