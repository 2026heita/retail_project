package com.retail.bi.controller;

import com.retail.bi.common.ApiResponse;
import com.retail.bi.dto.DashboardQueryDTO;
import com.retail.bi.dto.SalesTrendQueryDTO;
import com.retail.bi.filter.RequestIdFilter;
import com.retail.bi.service.SalesOverviewMetricService;
import com.retail.bi.vo.SalesOverviewVO;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 销售概览接口控制器。
 *
 * 作用：
 * 1. 接收销售概览与趋势查询参数；
 * 2. 调用指标服务查询 MySQL 应用层指标；
 * 3. 返回统一响应结构和 requestId。
 */
@RestController
@RequestMapping("/api/v1/dashboard")
public class SalesOverviewController {

    private final SalesOverviewMetricService salesOverviewMetricService;

    public SalesOverviewController(
            SalesOverviewMetricService salesOverviewMetricService) {
        this.salesOverviewMetricService = salesOverviewMetricService;
    }

    /**
     * 查询指定业务日期的销售概览指标。
     *
     * 请求示例：
     * GET /api/v1/dashboard/overview?date=2026-04-08
     */
    @GetMapping("/overview")
    public ResponseEntity<ApiResponse<SalesOverviewVO>> getOverview(
            @Valid @ModelAttribute DashboardQueryDTO query,
            HttpServletRequest request) {

        SalesOverviewVO result =
                salesOverviewMetricService.getByDate(query.getDate());

        return ResponseEntity.ok(
                ApiResponse.success(result, getRequestId(request))
        );
    }

    /**
     * 查询指定日期范围内的每日销售趋势。
     *
     * 请求示例：
     * GET /api/v1/dashboard/overview/trend
     *     ?startDate=2026-04-01
     *     &endDate=2026-04-08
     */
    @GetMapping("/overview/trend")
    public ResponseEntity<ApiResponse<List<SalesOverviewVO>>> getTrend(
            @Valid @ModelAttribute SalesTrendQueryDTO query,
            HttpServletRequest request) {

        List<SalesOverviewVO> result =
                salesOverviewMetricService.getTrend(
                        query.getStartDate(),
                        query.getEndDate()
                );

        return ResponseEntity.ok(
                ApiResponse.success(result, getRequestId(request))
        );
    }

    /**
     * 获取当前请求的 requestId。
     */
    private String getRequestId(HttpServletRequest request) {
        return (String) request.getAttribute(
                RequestIdFilter.REQUEST_ID
        );
    }
}