package com.retail.bi.service;

import com.retail.bi.exception.BusinessException;
import com.retail.bi.mapper.SalesOverviewMapper;
import com.retail.bi.vo.SalesOverviewComparisonVO;
import com.retail.bi.vo.SalesOverviewVO;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

/**
 * SalesOverviewMetricServiceImpl 单元测试。
 *
 * 测试范围：
 * 1. 日环比计算逻辑（五项指标）
 * 2. 前一日数据不存在的处理
 * 3. 前一日某项指标为 0 的处理（避免除以 0）
 * 4. 百分比两位小数舍入
 * 5. 当前日不存在时返回 404 业务异常
 *
 * 使用 Mockito 模拟 Mapper，不连接真实数据库。
 */
@ExtendWith(MockitoExtension.class)
class SalesOverviewMetricServiceImplTest {

    @Mock
    private SalesOverviewMapper salesOverviewMapper;

    @InjectMocks
    private SalesOverviewMetricServiceImpl salesOverviewMetricService;

    // ==================== 正常环比计算 ====================

    @Test
    @DisplayName("五项指标正常增长 - 应返回正确的百分比")
    void getComparison_normalGrowth_returnsCorrectPercent() {
        // Given
        LocalDate date = LocalDate.of(2026, 4, 8);
        LocalDate comparisonDate = LocalDate.of(2026, 4, 7);

        SalesOverviewVO current = createVO(
                date,
                new BigDecimal("1100.00"),  // totalSales
                11L,                        // totalOrders
                11L,                        // totalCustomers
                110L,                       // totalQuantity
                new BigDecimal("100.00")    // avgOrderValue
        );

        SalesOverviewVO previous = createVO(
                comparisonDate,
                new BigDecimal("1000.00"),  // totalSales
                10L,                        // totalOrders
                10L,                        // totalCustomers
                100L,                       // totalQuantity
                new BigDecimal("100.00")    // avgOrderValue
        );

        when(salesOverviewMapper.selectByDate(eq(date))).thenReturn(current);
        when(salesOverviewMapper.selectPreviousAvailable(eq(date), eq("test"))).thenReturn(previous);

        // When
        SalesOverviewComparisonVO result = salesOverviewMetricService.getComparison(date);

        // Then
        assertTrue(result.isComparisonAvailable());
        assertEquals(date, result.getDate());
        assertEquals(comparisonDate, result.getComparisonDate());
        assertNotNull(result.getCurrent());
        assertNotNull(result.getPrevious());
        assertNotNull(result.getChangePercent());

        // 验证百分比计算（10% 增长）
        assertEquals(new BigDecimal("10.00"), result.getChangePercent().getTotalSalesPercent());
        assertEquals(new BigDecimal("10.00"), result.getChangePercent().getTotalOrdersPercent());
        assertEquals(new BigDecimal("10.00"), result.getChangePercent().getTotalCustomersPercent());
        assertEquals(new BigDecimal("10.00"), result.getChangePercent().getTotalQuantityPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getAvgOrderValuePercent());
    }

    @Test
    @DisplayName("指标下降 - 应返回负数百分比")
    void getComparison_decline_returnsNegativePercent() {
        // Given
        LocalDate date = LocalDate.of(2026, 4, 8);
        LocalDate comparisonDate = LocalDate.of(2026, 4, 7);

        SalesOverviewVO current = createVO(
                date,
                new BigDecimal("900.00"),
                9L,
                9L,
                90L,
                new BigDecimal("100.00")
        );

        SalesOverviewVO previous = createVO(
                comparisonDate,
                new BigDecimal("1000.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        when(salesOverviewMapper.selectByDate(eq(date))).thenReturn(current);
        when(salesOverviewMapper.selectPreviousAvailable(eq(date), eq("test"))).thenReturn(previous);

        // When
        SalesOverviewComparisonVO result = salesOverviewMetricService.getComparison(date);

        // Then
        assertTrue(result.isComparisonAvailable());
        assertEquals(new BigDecimal("-10.00"), result.getChangePercent().getTotalSalesPercent());
        assertEquals(new BigDecimal("-10.00"), result.getChangePercent().getTotalOrdersPercent());
        assertEquals(new BigDecimal("-10.00"), result.getChangePercent().getTotalCustomersPercent());
        assertEquals(new BigDecimal("-10.00"), result.getChangePercent().getTotalQuantityPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getAvgOrderValuePercent());
    }

    @Test
    @DisplayName("指标不变 - 应返回 0.00")
    void getComparison_noChange_returnsZeroPercent() {
        // Given
        LocalDate date = LocalDate.of(2026, 4, 8);
        LocalDate comparisonDate = LocalDate.of(2026, 4, 7);

        SalesOverviewVO current = createVO(
                date,
                new BigDecimal("1000.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        SalesOverviewVO previous = createVO(
                comparisonDate,
                new BigDecimal("1000.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        when(salesOverviewMapper.selectByDate(eq(date))).thenReturn(current);
        when(salesOverviewMapper.selectPreviousAvailable(eq(date), eq("test"))).thenReturn(previous);

        // When
        SalesOverviewComparisonVO result = salesOverviewMetricService.getComparison(date);

        // Then
        assertTrue(result.isComparisonAvailable());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getTotalSalesPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getTotalOrdersPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getTotalCustomersPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getTotalQuantityPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getAvgOrderValuePercent());
    }

    // ==================== 边界情况处理 ====================

    @Test
    @DisplayName("上一可用业务日不存在 - 应返回 comparisonAvailable=false")
    void getComparison_previousAvailableNotExists_returnsFalse() {
        // Given
        LocalDate date = LocalDate.of(2026, 4, 8);

        SalesOverviewVO current = createVO(
                date,
                new BigDecimal("1000.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        when(salesOverviewMapper.selectByDate(eq(date))).thenReturn(current);
        when(salesOverviewMapper.selectPreviousAvailable(eq(date), eq("test"))).thenReturn(null);

        // When
        SalesOverviewComparisonVO result = salesOverviewMetricService.getComparison(date);

        // Then
        assertFalse(result.isComparisonAvailable());
        assertEquals(date, result.getDate());
        assertNull(result.getComparisonDate());
        assertNotNull(result.getCurrent());
        assertNull(result.getPrevious());
        assertNull(result.getChangePercent());
    }

    @Test
    @DisplayName("当前日数据不存在 - 应抛出 404 业务异常")
    void getComparison_currentDataNotExists_throws404() {
        // Given
        LocalDate date = LocalDate.of(2026, 4, 8);

        when(salesOverviewMapper.selectByDate(eq(date))).thenReturn(null);

        // When & Then
        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> salesOverviewMetricService.getComparison(date)
        );

        assertEquals(404, exception.getStatus().value());
        assertEquals("未找到指定日期的销售概览数据", exception.getMessage());
    }

    @Test
    @DisplayName("上一可用业务日某项指标为 0 - 对应百分比应为 null")
    void getComparison_previousMetricIsZero_correspondingPercentIsNull() {
        // Given
        LocalDate date = LocalDate.of(2026, 4, 8);
        LocalDate comparisonDate = LocalDate.of(2026, 4, 7);

        SalesOverviewVO current = createVO(
                date,
                new BigDecimal("1000.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        // 上一可用业务日 totalSales 为 0
        SalesOverviewVO previous = createVO(
                comparisonDate,
                BigDecimal.ZERO,      // totalSales = 0
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        when(salesOverviewMapper.selectByDate(eq(date))).thenReturn(current);
        when(salesOverviewMapper.selectPreviousAvailable(eq(date), eq("test"))).thenReturn(previous);

        // When
        SalesOverviewComparisonVO result = salesOverviewMetricService.getComparison(date);

        // Then
        assertTrue(result.isComparisonAvailable());
        assertNull(result.getChangePercent().getTotalSalesPercent());  // 除以 0，返回 null
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getTotalOrdersPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getTotalCustomersPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getTotalQuantityPercent());
        assertEquals(new BigDecimal("0.00"), result.getChangePercent().getAvgOrderValuePercent());
    }

    // ==================== 舍入规则验证 ====================

    @Test
    @DisplayName("百分比两位小数舍入 - HALF_UP 规则")
    void getComparison_percentRounding_halfUp() {
        // Given
        LocalDate date = LocalDate.of(2026, 4, 8);
        LocalDate comparisonDate = LocalDate.of(2026, 4, 7);

        // 1000 / 3 = 333.333... -> 增长 233.33%
        SalesOverviewVO current = createVO(
                date,
                new BigDecimal("1000.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        SalesOverviewVO previous = createVO(
                comparisonDate,
                new BigDecimal("300.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        when(salesOverviewMapper.selectByDate(eq(date))).thenReturn(current);
        when(salesOverviewMapper.selectPreviousAvailable(eq(date), eq("test"))).thenReturn(previous);

        // When
        SalesOverviewComparisonVO result = salesOverviewMetricService.getComparison(date);

        // Then
        assertTrue(result.isComparisonAvailable());
        // (1000 - 300) / 300 × 100 = 233.333... -> 233.33 (HALF_UP)
        assertEquals(new BigDecimal("233.33"), result.getChangePercent().getTotalSalesPercent());
    }

    // ==================== 日期缺口场景验证 ====================

    @Test
    @DisplayName("日期缺口场景 - 应使用上一可用业务日而非 minusDays(1)")
    void getComparison_dateGap_shouldUsePreviousAvailableNotMinusDays() {
        // Given: 模拟真实 canonical 数据缺口
        // current date = 2009-12-13
        // natural previous (2009-12-12) 无数据
        // previous available date = 2009-12-11
        LocalDate currentDate = LocalDate.of(2009, 12, 13);
        LocalDate previousAvailableDate = LocalDate.of(2009, 12, 11);

        SalesOverviewVO current = createVO(
                currentDate,
                new BigDecimal("1000.00"),
                10L,
                10L,
                100L,
                new BigDecimal("100.00")
        );

        SalesOverviewVO previous = createVO(
                previousAvailableDate,
                new BigDecimal("800.00"),
                8L,
                8L,
                80L,
                new BigDecimal("100.00")
        );

        when(salesOverviewMapper.selectByDate(eq(currentDate))).thenReturn(current);
        when(salesOverviewMapper.selectPreviousAvailable(eq(currentDate), eq("test")))
                .thenReturn(previous);

        // When
        SalesOverviewComparisonVO result = salesOverviewMetricService.getComparison(currentDate);

        // Then
        assertTrue(result.isComparisonAvailable(), "应能找到上一可用业务日");
        assertEquals(previousAvailableDate, result.getComparisonDate(),
                "comparisonDate 应为 2009-12-11，而非 2009-12-12");
        assertEquals(previousAvailableDate, result.getPrevious().getDt(),
                "previous.dt 应为 2009-12-11");
        assertNotNull(result.getChangePercent(), "应计算环比");
        assertEquals(new BigDecimal("25.00"), result.getChangePercent().getTotalSalesPercent(),
                "环比应为 (1000-800)/800*100 = 25.00%");
    }

    // ==================== 辅助方法 ====================

    private SalesOverviewVO createVO(
            LocalDate date,
            BigDecimal totalSales,
            Long totalOrders,
            Long totalCustomers,
            Long totalQuantity,
            BigDecimal avgOrderValue) {

        SalesOverviewVO vo = new SalesOverviewVO();
        vo.setDt(date);
        vo.setTotalSales(totalSales);
        vo.setTotalOrders(totalOrders);
        vo.setTotalCustomers(totalCustomers);
        vo.setTotalQuantity(totalQuantity);
        vo.setAvgOrderValue(avgOrderValue);
        vo.setSourceSystem("test");
        return vo;
    }
}
