package com.retail.bi.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PastOrPresent;

import java.time.LocalDate;

/**
 * BI 看板查询参数对象。
 *
 * 作用：
 * 1. 统一封装前端查询条件；
 * 2. 避免 Controller 方法参数不断增加；
 * 3. 为后续增加时间范围、地区、分类等筛选条件提供扩展空间；
 * 4. 在进入业务层前完成基础参数校验。
 */
public class DashboardQueryDTO {

    /**
     * 查询业务日期。
     *
     * 必须传入，且不能晚于当前日期。
     */
    @NotNull(message = "查询日期不能为空")
    @PastOrPresent(message = "查询日期不能晚于当前日期")
    private LocalDate date;

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }
}