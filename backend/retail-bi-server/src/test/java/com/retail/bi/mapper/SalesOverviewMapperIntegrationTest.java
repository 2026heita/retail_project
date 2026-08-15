package com.retail.bi.mapper;

import com.retail.bi.vo.SalesOverviewVO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.mysql.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import java.util.List;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

@Testcontainers
@MybatisTest
class SalesOverviewMapperIntegrationTest {

    @Container
    @ServiceConnection
    static final MySQLContainer MYSQL =
            new MySQLContainer("mysql:8.0.36");

    @Autowired
    private SalesOverviewMapper salesOverviewMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void setUp() {
        jdbcTemplate.execute("DROP TABLE IF EXISTS bi_sales_overview_daily");

        jdbcTemplate.execute("""
                CREATE TABLE bi_sales_overview_daily (
                    dt DATE NOT NULL PRIMARY KEY,
                    total_sales DECIMAL(18, 2) NOT NULL,
                    total_orders BIGINT NOT NULL,
                    total_customers BIGINT NOT NULL,
                    total_quantity BIGINT NOT NULL,
                    avg_order_value DECIMAL(18, 2) NOT NULL,
                    source_system VARCHAR(64) NOT NULL
                )
                """);

        jdbcTemplate.update("""
                INSERT INTO bi_sales_overview_daily (
                    dt,
                    total_sales,
                    total_orders,
                    total_customers,
                    total_quantity,
                    avg_order_value,
                    source_system
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                LocalDate.of(2009, 12, 10),
                new BigDecimal("38806.36"),
                20L,
                18L,
                1000L,
                new BigDecimal("1940.32"),
                "retail_canonical"
        );

        jdbcTemplate.update("""
                INSERT INTO bi_sales_overview_daily (
                    dt,
                    total_sales,
                    total_orders,
                    total_customers,
                    total_quantity,
                    avg_order_value,
                    source_system
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                LocalDate.of(2009, 12, 13),
                new BigDecimal("25000.00"),
                15L,
                14L,
                700L,
                new BigDecimal("1666.67"),
                "retail_canonical"
        );

        jdbcTemplate.update("""
                INSERT INTO bi_sales_overview_daily (
                    dt,
                    total_sales,
                    total_orders,
                    total_customers,
                    total_quantity,
                    avg_order_value,
                    source_system
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                LocalDate.of(2009, 12, 14),
                new BigDecimal("9999.99"),
                8L,
                7L,
                300L,
                new BigDecimal("1250.00"),
                "other_source"
        );
    }

    @Test
    void selectByDate_shouldReturnMappedRow() {
        SalesOverviewVO result =
                salesOverviewMapper.selectByDate(LocalDate.of(2009, 12, 10));

        assertThat(result).isNotNull();
        assertThat(result.getDt()).isEqualTo(LocalDate.of(2009, 12, 10));
        assertThat(result.getTotalSales())
                .isEqualByComparingTo("38806.36");
        assertThat(result.getTotalOrders()).isEqualTo(20L);
        assertThat(result.getTotalCustomers()).isEqualTo(18L);
        assertThat(result.getTotalQuantity()).isEqualTo(1000L);
        assertThat(result.getAvgOrderValue())
                .isEqualByComparingTo("1940.32");
        assertThat(result.getSourceSystem())
                .isEqualTo("retail_canonical");
    }

    @Test
    void selectByDateRange_shouldReturnRowsInAscendingDateOrder() {
        List<SalesOverviewVO> results =
                salesOverviewMapper.selectByDateRange(
                        LocalDate.of(2009, 12, 10),
                        LocalDate.of(2009, 12, 14)
                );

        assertThat(results).hasSize(3);

        assertThat(results)
                .extracting(SalesOverviewVO::getDt)
                .containsExactly(
                        LocalDate.of(2009, 12, 10),
                        LocalDate.of(2009, 12, 13),
                        LocalDate.of(2009, 12, 14)
                );
    }

    @Test
    void selectPreviousAvailable_shouldSkipMissingDatesAndFilterSourceSystem() {
        SalesOverviewVO result =
                salesOverviewMapper.selectPreviousAvailable(
                        LocalDate.of(2009, 12, 14),
                        "retail_canonical"
                );

        assertThat(result).isNotNull();
        assertThat(result.getDt()).isEqualTo(LocalDate.of(2009, 12, 13));
        assertThat(result.getSourceSystem()).isEqualTo("retail_canonical");
        assertThat(result.getTotalSales())
                .isEqualByComparingTo("25000.00");
    }
}