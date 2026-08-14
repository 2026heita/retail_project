package com.retail.bi.controller;

import com.retail.bi.service.SalesAnomalyService;
import com.retail.bi.vo.SalesAnomalyVO;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Collections;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(SalesAnomalyController.class)
class SalesAnomalyControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private SalesAnomalyService salesAnomalyService;

    @Test
    @DisplayName("GET /anomalies - 缺少日期参数应返回 400")
    void getAnomalies_missingDates_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard/anomalies"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /anomalies - 正常请求应返回异常列表")
    void getAnomalies_validRequest_returns200() throws Exception {
        LocalDate startDate = LocalDate.of(2010, 9, 1);
        LocalDate endDate = LocalDate.of(2010, 9, 30);

        SalesAnomalyVO anomaly = new SalesAnomalyVO();
        anomaly.setDt(LocalDate.of(2010, 9, 28));
        anomaly.setSalesChangePct(new BigDecimal("-65.11"));
        anomaly.setSalesLossAmount(new BigDecimal("75038.59"));
        anomaly.setAnomalyLevel("HIGH");
        anomaly.setPrimaryDriver("AVG_ORDER_VALUE");
        anomaly.setSourceSystem("retail_canonical_anomaly_ads");

        when(salesAnomalyService.getAnomalies(
                eq(startDate),
                eq(endDate)
        )).thenReturn(Collections.singletonList(anomaly));

        mockMvc.perform(get("/api/v1/dashboard/anomalies")
                        .param("startDate", startDate.toString())
                        .param("endDate", endDate.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.message").value("success"))
                .andExpect(jsonPath("$.data").isArray())
                .andExpect(jsonPath("$.data[0].dt").value("2010-09-28"))
                .andExpect(jsonPath("$.data[0].anomalyLevel").value("HIGH"))
                .andExpect(jsonPath("$.data[0].primaryDriver")
                        .value("AVG_ORDER_VALUE"))
                .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("GET /anomalies - 无异常应返回 200 和空数组")
    void getAnomalies_noAnomaly_returnsEmptyArray() throws Exception {
        LocalDate startDate = LocalDate.of(2010, 9, 1);
        LocalDate endDate = LocalDate.of(2010, 9, 2);

        when(salesAnomalyService.getAnomalies(
                eq(startDate),
                eq(endDate)
        )).thenReturn(Collections.emptyList());

        mockMvc.perform(get("/api/v1/dashboard/anomalies")
                        .param("startDate", startDate.toString())
                        .param("endDate", endDate.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data").isEmpty())
                .andExpect(jsonPath("$.requestId").exists());
    }
}
