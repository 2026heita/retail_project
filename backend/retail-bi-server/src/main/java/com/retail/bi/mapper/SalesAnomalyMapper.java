package com.retail.bi.mapper;

import com.retail.bi.vo.SalesAnomalyVO;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDate;
import java.util.List;

@Mapper
public interface SalesAnomalyMapper {

    /**
     * 查询指定日期范围内的经营异常。
     *
     * 仅返回 MEDIUM / HIGH，NORMAL 不作为异常列表返回。
     * source_system 显式限定为 canonical anomaly serving，
     * 避免未来其他来源数据混入当前查询口径。
     */
    @Select("""
            SELECT
                dt,
                total_sales AS totalSales,
                total_orders AS totalOrders,
                total_customers AS totalCustomers,
                total_quantity AS totalQuantity,
                avg_order_value AS avgOrderValue,
                prev_dt AS prevDt,
                prev_sales AS prevSales,
                sales_change_pct AS salesChangePct,
                sales_loss_amount AS salesLossAmount,
                orders_change_pct AS ordersChangePct,
                customers_change_pct AS customersChangePct,
                quantity_change_pct AS quantityChangePct,
                aov_change_pct AS aovChangePct,
                anomaly_level AS anomalyLevel,
                primary_driver AS primaryDriver,
                source_system AS sourceSystem
            FROM bi_sales_anomaly_daily
            WHERE dt BETWEEN #{startDate} AND #{endDate}
              AND source_system = #{sourceSystem}
              AND anomaly_level IN ('MEDIUM', 'HIGH')
            ORDER BY dt ASC
            """)
    List<SalesAnomalyVO> selectAnomaliesByDateRange(
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate,
            @Param("sourceSystem") String sourceSystem
    );
}
