package com.retail.bi.mapper;

import com.retail.bi.vo.SalesOverviewVO;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.util.List;

@Mapper
public interface SalesOverviewMapper {

    /**
     * 查询指定业务日期的销售概览指标。
     */
    @Select("""
            SELECT
                dt,
                total_sales AS totalSales,
                total_orders AS totalOrders,
                total_customers AS totalCustomers,
                total_quantity AS totalQuantity,
                avg_order_value AS avgOrderValue,
                source_system AS sourceSystem
            FROM bi_sales_overview_daily
            WHERE dt = #{date}
            """)
    SalesOverviewVO selectByDate(@Param("date") LocalDate date);

    /**
     * 查询指定日期范围内的销售趋势数据。
     * 按业务日期升序排列，便于前端直接绘制趋势图。
     */
    @Select("""
            SELECT
                dt,
                total_sales AS totalSales,
                total_orders AS totalOrders,
                total_customers AS totalCustomers,
                total_quantity AS totalQuantity,
                avg_order_value AS avgOrderValue,
                source_system AS sourceSystem
            FROM bi_sales_overview_daily
            WHERE dt BETWEEN #{startDate} AND #{endDate}
            ORDER BY dt ASC
            """)
    List<SalesOverviewVO> selectByDateRange(
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate
    );
}