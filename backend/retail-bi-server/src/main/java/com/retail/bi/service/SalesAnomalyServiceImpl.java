package com.retail.bi.service;

import com.retail.bi.mapper.SalesAnomalyMapper;
import com.retail.bi.vo.SalesAnomalyVO;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.List;

/**
 * 经营异常查询服务实现。
 *
 * 异常识别与驱动计算已在 Hive ADS 完成；
 * API 层只查询 MySQL Serving，不重复计算业务指标。
 */
@Service
public class SalesAnomalyServiceImpl implements SalesAnomalyService {

    private static final String SOURCE_SYSTEM =
            "retail_canonical_anomaly_ads";

    private final SalesAnomalyMapper salesAnomalyMapper;

    public SalesAnomalyServiceImpl(
            SalesAnomalyMapper salesAnomalyMapper) {
        this.salesAnomalyMapper = salesAnomalyMapper;
    }

    @Override
    public List<SalesAnomalyVO> getAnomalies(
            LocalDate startDate,
            LocalDate endDate) {

        return salesAnomalyMapper.selectAnomaliesByDateRange(
                startDate,
                endDate,
                SOURCE_SYSTEM
        );
    }
}
