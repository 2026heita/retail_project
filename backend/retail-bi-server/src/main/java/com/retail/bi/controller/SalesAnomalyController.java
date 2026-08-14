package com.retail.bi.controller;

import com.retail.bi.common.ApiResponse;
import com.retail.bi.dto.SalesTrendQueryDTO;
import com.retail.bi.filter.RequestIdFilter;
import com.retail.bi.service.SalesAnomalyService;
import com.retail.bi.vo.SalesAnomalyVO;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 经营异常接口控制器。
 */
@RestController
@RequestMapping("/api/v1/dashboard")
public class SalesAnomalyController {

    private final SalesAnomalyService salesAnomalyService;

    public SalesAnomalyController(
            SalesAnomalyService salesAnomalyService) {
        this.salesAnomalyService = salesAnomalyService;
    }

    /**
     * 查询指定日期范围内的 MEDIUM / HIGH 经营异常。
     *
     * 示例：
     * GET /api/v1/dashboard/anomalies
     *     ?startDate=2010-09-01
     *     &endDate=2010-09-30
     */
    @GetMapping("/anomalies")
    public ResponseEntity<ApiResponse<List<SalesAnomalyVO>>> getAnomalies(
            @Valid @ModelAttribute SalesTrendQueryDTO query,
            HttpServletRequest request) {

        List<SalesAnomalyVO> result =
                salesAnomalyService.getAnomalies(
                        query.getStartDate(),
                        query.getEndDate()
                );

        return ResponseEntity.ok(
                ApiResponse.success(result, getRequestId(request))
        );
    }

    private String getRequestId(HttpServletRequest request) {
        return (String) request.getAttribute(
                RequestIdFilter.REQUEST_ID
        );
    }
}
