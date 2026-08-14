package com.retail.bi.service;

import com.retail.bi.vo.SalesAnomalyVO;

import java.time.LocalDate;
import java.util.List;

/**
 * 经营异常查询服务。
 */
public interface SalesAnomalyService {

    /**
     * 查询指定日期范围内的 MEDIUM / HIGH 经营异常。
     *
     * 没有异常时返回空列表，不抛 404。
     */
    List<SalesAnomalyVO> getAnomalies(
            LocalDate startDate,
            LocalDate endDate
    );
}
