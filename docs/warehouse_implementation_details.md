# 零售数仓项目完整技术实现文档

> 本文档由项目原根 README 整理而来，保留数仓分层、质量门禁、回刷、调度、SCD2、性能验证及 BI 应用闭环等完整技术记录。仓库首页和项目概览请查看根目录的 [README.md](../README.md)。

> 阅读建议：招聘方或首次访问者优先阅读根 README；需要核对实现细节、脚本职责、验收口径和工程边界时，再阅读本文档。

## 文档导航

1. 项目简介
2. 项目架构
3. 技术栈
4. 项目目录结构
5. BI 应用服务与前端闭环
6. 数据说明
7. ODS 数据入口设计
8. Hive 主链路执行
9. 数据质量体系
10. 星型模型扩展
11. MySQL 阶段
12. DolphinScheduler 调度设计
13. 回刷、T+1 与幂等性
14. 性能分析与 SQL 优化
15. 已验证结果
16. 运行结果截图
17. 本地最小复现
18. 项目亮点
19. 项目边界
20. 工程能力总结
21. 仓库公开与安全说明

---

## 1. 项目简介

本项目基于电商零售订单数据，围绕订单、客户、商品和国家等维度，完成从 MySQL 数据分析、Hive 离线数仓、DolphinScheduler 调度，到 MySQL BI 应用表、Spring Boot 指标 API 和前端分析平台接入的完整实践。

当前 canonical 真实业务数据（1,067,371 行 Raw，DWD 805,531 行，604 个真实业务日期，2009-12-01 ~ 2011-12-09）已完成 DWD/DWS/ADS/serving/API/前端联调全链路验证。

项目当前包含四个阶段：

1. **MySQL 分析阶段**
   完成订单清洗、DWS / ADS 指标开发、统一执行脚本、批次日志，以及 20 项可阻断的数据质量检查。

2. **Hive 主链路阶段**
   构建 `ODS Raw → ODS Reject / 正常 ODS → DWD → DWS → ADS` 分层链路，使用 ORC、日期分区、`bizdate` 参数和 `INSERT OVERWRITE PARTITION` 支持指定业务日期重跑。

3. **工程化与维度建模阶段**
   增加 ODS 入仓完整性门禁、DWD / DWS / ADS / 星型模型质量门禁、区间回刷、T+1 修正、内容指纹幂等性检查、按业务日物化完整历史快照的 SCD2 用户维度、订单事实表和 DolphinScheduler 演示 DAG。

4. **BI 应用闭环阶段**
   从 Hive ADS 预计算经营总览日指标，通过 Shell 幂等同步到 MySQL 应用表，再由 Spring Boot 提供单日概览、日期范围趋势、环比和异常查询接口，最后接入独立 React 分析平台，形成"数仓 → Java → BI"闭环。
   新增经营异常检测 ADS（ads_sales_anomaly_daily_hive），基于规则识别 HIGH / MEDIUM 等级经营异常，通过 Shell 批量同步至 MySQL Serving 表（bi_sales_anomaly_daily），Spring Boot 提供异常查询接口（/api/v1/dashboard/anomalies），形成完整的异常检测链路。

本项目重点不是单纯编写 SQL 查询，而是展示以下能力：

- 离线数仓分层建模；
- 原始数据保真与异常分流；
- 上下游行数和金额对账；
- 可重跑、回刷、幂等性和失败阻断；
- ETL 批次级日志追踪；
- SCD2、事实表和星型模型设计；
- 调度编排、性能分析和工程化表达；
- ADS 预聚合、应用表同步和只读指标 API；
- 统一响应、参数校验、异常处理和 `requestId`；
- 外部业务指标接入前端分析平台。

> 项目定位为学习和作品集项目。文档会区分"已经实际验证的能力"和"尚未扩展完成的能力"，避免把演示链路描述成生产级系统。

---

## 2. 项目架构

### 2.1 整体工程架构

```mermaid
flowchart LR
  A["零售订单数据"] --> M["MySQL 分析链路<br/>清洗 / DWS / ADS / 质量门禁"]
  A --> H["Hive 离线数仓链路"]

  H --> R["ODS Raw<br/>原始字段保真"]
  R --> J["ODS Reject<br/>技术解析异常隔离"]
  R --> O["正常 ODS<br/>业务日期分区"]

  J --> Q0["ODS 入仓完整性门禁"]
  O --> Q0
  Q0 --> D["DWD 清洗明细"]
  D --> Q1["DWD 质量门禁"]
  Q1 --> W["DWS / ADS 指标"]
  W --> Q2["结果质量门禁"]
  Q2 --> S["星型模型分支<br/>SCD2 / 事实表 / 星型 DWS<br/>验证至 2010-03-04<br/>73 个真实业务日期"]
  S --> Q3["星型模型质量门禁<br/>17 条 BLOCK 规则"]

  H --> E["Shell 工程化执行<br/>单日 / 区间回刷 / T+1 / 幂等性"]
  H --> DS["DolphinScheduler<br/>12 节点演示 DAG"]

  Q3 --> V["查询结果 / 质量日志 / 截图验收"]
  E --> V
  DS --> V
```

### 2.2 Hive 完整主链路

```mermaid
flowchart TB
  SRC["Hive 源表 retail"] --> RAW["ods_retail_raw_hive<br/>业务字段 STRING<br/>batch_dt 分区"]

  RAW --> REJECT["ods_retail_reject_hive<br/>技术解析异常隔离"]
  RAW --> ODS["ods_retail_hive<br/>正常业务 ODS<br/>dt 分区"]

  SRC --> G0["ODS 入仓完整性门禁"]
  RAW --> G0
  REJECT --> G0
  ODS --> G0

  G0 --> DWD["dwd_retail_clean_hive<br/>有效订单明细"]
  DWD --> G1["DWD 门禁<br/>6 条 BLOCK 规则"]

  G1 --> DWS1["dws_customer_value_hive"]
  G1 --> DWS2["dws_sales_summary_hive"]

  DWS1 --> ADS1["高价值客户销售贡献"]
  DWS1 --> ADS2["客户层级分布"]
  DWS1 --> ADS4["高价值客户商品偏好"]
  DWS2 --> ADS3["国家销售排行"]

  ADS1 --> G2["DWS / ADS 结果门禁<br/>11 条 BLOCK / WARN 规则"]
  ADS2 --> G2
  ADS3 --> G2
  ADS4 --> G2

  G2 --> U["dim_user<br/>按业务日物化完整历史快照的 SCD2"]
  G2 --> P["dim_product"]
  G2 --> T["dim_date"]
  G2 --> GEO["dim_geo"]

  U --> F["fact_order"]
  P --> F
  T --> F
  GEO --> F

  F --> SDWS["dws_customer_value_star_hive"]
  SDWS --> G3["星型模型门禁<br/>17 条 BLOCK 规则<br/>验证至 2010-03-04<br/>73 个真实业务日期"]
```

> **Scope Note**：
> - **Canonical DWD/DWS/ADS**：覆盖 604 个真实业务日期（2009-12-01 ~ 2011-12-09）
> - **Canonical Star**：连续验证至 2010-03-04，覆盖 73 个真实业务日期（不是 604 天全量历史）

### 2.3 MySQL 与 Hive 的关系

```text
MySQL 链路                         Hive 链路
retail                            retail
  ↓                                 ↓
retail_clean / retail_clean2      ODS Raw / Reject / 正常 ODS
  ↓                                 ↓
DWS / ADS                         DWD / DWS / ADS / 星型模型
  ↓                                 ↓
Windows / Linux 调度模拟          Shell / DolphinScheduler
```

MySQL 表和 Hive 表是两个独立系统中的对象。即使二者存在同名表，Hive 也不会自动读取 MySQL 数据。

当前仓库的最小 Hive 复现链路为：

```text
CSV → Hive retail → Hive 数仓链路
```

项目没有内置 MySQL 到 Hive 的自动同步任务。生产环境如需同步，可额外接入 DataX、Sqoop、SeaTunnel 或 DolphinScheduler 数据同步任务。

### 2.4 数仓到 BI 应用闭环

```mermaid
flowchart LR
  DWD["Hive DWD<br/>有效订单明细"] --> ADS["Hive ADS<br/>ads_sales_overview_daily_hive"]
  ADS --> SYNC["Shell 同步与对账"]
  SYNC --> MYSQL["MySQL 应用表<br/>bi_sales_overview_daily"]
  MYSQL --> JAVA["Spring Boot<br/>统一指标 API"]
  JAVA --> WEB["React 分析平台<br/>指标概览 / 时间趋势"]
```

职责边界：

```text
Hive ADS
  负责按业务日期预计算销售额、订单数、客户数、销量和客单价

Shell 同步
  负责单日或区间同步、主键幂等更新以及 Hive / MySQL 对账

MySQL 应用表
  负责保存 Java 查询所需的轻量日粒度结果

Spring Boot
  负责参数校验、只读查询、统一响应、异常处理和 requestId

React 分析平台
  负责连接 API、转换统一表格模型并展示统计与时间趋势
```

Java 服务不会扫描大规模订单明细，也不会重复聚合 Hive 已经计算完成的 ADS 指标。

---

## 3. 技术栈

### 数仓与调度

- MySQL 8.x
- Hive 3.x
- Hadoop / HDFS
- SQL
- ORC
- Bash / Linux Shell
- Windows Batch / PowerShell
- DolphinScheduler 3.2.2
- Docker Standalone
- SSH
- 离线数仓分层建模
- 星型模型与 SCD2
- 数据质量门禁
- ETL 批次日志

### BI 应用服务

- Java 21
- Spring Boot 4.0.7
- Spring Web MVC
- Bean Validation
- MyBatis 4.0.1
- MySQL Connector/J
- Maven Wrapper
- REST API
- SLF4J MDC `requestId`

### 前端接入

当前交互式分析前端位于独立的 [score-analysis-tool](https://github.com/2026heita/score-analysis-tool) 项目，使用 React、TypeScript 和 ECharts。该前端通过零售 BI 连接器调用本项目的 Spring Boot 趋势接口，并复用通用字段识别、统计、导出和时间趋势能力。

> 仓库中的旧轻量 BI Dashboard 截图仍作为历史展示材料保留；当前可交互分析链路由 Spring Boot API 与独立 React 项目共同完成。

---

## 4. 项目目录结构

```text
retail_project/
├── README.md
├── sample_data/
│   └── retail_sample.csv
├── sql/                                      # MySQL 分析、DWS / ADS、日志和质量检查
├── scripts/                                  # MySQL 本地执行与调度演示
├── hive_sql/                                 # Hive 数仓 SQL、质量门禁与 Shell 主链路
│   ├── 00-28 ODS / DWD / DWS / ADS / 星型模型 / 质量日志
│   ├── 29_ads_sales_overview_daily_hive.sql
│   ├── 30_backfill_ads_sales_overview_daily.sh
│   ├── run_all_hive.sh
│   ├── run_daily_hive_profiled.sh
│   ├── run_backfill_hive.sh
│   ├── run_t1_window_hive.sh
│   ├── run_idempotency_check_hive.sh
│   └── run_*_quality_gate_hive.sh
├── mysql/                                    # BI 应用库建表与账号示例
│   ├── 01_create_retail_bi_tables.sql
│   └── 02_create_retail_bi_users.local.sql
├── sync/                                     # Hive ADS → MySQL 应用表
│   ├── 01_sync_sales_overview_to_mysql.sh
│   └── 02_backfill_sales_overview_to_mysql.sh
├── backend/
│   └── retail-bi-server/                     # Spring Boot 指标 API
│       ├── pom.xml
│       ├── mvnw / mvnw.cmd
│       └── src/
├── dolphinscheduler/                         # 调度设计、导入 JSON 与辅助 SQL
└── docs/
    ├── warehouse_implementation_details.md  # 当前完整技术文档
    ├── setup_local_hive.md
    ├── 25_scheduler_design.txt
    ├── 27_metric_definitions.txt
    ├── result_screenshots/
    └── multiday_validation_screenshots/
```

目录职责：

```text
sql/       MySQL 分析 SQL
scripts/   MySQL 本地执行与调度演示
hive_sql/  Hive SQL、质量门禁和 Shell 主链路
mysql/     BI 应用数据库、日指标表和账号示例
sync/      Hive ADS 到 MySQL 的单日 / 区间同步与对账
backend/   Java 指标查询服务
```

运行产生的日志和耗时文件统一写入：

```text
logs/
```

该目录已加入 `.gitignore`，不提交仓库。后端的 `target/`、IDE 配置和真实密码同样不应提交。

---

## 5. BI 应用服务与前端闭环

### 5.1 指标口径与存储粒度

Hive ADS 表：

```text
ads_sales_overview_daily_hive
```

MySQL 应用表：

```text
retail_bi.bi_sales_overview_daily
```

两张表都采用"每个业务日期一行"的粒度，包含五项核心经营指标：

| 指标 | 字段 | 口径 |
|---|---|---|
| 销售额 | `total_sales` | DWD 有效订单金额合计 |
| 订单数 | `total_orders` | 去重有效订单数 |
| 客户数 | `total_customers` | 去重有效客户数 |
| 销量 | `total_quantity` | 有效商品数量合计 |
| 客单价 | `avg_order_value` | `total_sales / total_orders`，订单数为 0 时返回 0 |

指标在 Hive ADS 中预计算，Java 只读取同步后的 MySQL 应用表，不重新扫描订单明细。

### 5.2 生成和同步经营总览指标

生成单日 Hive ADS（单日示例，start_dt 和 end_dt 相同）：

```bash
hive --database retail_canonical \
  --hiveconf start_dt=2009-12-03 \
  --hiveconf end_dt=2009-12-03 \
  -f hive_sql/29_ads_sales_overview_daily_hive.sql
```

范围式回刷：

```bash
HIVE_DATABASE=retail_canonical \
bash hive_sql/30_backfill_ads_sales_overview_daily.sh 2009-12-01 2011-12-09
```

回刷脚本行为（`30_backfill_ads_sales_overview_daily.sh`）：

1. DWD 范围前置检查：查询范围内 DWD 业务日期数量、最小/最大日期和金额汇总
2. 查询目标范围内已有 ADS 分区
3. 校验分区日期格式和范围合法性
4. 删除范围内已有旧 ADS 分区（stale partition self-healing）
5. 执行范围式动态分区 INSERT OVERWRITE 重建
6. DWD 0 行是合法状态（空数据集不阻断）
7. ADS 后置验证：行数、日期范围、金额汇总
8. DWD vs ADS 日期和金额对账（允许 0.01 精度差）

该修复解决：source-side deletion / disappearing partition 导致旧 ADS 分区残留的问题。

> **工程 trade-off**：先删旧分区再重建并非原子操作；中途失败时由任务失败和质量门禁暴露，生产级系统可用 staging/swap 等方式进一步降低窗口。

创建 MySQL BI 应用表：

```bash
mysql -u root -p < mysql/01_create_retail_bi_tables.sql
```

账号脚本中的密码必须在本地替换，不能把真实密码提交到仓库：

```text
mysql/02_create_retail_bi_users.local.sql
```

同步单日数据：

```bash
bash sync/01_sync_sales_overview_to_mysql.sh 2026-04-08
```

同步 8 个演示日期：

```bash
bash sync/02_backfill_sales_overview_to_mysql.sh
```

同步脚本具有以下保护：

- Hive 指定日期必须有且只能有一行；
- MySQL 使用日期主键和 `ON DUPLICATE KEY UPDATE` 实现幂等写入；
- 写入后检查目标端行数；
- 对比业务日期和五项经营指标，确保源端与目标端结果一致；
- 对账不一致时返回非零状态。

### 5.3 启动 Spring Boot 指标服务

后端目录：

```text
backend/retail-bi-server/
```

后端通过环境变量连接 MySQL BI 应用库。公开仓库不应记录真实数据库密码、主机地址或个人环境配置。

PowerShell 示例：

```powershell
cd backend\retail-bi-server

$env:RETAIL_DB_HOST = "your_mysql_host"
$env:RETAIL_DB_PORT = "3306"
$env:RETAIL_DB_NAME = "retail_bi"
$env:RETAIL_DB_USERNAME = "retail_api_user"
$env:RETAIL_DB_PASSWORD = "your_local_password"
$env:SERVER_PORT = "8080"

.\mvnw.cmd clean test
.\mvnw.cmd spring-boot:run
```

`application.yml` 可为本地开发提供默认值，但正式部署应通过环境变量显式覆盖。密码始终必须从环境变量传入。

可覆盖的环境变量：

```text
RETAIL_DB_HOST
RETAIL_DB_PORT
RETAIL_DB_NAME
RETAIL_DB_USERNAME
RETAIL_DB_PASSWORD
SERVER_PORT
```

运行后先检查：

```text
GET http://localhost:8080/api/v1/health
```

### 5.4 API

#### 健康检查

```http
GET /api/v1/health
```

健康检查不访问业务表，用于确认应用进程正常运行。

#### 单日销售概览

```http
GET /api/v1/dashboard/overview?date=2009-12-03
```

规则：

- `date` 必填；
- 日期不能晚于当前日期；
- 查不到数据时返回 `404`；
- 返回统一业务响应和 `requestId`。

#### 日期范围趋势

```http
GET /api/v1/dashboard/overview/trend?startDate=2009-12-01&endDate=2009-12-03
```

规则：

- `startDate`、`endDate` 必填；
- 日期格式为 `yyyy-MM-dd`；
- 两个日期都不能晚于当前日期；
- 开始日期不能早于结束日期；
- 单次范围最多包含 31 个自然日；
- 返回结果按 `dt` 升序排列。

#### 环比查询

```http
GET /api/v1/dashboard/comparison?date=2009-12-13
```

规则：

- `date` 必填；
- 查找同一 `source_system` 下上一可用业务日（不是固定 `date - 1`）；
- 日期有缺口时跳过缺失日期；
- 上一指标为 0 时对应 change percentage 返回 null，避免除 0；
- 找不到上一可用业务日时 `comparisonAvailable=false`。

#### 经营异常查询

```http
GET /api/v1/dashboard/anomalies?startDate=2010-09-01&endDate=2010-09-30
```

规则：

- `startDate`、`endDate` 必填；
- 返回范围内 HIGH / MEDIUM 等级异常记录；
- 包含异常等级、主要驱动指标和销售损失金额。

成功响应示例（legacy profile，2026-04-08）：

```json
{
  "code": 200,
  "message": "success",
  "data": [
    {
      "dt": "2026-04-08",
      "totalSales": 53230287.48,
      "totalOrders": 36969,
      "totalCustomers": 5878,
      "totalQuantity": 32118447,
      "avgOrderValue": 1439.86,
      "sourceSystem": "hive_ads"
    }
  ],
  "requestId": "00979494-150e-4c13-a1a4-a61ee32b0f67"
}
```

参数错误示例：

```json
{
  "code": 400,
  "message": "开始日期不能为空",
  "data": null,
  "requestId": "bde1111f-bb87-4a78-bfd7-c9524f397d7e"
}
```

后端通过 `X-Request-Id` 请求头和响应体中的 `requestId` 串联请求日志。未传入请求 ID 时，过滤器会自动生成 UUID。

### 5.5 前端接入

独立 React 分析平台通过以下接口加载趋势数据：

```text
GET {baseUrl}/api/v1/dashboard/overview/trend
```

前端适配器会把接口返回转换为统一 `ParsedTable`，继续复用：

- 字段识别；
- 描述统计；
- 相对位置；
- CSV 导出；
- 时间趋势图。

当前后端 CORS 允许本机开发前端和已部署域名：

```text
http://localhost:*
http://127.0.0.1:*
https://datainsightkit.com
https://2026heita.github.io
```

Methods: GET / OPTIONS
暴露: X-Request-Id

如需让其他正式域名直接访问后端，必须显式增加并评估 HTTPS、鉴权和网络暴露风险。不要为了临时联调使用无限制 `*` 放行。

### 5.6 演示数据说明

在 engineering_legacy_3x 历史工程验证中，`2026-04-08` 是主回归业务日期，经营总览指标为：

```text
销售额      53,230,287.48
订单数      36,970
客户数       5,878
销量     32,118,447
客单价        1,439.82
```

`2026-04-01` 至 `2026-04-07` 用于验证多日分区、回刷、同步、趋势接口和前端时间序列链路。多个演示日期结果相同，不应解释为业务连续多天完全一致。

---

## 6. 数据说明

原始表主要字段：

```text
Invoice
StockCode
Description
Quantity
InvoiceDate
Price
CustomerID
Country
```

销售金额：

```text
amount = Quantity × Price
```

业务指标默认基于 DWD 清洗后的有效订单统计，不包含：

- 无效数量；
- 无效价格；
- 空客户；
- 取消或退货订单；
- 关键字符串空值；
- 日期无法正常解析的数据。

ODS Raw 和 ODS Reject 属于技术接入与异常追踪层，不直接作为业务指标统计来源。

### 6.1 DWD 字段标准化与重跑基线

DWD 层对以下字段执行标准化清洗：

- `invoice`：TRIM 去除首尾空格
- `stockcode`：TRIM + UPPER 转大写
- `description`：TRIM 去除首尾空格
- `country`：TRIM 去除首尾空格
- `customerid`：TRIM + 去除纯数字 ID 末尾的 `.0`（如 `17850.0` → `17850`）

**重跑 DWD 前的基线记录**

修改 DWD 清洗逻辑后，重跑前应记录旧基线：

```sql
SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT invoice) AS invoices,
  COUNT(DISTINCT customerid) AS customers,
  COUNT(DISTINCT stockcode) AS products,
  SUM(quantity) AS quantity_sum,
  ROUND(SUM(amount), 2) AS amount_sum
FROM dwd_retail_clean_hive
WHERE dt = '2026-04-08';
```

重跑后再次执行上述查询，并对比以下指标：

- **行数**：不应意外下降（标准化不应过滤有效数据）
- **数量和金额**：原则上不应变化（同一批订单的 quantity 和 amount 不变）
- **客户数、订单数、商品数**：可能因空格或 `.0` 标准化小幅下降（如 `17850.0` 和 `17850` 合并为同一客户）

**标准化效果验证**

使用 `hive_sql/32_dwd_normalization_validation_hive.sql` 验证标准化效果：

```bash
hive --hiveconf bizdate=2026-04-08 -f hive_sql/32_dwd_normalization_validation_hive.sql
```

预期结果：

- 各字段首尾空格数量：0
- `customerid` 以 `.0` 结尾数量：0
- `stockcode` 全部为大写

### 6.2 样例数据

仓库提供最小样例数据：

```text
sample_data/retail_sample.csv
```

该文件用于验证 Hive 源表和数仓脚本能否在独立环境运行，不代表完整原始数据集。全量数据体积较大，公开仓库中不上传。

本地部署说明：

```text
docs/setup_local_hive.md
```

---

## 7. ODS 数据入口设计

### 7.1 ODS Raw 原始落地

表名：

```text
ods_retail_raw_hive
```

设计原则：

- 所有业务字段先按 `STRING` 保存；
- 不在原始落地阶段执行数值强制转换；
- 不根据订单日期提前删除数据；
- 按 ETL 处理批次 `batch_dt` 分区；
- 使用 `INSERT OVERWRITE` 支持同批次安全重跑。

链路：

```text
retail → ods_retail_raw_hive
```

原始层使用字符串的原因是保留真实异常值。例如 `Quantity='abc'` 如果过早转换为整数，只会得到 `NULL`，无法再区分原值为空还是格式错误。

### 7.2 ODS Reject 技术解析异常隔离

表名：

```text
ods_retail_reject_hive
```

当前 Reject 规则覆盖 6 类技术解析异常（按优先级排序）：

1. `EMPTY_INVOICE_DATE`：InvoiceDate 为空
2. `DATE_PARSE_FAILED`：InvoiceDate 无法按支持的 4 种格式解析
3. `EMPTY_QUANTITY`：quantity 为空
4. `QUANTITY_PARSE_FAILED`：quantity 无法转换为 BIGINT
5. `EMPTY_PRICE`：price 为空
6. `PRICE_PARSE_FAILED`：price 无法转换为 DECIMAL(10,2)

支持的日期格式：

```text
yyyy-MM-dd HH:mm:ss
yyyy-MM-dd HH:mm
d/M/yyyy HH:mm:ss
d/M/yyyy HH:mm
```

Reject 表保留：

```text
原始字段
parsed_bizdate
reject_code
reject_reason
batch_dt
```

当前 Reject 已扩展到 6 类技术解析异常（包括数量和价格格式异常）。业务异常（如取消订单、空客户等）仍由 DWD 清洗规则识别。

### 7.3 正常业务 ODS

表名：

```text
ods_retail_hive
```

正常 ODS 不再直接读取源表，而是从 ODS Raw 读取。只有满足技术解析条件（日期可解析、数量可转 BIGINT、价格可转 DECIMAL）且属于当前 `bizdate` 的记录才进入对应 `dt` 分区。

链路：

```text
ods_retail_raw_hive → ods_retail_hive
```

---

## 8. Hive 主链路执行

### 8.1 完整主入口

```bash
bash hive_sql/run_all_hive.sh 2026-04-08
```

当前 `run_all_hive.sh` 共 20 个步骤：

```text
01  创建 ODS Raw 表
02  创建 ODS Reject 表
03  创建正常 ODS 表
04  加载 ODS Raw 分区
05  加载 ODS Reject 分区
06  加载正常 ODS 分区
07  执行 ODS 入仓完整性门禁
08  执行 ODS 内容质量检查
09  创建 DWD 表
10  加载 DWD 分区
11  执行 DWD 质量门禁
12  构建客户价值 DWS
13  构建国家销售 DWS
14  构建高价值客户销售贡献 ADS
15  构建客户层级分布 ADS
16  构建国家销售排行 ADS
17  构建高价值客户商品偏好 ADS
18  执行 DWS / ADS 结果门禁
19  构建星型模型并执行星型模型门禁
20  展示最终结果
```

脚本使用：

```bash
set -Eeuo pipefail
```

任意 SQL 文件、质量门禁或子脚本返回失败时，主链路会立即停止。

### 8.2 其他 Shell 工具

```text
run_backfill_hive.sh
按日期升序执行区间回刷。

run_t1_window_hive.sh
重跑 bizdate 前一天和当天，用于晚到数据或 T+1 修正。

run_idempotency_check_hive.sh
重跑指定日期，并比较 8 张核心 ODS / DWD / DWS / ADS 表的行数和两组 CRC32 指纹。

run_quality_gate_hive.sh
执行 DWD 质量门禁。

run_result_quality_gate_hive.sh
执行 DWS / ADS 结果门禁。

run_star_schema_hive.sh
执行 13 步星型模型链路和最终门禁。

run_star_quality_gate_hive.sh
执行 17 条星型模型规则。

check_scd2_backfill_guard.sh
阻止已有后续快照时单独重跑历史日期。

run_daily_hive_profiled.sh
执行日常链路并记录各步骤耗时，支持局部重跑。
```

执行示例：

```bash
bash hive_sql/run_backfill_hive.sh 2026-04-01 2026-04-08
bash hive_sql/run_t1_window_hive.sh 2026-04-08
bash hive_sql/run_idempotency_check_hive.sh 2026-04-03
bash hive_sql/check_scd2_backfill_guard.sh 2026-04-08
bash hive_sql/run_quality_gate_hive.sh 2026-04-08
bash hive_sql/run_result_quality_gate_hive.sh 2026-04-08
bash hive_sql/run_star_schema_hive.sh 2026-04-08
```

### 8.3 日常运行与局部重跑

表已经创建后，可使用：

```bash
bash hive_sql/run_daily_hive_profiled.sh 2026-04-08
```

该脚本：

- 默认不重复单独执行建表 SQL；
- 默认不执行详细 ODS 样例和最终结果报告；
- 记录每一步和整条链路耗时；
- 支持从指定阶段继续执行。

局部重跑：

```bash
# 从 DWD 开始
bash hive_sql/run_daily_hive_profiled.sh 2026-04-08 dwd

# 从 DWS / ADS 开始
bash hive_sql/run_daily_hive_profiled.sh 2026-04-08 mart

# 从星型模型开始
bash hive_sql/run_daily_hive_profiled.sh 2026-04-08 star
```

可选参数：

```bash
RUN_REPORTS=1 bash hive_sql/run_daily_hive_profiled.sh 2026-04-08
RUN_STAR=0 bash hive_sql/run_daily_hive_profiled.sh 2026-04-08
```

### 8.4 MySQL 阶段辅助脚本

`scripts/` 目录保留 MySQL 阶段的本地执行与调度模拟脚本：

```text
10_run_etl.bat
Windows 本地快速执行 MySQL 版 08_run_all.sql。

26_scheduler_demo.bat
串联 MySQL ETL、批次日志和可阻断数据质量检查。

run_etl_linux.sh
Linux 环境下执行 MySQL ETL，并记录 START / SUCCESS / FAILED 状态。
```

这些脚本不参与 Hive 主链路，也不替代 DolphinScheduler 中的 Hive DAG。

---

## 9. 数据质量体系

项目当前采用：

```text
ODS 入仓完整性门禁
+
DWD / DWS-ADS / 星型模型三级业务质量门禁
```

### 9.1 ODS 入仓完整性门禁

文件：

```text
hive_sql/10_check_ods_ingestion_hive.sql
```

检查：

```text
源表行数 = ODS Raw 行数
预期正常 ODS 行数 = 正常 ODS 实际行数
预期 Reject 行数 = Reject 实际行数
```

使用：

```sql
ASSERT_TRUE(...)
```

断言成立时 Hive 可能显示 `NULL`，这是正常现象；条件不成立时 SQL 会抛出异常并阻断下游任务。

### 9.2 ODS 内容质量检查

文件：

```text
hive_sql/10_check_ods_retail_hive.sql
```

用于展示：

- 正常 ODS 数据量；
- 核心字段空值；
- 数量和价格异常；
- 取消或退货订单；
- Reject 数量和分类；
- 正常及异常样例。

该文件用于数据画像和告警，不承担入仓完整性阻断。

### 9.3 DWD、结果层和星型模型门禁

相关文件：

```text
23_quality_log_hive.sql
创建 DWD 质量日志表。

24_load_quality_log_hive.sql
写入 6 条 DWD 规则。

25_check_quality_log_hive.sql
查询 DWD 规则结果。

27_load_result_quality_log_hive.sql
创建并写入 11 条 DWS / ADS 结果规则。

28_load_star_quality_log_hive.sql
创建并写入 17 条星型模型规则。
```

质量日志主要字段：

```text
rule_code
table_name
check_item
check_level
actual_value
threshold_value
abnormal_cnt
check_status
check_detail
check_time
dt
```

规则处理方式：

- `BLOCK + FAIL`：返回非零状态并阻断下游；
- `WARN + FAIL`：保留告警但不阻断；
- SQL 无法执行或结果无法读取：按门禁失败处理。

#### DWD 门禁

```text
DWD_001 - DWD_006
```

覆盖：

- 无效数量；
- 无效价格；
- 空客户；
- DWD 分区非空；
- ODS 理论有效行数与 DWD 实际行数对账；
- DWD 时间格式标准化。

#### DWS / ADS 结果门禁

```text
RESULT_001 - RESULT_011
```

覆盖：

- DWS 分区非空；
- DWD 与 DWS 销售金额对账；
- 核心 ADS 分区非空；
- 客户数和销售额占比汇总；
- 高价值客户贡献率范围。

#### 星型模型门禁

```text
STAR_001 - STAR_017
```

当前 17 条规则均为 BLOCK，覆盖：

- 用户维度分区非空；
- 每个客户只有一个当前版本；
- SCD2 日期范围合法；
- 当前版本 `end_date` 正确；
- 商品、日期和地理业务键唯一；
- 事实表分区非空；
- DWD 与事实表行数、金额一致；
- `order_line_id` 唯一；
- 事实表与星型 DWS 客户数、金额一致。

项目已验证门禁的成功和失败路径：

- 正常业务日期下，`STAR_001 - STAR_017` 全部通过；
- 空分区测试日期会触发 `STAR_001`、`STAR_008` 失败，并返回退出码 `1`。

---

## 10. 星型模型扩展

`11-22` 是基于 DWD 清洗明细构建的星型模型扩展链路，不替代原 DWS / ADS 指标口径。

```text
dwd_retail_clean_hive
  ↓
├── dim_user
├── dim_product
├── dim_date
└── dim_geo
  ↓
fact_order
  ↓
dws_customer_value_star_hive
  ↓
star_quality_log_hive
```

执行：

```bash
bash hive_sql/run_star_schema_hive.sh 2026-04-08
```

### 10.1 SCD2 用户维度

`dim_user` 保存：

```text
user_id
customerid
country
start_date
end_date
is_current
dt
```

设计逻辑：

- 新客户生成首个版本；
- 属性未变化时延续原版本；
- 属性变化时关闭旧版本并生成新版本；
- 每个 `dt` 分区保存截至当天的完整 SCD2 历史快照；
- 事实表按订单日期匹配有效期内的用户版本，而不是只关联当前版本。

> **重要说明**：每日物化快照 ≠ 每天产生一个 SCD2 新版本。只有当跟踪属性（如 country）发生变化时，才会关闭旧版本并创建新版本。属性未变化时，现有 current 版本被延续到新的 dt 分区。

代理键策略：

```text
首日或新版本 user_id：
md5(customerid | country | start_date)

商品 product_id：
md5(stockcode)
```

**SCD2 多版本属性变化已通过真实业务数据验证**：

在 2010-03-04 对 customerid=12431 的 Belgium → Australia 真实属性变化进行了重点验证：
- Belgium 旧版本（user_id=5b3505b2200cc7e59ae46e9c5a199e99）关闭至 2010-03-03，is_current=false
- Australia 新版本（user_id=57d1ccdac3e283cfd7d9eeb640f56ef5）从 2010-03-04 生效，is_current=true
- 2010-03-04 fact_order 正确关联 Australia 新 user_id，fact_rows=17，fact_amount=394.59
- 质量结果：17/17/17/0

Star Schema 连续真实验证至 2010-03-04，覆盖 73 个真实业务日期。

### 10.2 历史回刷保护

按业务日物化完整历史快照的 SCD2 存在日期依赖。已经存在更晚快照时，不能只覆盖中间某一天。

执行：

```bash
bash hive_sql/check_scd2_backfill_guard.sh 2026-04-08
```

规则：

- 本次日期等于当前最大分区：允许；
- 本次日期晚于当前最大分区：允许；
- 本次日期早于当前最大分区：阻断，并提示按区间升序回刷。

该保护脚本当前是独立工具，尚未自动接入 `run_all_hive.sh`。

### 10.3 当前星型模型验收结果

**历史工程验证（engineering_legacy_3x，2026-04-08）**：

```text
dim_user：5,878 个版本，5,878 个当前版本，5,878 个客户
dim_product：4,630 行，4,630 个唯一商品
dim_date：1 行，1 个唯一日期
dim_geo：41 行，41 个唯一国家
fact_order：2,416,593 行，order_line_id 唯一
DWD / fact_order：行数均为 2,416,593
DWD / fact_order：金额均为 53,230,287.48
STAR_001 - STAR_012：全部 PASS（历史工程验证，当时为 12 条规则）
```

**Canonical 真实数据验证（2009-12-01 ~ 2011-12-09）**：

Star Schema 连续真实验证至 2010-03-04，覆盖 73 个真实业务日期。当前规则定义为 STAR_001 - STAR_017，共 17 条 BLOCK 规则。2010-03-04 质量结果为 17/17/17/0。

---

## 11. MySQL 阶段

### 11.1 安全认证

项目不在脚本中保存明文密码，而是使用 `mysql_config_editor`：

```powershell
mysql_config_editor set `
  --login-path=retail_local `
  --host=127.0.0.1 `
  --port=3306 `
  --user=root `
  --password
```

测试：

```powershell
mysql --login-path=retail_local retail_project -e "SELECT DATABASE();"
```

### 11.2 Windows 调度模拟

在项目根目录执行：

```powershell
.\scripts\26_scheduler_demo.bat
```

流程：

```text
确认 etl_task_log 存在
→ 写入当前批次 START
→ 执行 08_run_all.sql
→ 执行 20 项数据质量门禁
→ 成功写入 SUCCESS
→ 失败写入 FAILED
→ 只查询当前 batch_id
```

`sql/12_check_etl_log.sql` 使用 `BINARY` 精确匹配批次号，避免会话变量和表字段排序规则不一致导致 `Illegal mix of collations`。

### 11.3 MySQL 数据质量门禁

文件：

```text
sql/13_data_quality_check.sql
```

当前包含 20 项 DWD / DWS / ADS 检查。所有规则先写入临时结果表并统一输出：

```text
check_order
check_name
actual_value
expected_rule
check_status
```

任意规则失败时执行：

```sql
SIGNAL SQLSTATE '45000'
```

使 MySQL 客户端返回非零状态，批处理进入 `FAILED` 分支。

已验证结果：

```text
total_check_cnt   = 20
passed_check_cnt  = 20
failed_check_cnt  = 0
overall_status    = PASS
```

已验证批次日志：

```text
START   = 1
SUCCESS = 1
FAILED  = 0
batch_status = SUCCESS
```

---

## 12. DolphinScheduler 调度设计

工作流逻辑名称：

```text
retail_hive_offline_warehouse_daily
```

### 12.1 已完成的部署实践

项目文档记录了以下部署过程：

- DolphinScheduler 3.2.2 Docker Standalone；
- 元数据库由 H2 内存库迁移到 MySQL，实现项目、工作流和实例持久化；
- 自定义镜像加入 MySQL Connector/J；
- 自定义镜像加入 OpenSSH Client；
- Shell 节点通过 SSH 调用 Hadoop/Hive 主机；
- 12 节点 DAG 已完成成功验收。

详细说明：

```text
dolphinscheduler/deployment_mysql_ssh.md
dolphinscheduler/workflow_design.md
dolphinscheduler/hive_task_nodes.md
```

### 12.2 当前导入 JSON

文件：

```text
dolphinscheduler/retail_hive_offline_warehouse_daily_demo.json
```

当前状态：

- JSON 已通过 Python 标准解析；
- 共 12 个任务节点；
- `schedule` 为 `null`，导入后不会自动创建启用中的定时计划；
- `globalParams`、`globalParamList`、`globalParamMap` 已统一；
- 公开仓库只保存占位参数。

占位值：

```text
bizdate=$[yyyy-MM-dd-1]
HIVE_USER=your_hive_user
HIVE_HOST=your_hive_host
PROJECT_HOME=/home/your_user/retail_hive_project
```

DolphinScheduler 3.2.2 导入文件中：

```text
processTaskRelationList
```

必须存在且非空，并使用合法的数值任务编码，否则工作流关系无法正常导入。

### 12.3 当前 12 节点 DAG

```text
ods_create_retail
→ ods_load_retail
→ dwd_create_table
→ dwd_load_clean_data
→ dwd_quality_gate
  ├─ dws_customer_value
  │  ├─ ads_high_value_customer_sales_contribution
  │  ├─ ads_customer_level_distribution
  │  └─ ads_high_value_customer_preference
  └─ dws_sales_summary
     └─ ads_country_sales_rank

四个 ADS 节点
→ hive_data_quality_check
```

当前 JSON 是已验收的原主链路演示 DAG，尚未同步：

- ODS Raw；
- ODS Reject；
- ODS 入仓完整性门禁；
- DWS / ADS 结果门禁；
- 星型模型；
- 星型模型门禁。

因此应明确区分：

```text
当前最完整执行链路：
hive_sql/run_all_hive.sh

已验收调度演示：
DolphinScheduler 12 节点 JSON
```

导入后应先修改环境参数并手动验证，再根据目标环境时区和业务窗口配置定时计划。

---

## 13. 回刷、T+1 与幂等性

### 13.1 区间回刷

```bash
bash hive_sql/run_backfill_hive.sh 2026-04-01 2026-04-08
```

脚本按日期升序执行，任意一天失败后停止。

### 13.2 T+1 修正

```bash
bash hive_sql/run_t1_window_hive.sh 2026-04-08
```

用于重跑前一天和当天。

### 13.3 内容指纹幂等性检查

```bash
bash hive_sql/run_idempotency_check_hive.sh 2026-04-03
```

当前脚本对 8 张核心 ODS / DWD / DWS / ADS 表比较：

- 行数；
- 第一组 CRC32 内容指纹；
- 第二组反向字符串 CRC32 内容指纹。

该方法用于降低"行数相同但内容发生变化"的漏检风险。它是工程验收指纹，不是密码学哈希。

当前脚本尚未覆盖：

- ODS Raw；
- ODS Reject；
- 全部星型模型表。

---

## 14. 性能分析与 SQL 优化

### 14.1 已完成的 SQL 优化

项目保留了以下 Hive 优化实践：

1. **国家维度数据倾斜识别**
   `country='United Kingdom'` 在一次 DWD 分区中约有 2,175,699 行，占约 69.6%，属于明显热点 Key。

2. **手写 Salt 与两阶段聚合**
   `04_dws_sales_summary_hive.sql` 针对 `GROUP BY country` 使用 Salt。销售额先局部聚合再回收；订单数和客户数采用独立去重路径，避免加盐后重复计数。

3. **MAPJOIN**
   DWD 明细大表关联 DWS 客户价值小表时使用 `MAPJOIN`，减少 Shuffle。

4. **分区裁剪**
   ADS Join 增加 `dws.dt='${hiveconf:bizdate}'`，避免跨日期分区关联导致结果放大。

5. **DWD 清洗修正**
   补充 `stockcode`、`country`、`invoicedate` 非空和非空字符串过滤。

6. **执行计划验证**
   使用 `EXPLAIN` 确认查询中出现 `Map Join Operator`。

该过程形成：

```text
发现倾斜
→ 定位热点 Key
→ 改写 SQL
→ EXPLAIN 验证
→ 全链路回归
```

### 14.2 全链路耗时分析

一次单机虚拟机完整日常链路实测：

```text
TOTAL_PIPELINE：1963 秒，约 32 分 43 秒
```

主要耗时：

```text
星型模型链路                    758 秒
DWS / ADS 结果质量门禁          237 秒
ODS 入仓完整性门禁              151 秒
DWD 质量门禁                    130 秒
国家销售 DWS                    109 秒
高价值客户商品偏好 ADS           98 秒
高价值客户销售贡献 ADS           92 秒
```

该结果只反映当时的单机虚拟机、Hive 执行引擎和资源配置，不代表生产 SLA。

当前已经完成步骤级耗时定位，但没有为了缩短少量时间进行高风险的大规模 SQL 合并或调度重写。开发阶段主要通过局部重跑减少等待。

---

## 15. 已验证结果

### 15.1 当前 `dt=2026-04-08` 回归结果

ODS 入仓对账：

```text
源表 retail                 3,202,113
ODS Raw                     3,202,113
source_raw_diff                     0

预期正常 ODS               3,202,113
正常 ODS                   3,202,113
expected_ods_diff                   0

预期 Reject                        0
实际 Reject                        0
expected_reject_diff                0
```

核心结果：

```text
DWD 行数                  2,416,593
fact_order 行数           2,416,593
客户数                        5,878
商品数                        4,630
国家数                           41
总销售额               53,230,287.48
高价值客户销售贡献率          86.68%
```

BI 导出：

```text
High Value Sales Contribution Pct   86.68
Total Customer Count              5878.00
Total Sales                   53230287.48
```

质量结果：

```text
ODS 三组差值                         0 / 0 / 0
技术 Reject 数量                             0
MySQL 数据质量门禁                  20 / 20 PASS
当前 MySQL 批次日志       START=1 / SUCCESS=1 / FAILED=0
```

### 15.2 历史 7 天工程验证

`docs/multiday_validation_screenshots/` 保存了较早数据版本的多日分区、区间回刷、幂等性和 T+1 验证截图。

历史结果曾显示：

```text
ODS：2026-04-01 到 2026-04-07，每天 3,202,113 行
DWD：2026-04-01 到 2026-04-07，每天 3,124,956 行
国家销售排行：每天 43 行
```

这组历史结果与当前 `2026-04-08` 回归中的：

```text
DWD = 2,416,593
国家 = 41
```

不是同一数据或清洗规则基线，不能直接横向比较。

历史截图用于证明脚本具备跨日期分区、回刷和重跑能力，不用于证明当前完整数据版本连续 7 天都得到相同结果。

### 15.3 BI 应用链路验证

**历史工程验证（engineering_legacy_3x）**：

```text
Hive ads_sales_overview_daily_hive
→ sync/01_sync_sales_overview_to_mysql.sh
→ MySQL bi_sales_overview_daily
→ Spring Boot trend API
→ React 时间趋势
```

趋势接口已返回 `2026-04-01` 至 `2026-04-08` 共 8 行数据，并保留 `sourceSystem=hive_ads`。

**Canonical 真实数据验证**：

Hive ADS 已完成全范围验证（604 个真实业务日期，2009-12-01 ~ 2011-12-09）：

![Canonical ADS 全范围验证](docs/canonical_validation_screenshots/canonical_ads_sales_overview_full_validation.png)
> 验证结果：row_count=604，distinct_dt=604，min_dt=2009-12-01，max_dt=2011-12-09，total_sales=17,743,429.16。

Hive → MySQL 同步已完成全范围验证：

![Canonical Hive-MySQL 同步验证](docs/canonical_validation_screenshots/canonical_hive_mysql_full_sync_validation.png)
> 验证结果：source_rows=604，target_rows=604，日期范围 2009-12-01 ~ 2011-12-09，total_sales=17,743,429.16，逐行对账 PASS。
> MySQL 中保留两组数据：旧历史展示数据（source_system=hive_ads，8 行，2026-04-01 ~ 2026-04-08）和 canonical 数据（source_system=retail_canonical_ads，604 行）。

Spring Boot API 已真实连接 canonical serving 数据：

![Canonical Spring API 趋势验证](docs/canonical_validation_screenshots/canonical_spring_api_trend_validation.png)
> 趋势接口真实验证 2009-12-01 ~ 2009-12-03，返回数据与 Hive ADS / MySQL 完全一致，sourceSystem=retail_canonical_ads。

Spring Boot 环比业务语义已修正并真实验证：

![Canonical Spring 环比业务日期验证](docs/canonical_validation_screenshots/canonical_spring_comparison_business_date_validation.png)
> 真实验证：2009-12-13 → 2009-12-11（跳过无数据的 2009-12-12），comparisonAvailable=true，两边 sourceSystem 均为 retail_canonical_ads。
> 连续日期回归：2009-12-03 → 2009-12-02 仍然 PASS。
> Spring Boot 自动化测试：单元测试与集成测试全部通过，其中包含基于 Testcontainers + MySQL 8 的 SalesOverviewMapper 集成测试，覆盖单日查询、日期范围查询和上一可用业务日查询；Backend CI 执行 `./mvnw -B clean verify`。

参数校验已验证：

- 缺少开始日期返回 `400` 和"开始日期不能为空"；
- 日期顺序错误进入统一异常响应；
- 查询范围超过 31 天进入统一异常响应；
- 日期格式错误进入统一异常响应；
- 错误响应和正常响应都包含 `requestId`。

---

## 16. 运行结果截图

### 16.1 调度和 ADS 结果

目录：

```text
docs/result_screenshots/
```

文件：

```text
01_ds_workflow_instance_success.png
02_ds_dag_quality_gate_success.png
03_dwd_quality_gate_passed.png
04_ads_sales_contribution_20260408.png
05_ads_customer_level_distribution_20260408.png
06_ads_country_sales_rank_20260408.png
07_ads_customer_preference_20260408.png
08_light_bi_dashboard_top_20260408.png
09_light_bi_dashboard_bottom_20260408.png
```

核心截图预览：

![DolphinScheduler 工作流实例成功](result_screenshots/01_ds_workflow_instance_success.png)

![DolphinScheduler DAG 与质量门禁成功](result_screenshots/02_ds_dag_quality_gate_success.png)

![DWD 质量门禁通过](result_screenshots/03_dwd_quality_gate_passed.png)

这些 DolphinScheduler 截图对应已验收的 12 节点演示 DAG，不代表当前 20 步 Shell 完整链路已经全部拆成调度节点。

轻量 BI Dashboard 截图：

- `08_light_bi_dashboard_top_20260408.png`：高价值客户贡献和客户分层；
- `09_light_bi_dashboard_bottom_20260408.png`：国家销售 Top10 和高价值客户偏好商品 Top10。

### 16.2 历史多日验证截图

目录：

```text
docs/multiday_validation_screenshots/
```

文件：

```text
01_7day_ods_partition_check.png
02_7day_dwd_partition_check.png
03_7day_ads_country_rank_check.png
04_idempotency_check_20260403.png
05_t1_window_check_20260406_20260407.png
06_dwd_cleaning_quality_20260401.png
```

该目录属于历史验证基线，具体数据版本说明以目录内 README 为准。

---

## 17. 本地最小复现

完整说明：

```text
docs/setup_local_hive.md
```

### 17.1 环境检查

```bash
hdfs dfs -ls /
hive -e "SHOW DATABASES;"
```

两个命令都正常后再执行项目。

### 17.2 创建 Hive 样例源表

> `00_bootstrap_sample_source_hive.sql` 会执行 `DROP TABLE IF EXISTS retail PURGE`，只应在独立测试环境使用。

```bash
hive \
  --hiveconf source_file=/path/to/retail_project/sample_data/retail_sample.csv \
  -f hive_sql/00_bootstrap_sample_source_hive.sql
```

检查：

```bash
hive -S -e "SHOW TABLES LIKE 'retail';"
hive -e "SELECT COUNT(*) FROM retail;"
```

### 17.3 执行完整链路

```bash
bash hive_sql/run_all_hive.sh 2026-04-08
```

仓库目录名是：

```text
hive_sql/
```

服务器部署时可以上传为：

```text
${PROJECT_HOME}/hive/
```

但 DolphinScheduler 的 `PROJECT_HOME` 和任务命令必须与真实部署路径一致。

---

## 18. 项目亮点

1. 完成 MySQL 到 Hive 的核心链路迁移，构建 ODS Raw、Reject、正常 ODS、DWD、DWS、ADS 和星型模型。

2. 原始字段先按字符串落地，避免日期或数值异常在进入 ODS 前静默丢失。

3. 建立技术解析异常 Reject 分流，保存原值、异常编码、原因和批次，覆盖日期、数量和价格 6 类技术异常。

4. 使用三组数量对账和 `ASSERT_TRUE` 实现 ODS 入仓完整性门禁。

5. 使用 ORC、日期分区、`bizdate` 和 `INSERT OVERWRITE PARTITION` 支持分区级重跑。

6. 建立 ODS 入仓门禁和 DWD、DWS/ADS、星型模型三级业务门禁。

7. 设计区间回刷、T+1 修正、内容指纹幂等性检查和 SCD2 历史回刷保护。

8. 实现按业务日物化完整历史快照的 SCD2 用户维度和按有效期关联的事实表。

9. MySQL 调度演示实现当前批次 `START / SUCCESS / FAILED` 日志闭环。

10. MySQL 20 项规则失败时通过 `SIGNAL SQLSTATE '45000'` 阻断任务。

11. DolphinScheduler 完成 H2 到 MySQL 元数据库迁移、自定义连接器和 SSH 执行环境配置。

12. DolphinScheduler JSON 使用统一占位参数，避免硬编码真实服务器信息。

13. 针对国家热点 Key 使用 Salt 和两阶段聚合，并使用 MAPJOIN 和 EXPLAIN 验证。

14. 使用步骤级耗时分析定位星型模型和多层质量门禁等主要瓶颈。

---

## 19. 项目边界

本项目不是生产级实时数仓，当前边界包括：

- 使用按业务日期分区覆盖写入的离线批处理，不是 CDC 实时增量；
- DolphinScheduler JSON 尚未同步 Shell 完整 20 步链路；
- 当前 canonical 已验收基线 reject=0；新版 Reject 解析逻辑已支持 4 种日期格式并扩展到 6 类技术 Reject，目前仅完成 10 行功能样本验证，尚未使用新版逻辑对 1,067,371 行 canonical 数据执行完整重跑。
- SCD2 回刷保护脚本尚未自动接入主入口；
- 幂等性指纹只覆盖 8 张核心 ODS / DWD / DWS / ADS 表；
- 历史轻量 BI Dashboard 仍只有截图；当前交互式分析前端位于独立 score-analysis-tool 项目；
- 单机 Hive 完整运行约 30 分钟，性能依赖环境；
- 历史多日截图和当前完整回归不是同一数据版本；
- 项目没有内置 MySQL 到 Hive 自动同步链路；
- Spring Boot 当前提供 overview、trend、comparison 和 anomalies 接口；
- Java 当前读取预聚合日指标，不提供订单明细钻取、分页或任意维度动态聚合；
- 后端尚未加入登录权限、缓存、OpenAPI、Docker；
- 已有 GitHub Actions CI（Backend Maven clean verify、Data Warehouse bash -n + ShellCheck），但尚未实现自动部署、环境晋级、制品发布、回滚等完整 CD；
- 当前 CORS 允许本机开发前端（localhost、127.0.0.1）以及已部署域名（datainsightkit.com、2026heita.github.io），公网部署需要单独配置正式域名和安全策略；
- Hive ADS 范围写入采用动态分区，一次范围式 ADS DML 覆盖 604 个真实业务日期；回刷脚本 `30_backfill_ads_sales_overview_daily.sh` 已实现 stale partition self-healing（先查询并删除目标范围旧分区再重建）；
- Hive → MySQL 同步采用范围式一次 Hive 查询 + 批量 MySQL UPSERT，不是逐日同步；
- 跨系统 DECIMAL 对账需要按数值类型比较，避免 Hive 输出 341.4 与 MySQL DECIMAL 输出 341.40 的字符串格式差异导致假失败；
- Spring Boot 环比接口当前使用"同一 source_system 下上一可用业务日"语义，不是固定"前一日（date.minusDays(1)）"，以应对真实业务日期存在缺口的情况。

这些边界不影响项目作为离线数仓学习和工程能力展示项目，但在简历和面试中应如实说明。

---

## 20. 工程能力总结

本项目能够证明的工程能力包括：

1. **分层建模**：完成 ODS Raw、Reject、正常 ODS、DWD、DWS、ADS 和星型模型设计，并明确各层职责。

2. **数据质量**：通过入仓对账、断言、BLOCK / WARN 规则和批次日志，在多个关键层级阻断错误数据继续下游传播。

3. **可重跑与可追溯**：使用业务日期分区覆盖写入、区间回刷、T+1 修正、指纹幂等检查和 `requestId` 支持问题定位。

4. **维度建模**：实现按业务日物化完整历史快照的 SCD2 用户维度、商品维度、日期维度、地理维度和订单事实表。

5. **调度与运维表达**：完成 DolphinScheduler 演示 DAG、SSH 执行环境、MySQL 元数据库迁移和 Shell 返回码联动。

6. **性能分析**：通过步骤级耗时记录、Salt 两阶段聚合、MAPJOIN 和 EXPLAIN 识别热点与优化机会。

7. **应用闭环**：在 Hive ADS 预计算经营指标，通过 Shell 幂等同步到 MySQL，再由 Spring Boot 提供统一 API，并接入 React 时间趋势分析。

项目当前优先保证口径正确、失败可见、链路可重跑和文档可复现；缓存、权限、实时 CDC、生产级监控等能力仅在真实需求出现时再增加。

---

## 21. 仓库公开与安全说明

公开仓库不要提交：

- 真实服务器账号；
- 真实主机名、内网 IP 或公网 IP；
- 明文数据库密码；
- `RETAIL_DB_PASSWORD`、`.env` 或其他真实环境变量文件；
- MySQL login-path 配置文件；
- 运行日志和性能分析文件；
- `.bak`、`.tmp` 等临时文件；
- 后端 `target/`、IDE 工作区和本地运行产物；
- 大体积全量原始数据；
- 未打码的敏感截图。

当前 DolphinScheduler JSON 只保留占位参数：

```text
your_hive_user
your_hive_host
/home/your_user/retail_hive_project
```

提交前建议执行：

```bash
git status --short
git diff --stat
git diff --cached --name-status
```

确认没有日志、备份、压缩包和误放文件后再提交。

---

返回项目概览：[根目录 README.md](../README.md)
