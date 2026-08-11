package com.retail.bi.service;

import com.retail.bi.exception.BusinessException;
import com.retail.bi.mapper.SalesOverviewMapper;
import com.retail.bi.vo.SalesOverviewChangePercentVO;
import com.retail.bi.vo.SalesOverviewComparisonVO;
import com.retail.bi.vo.SalesOverviewVO;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.List;

/**
 * 销售概览指标服务实现类。
 *
 * 作用：
 * 1. 调用 Mapper 查询销售概览数据；
 * 2. 负责销售概览相关业务规则；
 * 3. 查询不到数据时抛出统一业务异常；
 * 4. 为后续指标口径校验、缓存和权限控制提供实现位置。
 */
@Service
public class SalesOverviewMetricServiceImpl
        implements SalesOverviewMetricService {

    private final SalesOverviewMapper salesOverviewMapper;

    public SalesOverviewMetricServiceImpl(
            SalesOverviewMapper salesOverviewMapper) {
        this.salesOverviewMapper = salesOverviewMapper;
    }

    @Override
    public List<SalesOverviewVO> getTrend(
            LocalDate startDate,
            LocalDate endDate) {

        return salesOverviewMapper.selectByDateRange(startDate, endDate);
    }

    /**
     * 根据业务日期查询销售概览指标。
     */
    @Override
    public SalesOverviewVO getByDate(LocalDate date) {

        SalesOverviewVO result =
                salesOverviewMapper.selectByDate(date);

        // 查询不到数据时，由业务层统一定义异常语义。
        if (result == null) {
            throw new BusinessException(
                    HttpStatus.NOT_FOUND,
                    "未找到指定日期的销售概览数据"
            );
        }

        return result;
    }

    /**
     * 查询指定日期的销售概览日环比数据。
     *
     * 比较口径：当前业务日 vs 同一 source_system 下的上一可用业务日。
     *
     * @param date 业务日期
     * @return 日环比对比结果
     */
    @Override
    public SalesOverviewComparisonVO getComparison(LocalDate date) {
        // 查询当前日数据，不存在则抛出 404 业务异常
        SalesOverviewVO current = salesOverviewMapper.selectByDate(date);
        if (current == null) {
            throw new BusinessException(
                    HttpStatus.NOT_FOUND,
                    "未找到指定日期的销售概览数据"
            );
        }

        // 查询同一 source_system 下上一可用业务日数据
        SalesOverviewVO previous = salesOverviewMapper.selectPreviousAvailable(
                date,
                current.getSourceSystem()
        );

        SalesOverviewComparisonVO result = new SalesOverviewComparisonVO();
        result.setDate(date);
        result.setCurrent(current);

        // 上一可用业务日不存在时，comparisonAvailable=false
        if (previous == null) {
            result.setComparisonDate(null);
            result.setComparisonAvailable(false);
            result.setPrevious(null);
            result.setChangePercent(null);
            return result;
        }

        // 上一可用业务日存在，计算环比
        result.setComparisonDate(previous.getDt());
        result.setComparisonAvailable(true);
        result.setPrevious(previous);
        result.setChangePercent(calculateChangePercent(current, previous));

        return result;
    }

    /**
     * 计算五项指标的环比变化百分比。
     *
     * 公式：(current - previous) / previous × 100
     * 规则：
     * - 使用 BigDecimal 计算，保留两位小数，HALF_UP 舍入
     * - 前一日某项指标为 0 时，对应百分比为 null（避免除以 0）
     *
     * @param current  当前日数据
     * @param previous 前一日数据
     * @return 环比变化百分比 VO
     */
    private SalesOverviewChangePercentVO calculateChangePercent(
            SalesOverviewVO current,
            SalesOverviewVO previous) {

        SalesOverviewChangePercentVO percent = new SalesOverviewChangePercentVO();

        percent.setTotalSalesPercent(
                calculatePercentChange(current.getTotalSales(), previous.getTotalSales())
        );
        percent.setTotalOrdersPercent(
                calculatePercentChange(current.getTotalOrders(), previous.getTotalOrders())
        );
        percent.setTotalCustomersPercent(
                calculatePercentChange(current.getTotalCustomers(), previous.getTotalCustomers())
        );
        percent.setTotalQuantityPercent(
                calculatePercentChange(current.getTotalQuantity(), previous.getTotalQuantity())
        );
        percent.setAvgOrderValuePercent(
                calculatePercentChange(current.getAvgOrderValue(), previous.getAvgOrderValue())
        );

        return percent;
    }

    /**
     * 计算单个指标的环比变化百分比。
     *
     * @param current  当前值
     * @param previous 前一日值
     * @return 百分比变化，前一日为 0 时返回 null
     */
    private BigDecimal calculatePercentChange(BigDecimal current, BigDecimal previous) {
        if (previous == null || previous.compareTo(BigDecimal.ZERO) == 0) {
            return null;
        }
        // (current - previous) / previous × 100
        return current.subtract(previous)
                .divide(previous, 4, RoundingMode.HALF_UP)
                .multiply(new BigDecimal("100"))
                .setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * 计算单个指标的环比变化百分比（Long 类型）。
     *
     * @param current  当前值
     * @param previous 前一日值
     * @return 百分比变化，前一日为 0 时返回 null
     */
    private BigDecimal calculatePercentChange(Long current, Long previous) {
        if (current == null || previous == null || previous == 0L) {
            return null;
        }
        // 先安全转换为 BigDecimal
        BigDecimal currentBd = BigDecimal.valueOf(current);
        BigDecimal previousBd = BigDecimal.valueOf(previous);
        return calculatePercentChange(currentBd, previousBd);
    }
}