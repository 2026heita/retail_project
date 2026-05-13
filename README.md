# 零售数据分析离线数仓项目：MySQL、Hive 与 DolphinScheduler 调度实践

## 1. 项目简介

本项目基于电商零售订单数据，围绕订单、客户、商品、国家等维度完成离线数仓建模、业务指标开发、Hive 迁移和 DolphinScheduler 调度编排。

项目分为三个阶段：

1. MySQL 阶段：完成 ODS、DWD、DWS、ADS 四层离线数仓链路，覆盖数据清洗、主题汇总、应用层指标输出、统一执行脚本、ETL 日志记录和数据质量校验。
2. Hive 阶段：将核心链路迁移到 Hive，使用 `dt` 分区、ORC 列式存储、`bizdate` 参数和 `INSERT OVERWRITE PARTITION` 分区覆盖写入，支持指定业务日期重跑。
3. DolphinScheduler 阶段：将 Hive 离线数仓链路拆分为可视化 DAG 任务节点，实现 ODS、DWD、DWS、ADS 和数据质量校验的任务依赖编排、参数化调度、运行状态追踪和结果验收。

本项目重点不是单纯写 SQL 查询，而是展示从原始订单数据清洗、客户价值分层、指标沉淀，到 Hive 离线数仓迁移、DolphinScheduler 调度编排和工程化执行的完整实践过程。

## 2. 技术栈

- MySQL
- Hive
- SQL
- HDFS
- ORC
- Linux Shell
- DolphinScheduler
- Docker / 容器化部署
- SSH / Shell 调度执行
- 离线数仓分层建模
- 数据质量校验
- ETL 批次日志记录

## 3. 项目目录结构

```text
retail_project/
├── README.md
├── sql/
├── hive_sql/
├── dolphinscheduler/
│   ├── dq_check_result.sql
│   ├── etl_task_log_v2.sql
│   ├── hive_task_nodes.md
│   ├── workflow_design.md
│   └── retail_hive_offline_warehouse_daily_import_success.json
├── scripts/
└── docs/
    ├── 25_scheduler_design.txt
    ├── 27_metric_definitions.txt
    ├── interview_talking_points.txt
    └── result_screenshots/
```

说明：原始数据文件较大，仓库中不直接上传完整数据集。运行项目前，需要提前准备同字段结构的订单数据表。

## 4. 数据说明

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

销售金额字段：

```text
amount = Quantity * Price
```

所有指标默认基于清洗后的有效订单数据统计，不包含异常数量、异常价格、空客户和退货订单。

## 5. MySQL 数仓分层设计

```text
ODS 原始订单数据
        ↓
DWD 明细清洗层
        ↓
DWS 主题汇总层
        ↓
ADS 应用指标层
        ↓
数据质量校验
```

DWD 清洗规则：

```text
Quantity > 0
Price > 0
CustomerID IS NOT NULL
Invoice NOT LIKE 'C%'
amount = Quantity * Price
```

DWS 层沉淀客户价值分层和国家销售汇总，ADS 层输出复购率、销售趋势、国家排行、客户收入集中度、客户分层分布、高价值客户偏好和高价值客户销售贡献等指标。

## 6. Hive 迁移设计

Hive 版本采用 ODS、DWD、DWS、ADS 分层结构，并统一使用 `dt` 作为业务日期分区字段。

```sql
PARTITIONED BY (dt STRING)
```

执行任务时通过 `bizdate` 参数传入业务日期：

```sql
'${hiveconf:bizdate}'
```

核心写入方式：

```sql
INSERT OVERWRITE TABLE table_name
PARTITION (dt = '${hiveconf:bizdate}')
```

该方式支持指定业务日期重跑，避免重复执行导致重复数据，并保证离线任务具备幂等性。

## 7. DolphinScheduler 调度设计

工作流名称：

```text
retail_hive_offline_warehouse_daily
```

全局参数：

```text
bizdate = $[yyyy-MM-dd-1]
```

执行方式：DolphinScheduler Shell 节点不在容器内直接执行 Hive，而是通过 SSH 调用部署 Hive 的 Linux 主机执行 Hive SQL。公开仓库中不保留真实服务器账号、真实 IP 或明文密码，统一使用以下占位符：

```text
${HIVE_USER}
${HIVE_HOST}
${PROJECT_HOME}
```

命令模板：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/SQL文件名
"
```

DAG 链路：

```text
ods_create_retail
  -> dwd_create_table
  -> dwd_load_clean_data
      -> dws_customer_value
          -> ads_high_value_customer_sales_contribution
          -> ads_customer_level_distribution
          -> ads_high_value_customer_preference
      -> dws_sales_summary
          -> ads_country_sales_rank

ads_high_value_customer_sales_contribution
ads_customer_level_distribution
ads_country_sales_rank
ads_high_value_customer_preference
  -> hive_data_quality_check
```

## 8. 数据质量校验

数据质量校验目标不是只确认 SQL 是否执行成功，而是进一步确认结果表和核心指标是否可用。校验内容包括：

- DWD 清洗后是否仍存在异常数量、异常价格、空客户、退货订单和异常金额；
- DWS 客户分层结果是否为空；
- ADS 指标表是否生成；
- 指定业务日期 `dt/bizdate` 是否存在结果数据；
- 销售贡献占比、排名、销售额等关键字段是否存在异常范围。

## 9. 项目亮点

1. 完成 MySQL ODS、DWD、DWS、ADS 四层离线数仓建模。
2. 将核心链路迁移到 Hive，补充分区、ORC、参数化和幂等写入设计。
3. 接入 DolphinScheduler，将 Hive 链路拆分为 10 个 Shell 任务节点并形成 DAG 编排。
4. 补充指标口径文档、调度设计文档、任务节点说明、质量校验结果表和调度任务日志表。
5. 围绕高价值客户形成客户分层、客户偏好、客户活跃度、国家分布和销售贡献的完整分析链路。

## 10. 项目边界说明

本项目是面向学习与作品集展示的电商离线数仓项目，主要用于展示 SQL 开发、数仓分层建模、指标沉淀、Hive 迁移、调度编排和数据质量校验能力。项目结果基于当前数据集统计，不等同于真实业务运营指标，也不直接推导实际业务收益。

## 11. GitHub 上传说明

公开仓库中不要上传以下内容：

- 真实服务器账号；
- 真实内网 IP 或公网 IP；
- 明文密码；
- 数据库连接凭据；
- 未打码的运行日志截图；
- 大体积原始数据文件。

本安全版已将远程执行命令统一改为占位符形式，适合公开上传 GitHub。
