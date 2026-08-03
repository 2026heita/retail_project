package com.retail.bi.controller;

import com.retail.bi.common.ApiResponse;
import com.retail.bi.service.SalesOverviewMetricService;
import com.retail.bi.vo.SalesOverviewChangePercentVO;
import com.retail.bi.vo.SalesOverviewComparisonVO;
import com.retail.bi.vo.SalesOverviewVO;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Collections;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * SalesOverviewController 基础自动化测试。
 *
 * 测试范围：
 * 1. 参数校验（缺失、格式错误、业务规则）
 * 2. 响应结构（ApiResponse 字段、requestId 存在性）
 * 3. 不连接真实数据库，使用 MockMvc + Mockito
 */
@WebMvcTest(SalesOverviewController.class)
class SalesOverviewControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private SalesOverviewMetricService salesOverviewMetricService;

    // ==================== /api/v1/dashboard/overview ====================

    @Test
    @DisplayName("GET /overview - 缺少 date 参数应返回 400")
    void getOverview_missingDate_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview - date 格式错误应返回 400")
    void getOverview_invalidDateFormat_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview")
                        .param("date", "invalid-date"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview - date 为未来日期应返回 400")
    void getOverview_futureDate_returns400() throws Exception {
        LocalDate futureDate = LocalDate.now().plusDays(1);
        mockMvc.perform(get("/api/v1/dashboard/overview")
                        .param("date", futureDate.toString()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview - 正常请求应返回 200 和 ApiResponse 结构")
    void getOverview_validRequest_returns200() throws Exception {
        // Given
        LocalDate validDate = LocalDate.of(2026, 4, 8);
        SalesOverviewVO mockVO = new SalesOverviewVO();
        mockVO.setDt(validDate);
        mockVO.setTotalSales(new java.math.BigDecimal("1000.00"));
        mockVO.setTotalOrders(10L);
        mockVO.setTotalCustomers(5L);
        mockVO.setTotalQuantity(20L);
        mockVO.setAvgOrderValue(new java.math.BigDecimal("100.00"));
        mockVO.setSourceSystem("test");

        when(salesOverviewMetricService.getByDate(eq(validDate))).thenReturn(mockVO);

        // When & Then
        mockMvc.perform(get("/api/v1/dashboard/overview")
                        .param("date", validDate.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.message").value("success"))
                .andExpect(jsonPath("$.data").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    // ==================== /api/v1/dashboard/overview/trend ====================

    @Test
    @DisplayName("GET /overview/trend - 缺少 startDate 应返回 400")
    void getTrend_missingStartDate_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview/trend")
                        .param("endDate", "2026-04-08"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/trend - 缺少 endDate 应返回 400")
    void getTrend_missingEndDate_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview/trend")
                        .param("startDate", "2026-04-01"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/trend - 日期格式错误应返回 400")
    void getTrend_invalidDateFormat_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview/trend")
                        .param("startDate", "invalid")
                        .param("endDate", "2026-04-08"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/trend - startDate 晚于 endDate 应返回 400")
    void getTrend_startDateAfterEndDate_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview/trend")
                        .param("startDate", "2026-04-10")
                        .param("endDate", "2026-04-01"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/trend - 查询范围超过 31 天应返回 400")
    void getTrend_rangeExceeds31Days_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview/trend")
                        .param("startDate", "2026-03-01")
                        .param("endDate", "2026-04-02")) // 32 天
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/trend - 包含未来日期应返回 400")
    void getTrend_futureDate_returns400() throws Exception {
        LocalDate futureDate = LocalDate.now().plusDays(1);
        mockMvc.perform(get("/api/v1/dashboard/overview/trend")
                        .param("startDate", "2026-04-01")
                        .param("endDate", futureDate.toString()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/trend - 正常请求应返回 200 和 ApiResponse 结构")
    void getTrend_validRequest_returns200() throws Exception {
        // Given
        LocalDate startDate = LocalDate.of(2026, 4, 1);
        LocalDate endDate = LocalDate.of(2026, 4, 8);
        SalesOverviewVO mockVO = new SalesOverviewVO();
        mockVO.setDt(startDate);
        mockVO.setTotalSales(new java.math.BigDecimal("1000.00"));
        mockVO.setTotalOrders(10L);

        when(salesOverviewMetricService.getTrend(eq(startDate), eq(endDate)))
                .thenReturn(Collections.singletonList(mockVO));

        // When & Then
        mockMvc.perform(get("/api/v1/dashboard/overview/trend")
                        .param("startDate", startDate.toString())
                        .param("endDate", endDate.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.message").value("success"))
                .andExpect(jsonPath("$.data").isArray())
                .andExpect(jsonPath("$.requestId").exists());
    }

    // ==================== /api/v1/dashboard/overview/comparison ====================

    @Test
    @DisplayName("GET /overview/comparison - 缺少 date 参数应返回 400")
    void getComparison_missingDate_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview/comparison"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/comparison - date 格式错误应返回 400")
    void getComparison_invalidDateFormat_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/overview/comparison")
                        .param("date", "invalid-date"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/comparison - date 为未来日期应返回 400")
    void getComparison_futureDate_returns400() throws Exception {
        LocalDate futureDate = LocalDate.now().plusDays(1);
        mockMvc.perform(get("/api/v1/dashboard/overview/comparison")
                        .param("date", futureDate.toString()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/comparison - 正常请求应返回 200 和完整响应结构")
    void getComparison_validRequest_returns200() throws Exception {
        // Given
        LocalDate validDate = LocalDate.of(2026, 4, 8);
        LocalDate comparisonDate = LocalDate.of(2026, 4, 7);

        SalesOverviewVO currentVO = new SalesOverviewVO();
        currentVO.setDt(validDate);
        currentVO.setTotalSales(new BigDecimal("1000.00"));
        currentVO.setTotalOrders(10L);
        currentVO.setTotalCustomers(5L);
        currentVO.setTotalQuantity(20L);
        currentVO.setAvgOrderValue(new BigDecimal("100.00"));
        currentVO.setSourceSystem("test");

        SalesOverviewVO previousVO = new SalesOverviewVO();
        previousVO.setDt(comparisonDate);
        previousVO.setTotalSales(new BigDecimal("900.00"));
        previousVO.setTotalOrders(9L);
        previousVO.setTotalCustomers(4L);
        previousVO.setTotalQuantity(18L);
        previousVO.setAvgOrderValue(new BigDecimal("100.00"));
        previousVO.setSourceSystem("test");

        SalesOverviewChangePercentVO changePercentVO = new SalesOverviewChangePercentVO();
        changePercentVO.setTotalSalesPercent(new BigDecimal("11.11"));
        changePercentVO.setTotalOrdersPercent(new BigDecimal("11.11"));
        changePercentVO.setTotalCustomersPercent(new BigDecimal("25.00"));
        changePercentVO.setTotalQuantityPercent(new BigDecimal("11.11"));
        changePercentVO.setAvgOrderValuePercent(new BigDecimal("0.00"));

        SalesOverviewComparisonVO comparisonVO = new SalesOverviewComparisonVO();
        comparisonVO.setDate(validDate);
        comparisonVO.setComparisonDate(comparisonDate);
        comparisonVO.setComparisonAvailable(true);
        comparisonVO.setCurrent(currentVO);
        comparisonVO.setPrevious(previousVO);
        comparisonVO.setChangePercent(changePercentVO);

        when(salesOverviewMetricService.getComparison(eq(validDate))).thenReturn(comparisonVO);

        // When & Then
        mockMvc.perform(get("/api/v1/dashboard/overview/comparison")
                        .param("date", validDate.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.message").value("success"))
                .andExpect(jsonPath("$.data").exists())
                .andExpect(jsonPath("$.data.date").value(validDate.toString()))
                .andExpect(jsonPath("$.data.comparisonDate").value(comparisonDate.toString()))
                .andExpect(jsonPath("$.data.comparisonAvailable").value(true))
                .andExpect(jsonPath("$.data.current").exists())
                .andExpect(jsonPath("$.data.previous").exists())
                .andExpect(jsonPath("$.data.changePercent").exists())
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /overview/comparison - 前一日数据不存在应返回 200 和 comparisonAvailable=false")
    void getComparison_previousDataNotAvailable_returns200() throws Exception {
        // Given
        LocalDate validDate = LocalDate.of(2026, 4, 8);
        LocalDate comparisonDate = LocalDate.of(2026, 4, 7);

        SalesOverviewVO currentVO = new SalesOverviewVO();
        currentVO.setDt(validDate);
        currentVO.setTotalSales(new BigDecimal("1000.00"));
        currentVO.setTotalOrders(10L);
        currentVO.setTotalCustomers(5L);
        currentVO.setTotalQuantity(20L);
        currentVO.setAvgOrderValue(new BigDecimal("100.00"));
        currentVO.setSourceSystem("test");

        SalesOverviewComparisonVO comparisonVO = new SalesOverviewComparisonVO();
        comparisonVO.setDate(validDate);
        comparisonVO.setComparisonDate(comparisonDate);
        comparisonVO.setComparisonAvailable(false);
        comparisonVO.setCurrent(currentVO);
        comparisonVO.setPrevious(null);
        comparisonVO.setChangePercent(null);

        when(salesOverviewMetricService.getComparison(eq(validDate))).thenReturn(comparisonVO);

        // When & Then
        mockMvc.perform(get("/api/v1/dashboard/overview/comparison")
                        .param("date", validDate.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data.date").value(validDate.toString()))
                .andExpect(jsonPath("$.data.comparisonDate").value(comparisonDate.toString()))
                .andExpect(jsonPath("$.data.comparisonAvailable").value(false))
                .andExpect(jsonPath("$.data.current").exists())
                .andExpect(jsonPath("$.data.previous").doesNotExist())
                .andExpect(jsonPath("$.data.changePercent").doesNotExist())
                .andExpect(jsonPath("$.requestId").exists());
    }
}
