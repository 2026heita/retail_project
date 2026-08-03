package com.retail.bi.service;

import com.retail.bi.vo.SalesOverviewComparisonVO;
import com.retail.bi.vo.SalesOverviewVO;

import java.time.LocalDate;
import java.util.List;

/**
 * 销售概览指标服务。
 *
 * 作用：
 * 1. 对外提供销售概览指标查询能力；
 * 2. 隔离 Controller 与具体实现类；
 * 3. 为后续增加缓存、权限、指标口径校验等能力保留扩展位置。
 */
public interface SalesOverviewMetricService {

    /**
     * 根据业务日期查询销售概览指标。
     *
     * @param date 业务日期
     * @return 销售概览指标
     */
    SalesOverviewVO getByDate(LocalDate date);

    /**
     * 查询指定日期范围内的销售趋势数据。
     *
     * @param startDate 开始日期
     * @param endDate   结束日期
     * @return 每日销售概览指标列表
     */
    List<SalesOverviewVO> getTrend(
            LocalDate startDate,
            LocalDate endDate
    );

    /**
     * 查询指定日期的销售概览日环比数据。
     *
     * @param date 业务日期
     * @return 日环比对比结果
     */
    SalesOverviewComparisonVO getComparison(LocalDate date);
}