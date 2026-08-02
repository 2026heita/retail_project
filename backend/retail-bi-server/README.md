# 零售 BI 后端服务

Spring Boot 指标查询服务，为前端分析平台提供经营概览数据接口。

## 项目定位

```
Hive ADS → Shell 同步 → MySQL 应用表 → Spring Boot API → React 分析平台
```

本服务位于数据链路末端，负责：
- 查询已同步到 MySQL 的经营指标
- 提供统一的 REST API 响应格式
- 参数校验与异常处理
- 请求追踪（requestId）

不负责：
- 数据计算或聚合（由 Hive 完成）
- 数据同步（由 Shell 脚本完成）
- 前端渲染（由 React 平台完成）

## 技术栈

基于 `pom.xml` 实际配置：

- **Java**: 21
- **Spring Boot**: 4.0.7
- **Spring Web MVC**: 内置
- **MyBatis**: 4.0.1
- **MySQL Connector/J**: 运行时依赖
- **Bean Validation**: 参数校验
- **Maven Wrapper**: 构建工具

## 项目结构

```
src/main/java/com/retail/bi/
├── RetailBiServerApplication.java    # 启动类
├── common/
│   └── ApiResponse.java              # 统一响应格式
├── config/
│   └── WebCorsConfig.java            # CORS 配置
├── controller/
│   ├── HealthController.java         # 健康检查
│   └── SalesOverviewController.java  # 销售概览接口
├── dto/
│   ├── DashboardQueryDTO.java        # 单日查询参数
│   └── SalesTrendQueryDTO.java       # 趋势查询参数
├── exception/
│   ├── BusinessException.java        # 业务异常
│   └── GlobalExceptionHandler.java   # 全局异常处理
├── filter/
│   └── RequestIdFilter.java          # 请求 ID 过滤器
├── mapper/
│   └── SalesOverviewMapper.java      # MyBatis Mapper
├── service/
│   ├── SalesOverviewMetricService.java
│   └── SalesOverviewMetricServiceImpl.java
└── vo/
    └── SalesOverviewVO.java          # 返回对象
```

## API 接口

### 1. 健康检查

```
GET /api/v1/health
```

**响应示例：**

```json
{
  "status": "UP",
  "service": "retail-bi-server",
  "timestamp": "2026-04-08T10:30:00+08:00"
}
```

### 2. 单日销售概览

```
GET /api/v1/dashboard/overview?date=2026-04-08
```

**参数：**
- `date`（必填）：业务日期，ISO 格式（yyyy-MM-dd）
- 不能晚于当前日期

**响应示例：**

```json
{
  "code": 200,
  "message": "success",
  "data": {
    "dt": "2026-04-08",
    "totalSales": 53230287.48,
    "totalOrders": 36970,
    "totalCustomers": 5878,
    "totalQuantity": 32118447,
    "avgOrderValue": 1439.82,
    "sourceSystem": "hive_ads"
  },
  "requestId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**错误响应：**
- 404：指定日期无数据
- 400：日期格式错误或晚于当前日期

### 3. 销售趋势查询

```
GET /api/v1/dashboard/overview/trend?startDate=2026-04-01&endDate=2026-04-08
```

**参数：**
- `startDate`（必填）：开始日期，ISO 格式
- `endDate`（必填）：结束日期，ISO 格式
- 两个日期都不能晚于当前日期
- `startDate` 不能晚于 `endDate`
- 日期范围不能超过 31 天

**响应示例：**

```json
{
  "code": 200,
  "message": "success",
  "data": [
    {
      "dt": "2026-04-01",
      "totalSales": 12345678.90,
      "totalOrders": 8500,
      "totalCustomers": 1200,
      "totalQuantity": 7500000,
      "avgOrderValue": 1452.43,
      "sourceSystem": "hive_ads"
    },
    {
      "dt": "2026-04-02",
      "totalSales": 13456789.01,
      "totalOrders": 9200,
      "totalCustomers": 1350,
      "totalQuantity": 8100000,
      "avgOrderValue": 1462.69,
      "sourceSystem": "hive_ads"
    }
  ],
  "requestId": "b2c3d4e5-f6a7-8901-bcde-f12345678901"
}
```

**错误响应：**
- 400：参数缺失、格式错误、日期顺序错误或范围超限

## 环境变量

启动前需要配置以下环境变量：

```bash
# 数据库连接
RETAIL_DB_HOST=192.168.85.100        # MySQL 主机地址
RETAIL_DB_PORT=3306                   # MySQL 端口（默认 3306）
RETAIL_DB_NAME=retail_bi              # 数据库名
RETAIL_DB_USERNAME=retail_api_user    # 数据库用户名
RETAIL_DB_PASSWORD=<YOUR_PASSWORD>    # 数据库密码

# 服务配置
SERVER_PORT=8080                      # 服务端口（默认 8080）
```

**注意：**
- 密码必须通过环境变量传入，不要硬编码
- 默认数据库地址为 `192.168.85.100`，可通过 `RETAIL_DB_HOST` 覆盖
- 生产环境应使用独立的数据库账号和权限
- 不同环境部署时，应根据实际网络调整 MySQL 用户授权网段（参见 `mysql/02_create_retail_bi_users.local.sql`）

## 启动方式

### 方式一：使用 Maven Wrapper（推荐）

```bash
# Windows
.\mvnw.cmd spring-boot:run

# Linux/Mac
./mvnw spring-boot:run
```

### 方式二：先编译再运行

```bash
# 编译
.\mvnw.cmd clean package

# 运行
java -jar target/retail-bi-server-0.0.1-SNAPSHOT.jar
```

### 方式三：使用 IDE

直接运行 `RetailBiServerApplication.java` 的 `main` 方法。

## 验证与测试

### 运行单元测试

```bash
.\mvnw.cmd test
```

当前测试覆盖：
- `RetailBiServerApplicationTests.java`：应用启动测试

### 手动验证接口

启动服务后，使用 curl 或浏览器测试：

```bash
# 健康检查
curl http://localhost:8080/api/v1/health

# 单日概览（2026-04-08 是真实回归日）
curl "http://localhost:8080/api/v1/dashboard/overview?date=2026-04-08"

# 趋势查询（2026-04-01 至 2026-04-07 主要是趋势链路演示数据）
curl "http://localhost:8080/api/v1/dashboard/overview/trend?startDate=2026-04-01&endDate=2026-04-08"
```

### 编译打包

```bash
.\mvnw.cmd clean package
```

生成的 JAR 文件位于：`target/retail-bi-server-0.0.1-SNAPSHOT.jar`

## 核心实现

### 1. 统一响应格式

所有接口返回 `ApiResponse<T>` 结构：

```java
public record ApiResponse<T>(
    int code,           // 200=成功，400=参数错误，404=无数据，500=服务器错误
    String message,     // 响应消息
    T data,             // 响应数据
    String requestId    // 请求追踪 ID
)
```

### 2. 请求追踪

`RequestIdFilter` 自动为每个请求生成或传递 `requestId`：
- 如果请求头包含 `X-Request-Id`，则使用该值
- 否则生成 UUID
- 写入响应头 `X-Request-Id`
- 写入 MDC（Mapped Diagnostic Context），便于日志关联

### 3. 全局异常处理

`GlobalExceptionHandler` 统一处理异常：
- `BusinessException`：业务异常（如数据不存在）
- `MethodArgumentNotValidException`：参数校验失败
- `MethodArgumentTypeMismatchException`：参数类型错误
- `HttpMessageNotReadableException`：请求体格式错误
- `Exception`：未捕获异常

所有异常都返回 `ApiResponse` 格式，避免暴露内部堆栈。

### 4. CORS 配置

`WebCorsConfig` 允许以下来源跨域访问：
- `http://localhost:*`
- `http://127.0.0.1:*`

生产环境应限制为实际域名。

### 5. 参数校验

使用 Bean Validation 注解：
- `@NotNull`：必填字段
- `@PastOrPresent`：日期不能晚于当前
- `@AssertTrue`：自定义校验逻辑（如日期范围不超过 31 天）

## 数据库表

查询目标表：`bi_sales_overview_daily`

表结构（由 `mysql/01_create_retail_bi_tables.sql` 创建）：

```sql
CREATE TABLE bi_sales_overview_daily (
    dt DATE PRIMARY KEY,              -- 业务日期
    total_sales DECIMAL(15,2),        -- 销售额
    total_orders INT,                 -- 订单数
    total_customers INT,              -- 客户数
    total_quantity INT,               -- 销量
    avg_order_value DECIMAL(15,2),    -- 客单价
    source_system VARCHAR(50)         -- 数据来源
);
```

数据由 Shell 脚本从 Hive ADS 同步，本服务只负责查询。

## 演示数据说明

- **2026-04-08**：真实回归日，核心验证基线
- **2026-04-01 至 2026-04-07**：趋势链路演示数据，用于验证多日期查询

演示数据不代表真实业务连续性，仅用于工程验证。

## 当前边界

本服务当前**不包含**：
- 认证与授权（无登录、无权限控制）
- 分页与排序（趋势接口返回全部数据）
- 缓存（每次查询直接访问数据库）
- 限流与熔断
- 生产级高可用（单实例部署）
- 任意指标动态查询（只支持预定义的 5 个指标）
- 数据写入接口（只读服务）

如需扩展，建议：
- 增加 Spring Security 实现认证
- 增加 Redis 缓存热点数据
- 增加分页参数支持大数据量
- 增加 Swagger/OpenAPI 文档
- 增加 Prometheus 指标暴露

## 故障排查

### 1. 启动失败：数据库连接错误

检查：
- 环境变量是否正确设置
- MySQL 服务是否运行
- 网络是否可达（`telnet <host> 3306`）
- 用户名密码是否正确
- 数据库 `retail_bi` 是否存在
- 表 `bi_sales_overview_daily` 是否存在

### 2. 接口返回 404

检查：
- 请求的日期是否有数据
- 日期格式是否为 `yyyy-MM-dd`
- 日期是否晚于当前日期

### 3. 接口返回 400

检查：
- 必填参数是否缺失
- 日期格式是否正确
- 趋势查询的日期范围是否超过 31 天
- `startDate` 是否晚于 `endDate`

### 4. 跨域错误

检查：
- 前端是否运行在 `http://localhost:*` 或 `http://127.0.0.1:*`
- 如需其他域名，修改 `WebCorsConfig.java`

## 相关文档

- [根目录 README](../../README.md)：项目整体说明
- [数仓实现细节](../../docs/warehouse_implementation_details.md)：Hive 分层与质量门禁
- [MySQL 建表脚本](../../mysql/01_create_retail_bi_tables.sql)：应用表结构
- [同步脚本](../../sync/01_sync_sales_overview_to_mysql.sh)：数据同步流程
