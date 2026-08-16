package com.retail.bi.mapper;

import com.retail.bi.vo.SalesAnomalyVO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mysql.MySQLContainer;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@Testcontainers
@MybatisTest
class SalesAnomalyMapperIntegrationTest {

    @Container
    @ServiceConnection
    static final MySQLContainer MYSQL =
            new MySQLContainer("mysql:8.0.36")
                    .withDatabaseName("retail_bi")
                    .withInitScript("mysql/03_create_retail_bi_anomaly_table.sql");

    @Autowired
    private SalesAnomalyMapper salesAnomalyMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void setUp() {
        jdbcTemplate.update("DELETE FROM bi_sales_anomaly_daily");

        insertAnomaly(
                LocalDate.of(2010, 9, 27),
                "NORMAL",
                null,
                "retail_canonical_anomaly_ads"
        );

        insertAnomaly(
                LocalDate.of(2010, 9, 28),
                "HIGH",
                "ORDERS",
                "retail_canonical_anomaly_ads"
        );

        insertAnomaly(
                LocalDate.of(2010, 9, 29),
                "MEDIUM",
                "AVG_ORDER_VALUE",
                "retail_canonical_anomaly_ads"
        );

        insertAnomaly(
                LocalDate.of(2010, 9, 30),
                "HIGH",
                "ORDERS",
                "other_source"
        );
    }

    @Test
    void selectAnomaliesByDateRange_shouldFilterAndMapRows() {
        List<SalesAnomalyVO> results =
                salesAnomalyMapper.selectAnomaliesByDateRange(
                        LocalDate.of(2010, 9, 27),
                        LocalDate.of(2010, 9, 30),
                        "retail_canonical_anomaly_ads"
                );

        assertThat(results).hasSize(2);

        assertThat(results)
                .extracting(SalesAnomalyVO::getDt)
                .containsExactly(
                        LocalDate.of(2010, 9, 28),
                        LocalDate.of(2010, 9, 29)
                );

        SalesAnomalyVO high = results.get(0);

        assertThat(high.getAnomalyLevel()).isEqualTo("HIGH");
        assertThat(high.getPrimaryDriver()).isEqualTo("ORDERS");
        assertThat(high.getSourceSystem())
                .isEqualTo("retail_canonical_anomaly_ads");

        assertThat(high.getTotalSales())
                .isEqualByComparingTo("10000.00");
        assertThat(high.getPrevSales())
                .isEqualByComparingTo("15000.00");
        assertThat(high.getSalesChangePct())
                .isEqualByComparingTo("-33.33");
    }

    private void insertAnomaly(
            LocalDate dt,
            String anomalyLevel,
            String primaryDriver,
            String sourceSystem
    ) {
        jdbcTemplate.update("""
                INSERT INTO bi_sales_anomaly_daily (
                    dt,
                    total_sales,
                    total_orders,
                    total_customers,
                    total_quantity,
                    avg_order_value,
                    prev_dt,
                    prev_sales,
                    sales_change_pct,
                    sales_loss_amount,
                    orders_change_pct,
                    customers_change_pct,
                    quantity_change_pct,
                    aov_change_pct,
                    anomaly_level,
                    primary_driver,
                    source_system
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                dt,
                new BigDecimal("10000.00"),
                20L,
                18L,
                500L,
                new BigDecimal("500.00"),
                dt.minusDays(1),
                new BigDecimal("15000.00"),
                new BigDecimal("-33.33"),
                new BigDecimal("5000.00"),
                new BigDecimal("-20.00"),
                new BigDecimal("-10.00"),
                new BigDecimal("-15.00"),
                new BigDecimal("-16.67"),
                anomalyLevel,
                primaryDriver,
                sourceSystem
        );
    }
}