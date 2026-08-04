package com.retail.bi.exception;

import com.retail.bi.controller.SalesOverviewController;
import com.retail.bi.filter.RequestIdFilter;
import com.retail.bi.service.SalesOverviewMetricService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * GlobalExceptionHandler 未知路由 404 测试。
 *
 * 测试范围：
 * 1. 未知根路径返回 404 和统一 ApiResponse 格式；
 * 2. 未知 API 路径返回 404 和统一 ApiResponse 格式；
 * 3. 请求携带 X-Request-Id 时，响应中返回相同的 requestId。
 *
 * 使用 @WebMvcTest 加载 Web 层上下文，
 * 确保 DispatcherServlet 能正确触发 NoResourceFoundException。
 */
@WebMvcTest(SalesOverviewController.class)
class GlobalExceptionHandlerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private SalesOverviewMetricService salesOverviewMetricService;

    // ==================== 未知根路径 ====================

    @Test
    @DisplayName("GET / - 未知根路径应返回 404 和统一错误格式")
    void getRootPath_returns404() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isNotFound())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value(404))
                .andExpect(jsonPath("$.message").value("接口不存在"))
                .andExpect(jsonPath("$.data").doesNotExist())
                .andExpect(jsonPath("$.requestId").exists());
    }

    // ==================== 未知 API 路径 ====================

    @Test
    @DisplayName("GET /api/v1/not-found - 未知 API 路径应返回 404 和统一错误格式")
    void getUnknownApiPath_returns404() throws Exception {
        mockMvc.perform(get("/api/v1/not-found"))
                .andExpect(status().isNotFound())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value(404))
                .andExpect(jsonPath("$.message").value("接口不存在"))
                .andExpect(jsonPath("$.data").doesNotExist())
                .andExpect(jsonPath("$.requestId").exists());
    }

    // ==================== X-Request-Id 传递 ====================

    @Test
    @DisplayName("未知路径携带 X-Request-Id 时，响应应返回相同的 requestId")
    void unknownPath_withRequestId_returnsSameRequestId() throws Exception {
        String customRequestId = "test-request-id-12345";

        mockMvc.perform(get("/api/v1/not-found")
                        .header(RequestIdFilter.REQUEST_ID_HEADER, customRequestId))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.requestId").value(customRequestId));
    }
}
