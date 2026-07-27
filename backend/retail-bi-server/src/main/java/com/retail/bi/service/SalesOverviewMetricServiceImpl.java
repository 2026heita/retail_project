package com.retail.bi.service;

import com.retail.bi.exception.BusinessException;
import com.retail.bi.mapper.SalesOverviewMapper;
import com.retail.bi.vo.SalesOverviewVO;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

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
}