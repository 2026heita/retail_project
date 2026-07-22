# 零售数据分析离线数仓项目：MySQL、Hive 与 DolphinScheduler 调度实践

## 1. 项目简介

本项目基于电商零售订单数据，围绕订单、客户、商品、国家等维度完成离线数仓建模、业务指标开发、Hive 迁移和 DolphinScheduler 调度编排。

项目分为三个阶段：

1. **MySQL 阶段**：完成订单清洗、主题汇总、应用层指标输出、统一执行脚本、ETL 日志记录和数据质量校验。
2. **Hive 主链路阶段**：将核心链路迁移到 Hive，构建 `ODS -> DWD -> DWS -> ADS` 分层结构，使用 `dt` 分区、ORC 列式存储、`bizdate` 参数和 `INSERT OVERWRITE PARTITION` 分区覆盖写入，支持指定业务日期重跑。
3. **工程化扩展阶段**：补充区间回刷、T+1 修正窗口、ODS 入仓校验、三级质量门禁、内容指纹幂等性校验和 DolphinScheduler 调度编排；同时实现 `11-22` 星型模型扩展链路，其中用户维度采用每日完整快照式 SCD2，并将星型链路接入统一主脚本。

本项目重点不是单纯写 SQL 查询，而是展示从原始订单数据清洗、客户价值分层、指标沉淀，到 Hive 离线数仓迁移、DolphinScheduler 调度编排和工程化执行的完整实践过程。

---

## 2. 项目架构图

### 2.1 整体工程架构

```mermaid
flowchart LR
    A["原始零售订单数据<br/>retail"] --> B["MySQL 阶段<br/>清洗 / 汇总 / ADS 指标"]
    B --> C["Hive 分层主链路<br/>ODS → DWD → DWS → ADS"]
    C --> Q1["DWD 质量门禁<br/>6 条 BLOCK 规则"]
    Q1 --> D["DWS / ADS 指标产出"]
    D --> Q2["结果质量门禁<br/>BLOCK / WARN"]
    Q2 --> G["星型模型扩展<br/>SCD2 维表 / 事实表 / 星型 DWS"]
    G --> Q3["星型模型质量门禁<br/>12 条规则"]
    Q3 --> H["结果展示与验收<br/>分区 / 对账 / 幂等性"]

    C --> E["工程化执行<br/>单日 / 区间回刷 / T+1"]
    Q1 --> F["DolphinScheduler 12 节点 DAG<br/>原主链路 + DWD 门禁"]
    E --> H
    F --> H

    classDef core fill:#e8f3ff,stroke:#2f80ed,stroke-width:1px,color:#111;
    classDef extend fill:#f4f0ff,stroke:#8b5cf6,stroke-width:1px,color:#111;
    classDef check fill:#eefbf3,stroke:#22a06b,stroke-width:1px,color:#111;
    class C,D,E,F core;
    class G extend;
    class Q1,Q2,Q3,H check;
```

### 2.2 Hive 数仓主链路与星型模型扩展

```mermaid
flowchart TB
    S["retail 源表"] --> ODS["ODS：ods_retail_hive<br/>解析业务日期并写入 dt 分区"]
    ODS --> DWD["DWD：dwd_retail_clean_hive<br/>清洗订单明细并统一时间格式"]

    DWD --> Q1["DWD Gate：quality_log_hive<br/>6 条 BLOCK 规则"]
    Q1 --> DWS1["DWS：dws_customer_value_hive<br/>客户价值分层"]
    Q1 --> DWS2["DWS：dws_sales_summary_hive<br/>国家销售汇总"]

    DWS1 --> ADS1["ADS：高价值客户销售贡献"]
    DWS1 --> ADS2["ADS：客户层级分布"]
    DWS1 --> ADS4["ADS：高价值客户商品偏好"]
    DWS2 --> ADS3["ADS：国家销售排行"]

    ADS1 --> Q2["Result Gate：result_quality_log_hive<br/>11 条结果规则"]
    ADS2 --> Q2
    ADS3 --> Q2
    ADS4 --> Q2

    Q2 --> U["dim_user<br/>每日完整快照式 SCD2"]
    Q2 --> P["dim_product<br/>商品维度快照"]
    Q2 --> T["dim_date<br/>日期维度快照"]
    Q2 --> G["dim_geo<br/>地理维度快照"]
    U --> FO["fact_order<br/>按事实日期命中 SCD2 版本"]
    P --> FO
    T --> FO
    G --> FO
    FO --> STAR["dws_customer_value_star_hive<br/>星型模型客户价值汇总"]
    STAR --> Q3["Star Gate：star_quality_log_hive<br/>12 条星型规则"]

    classDef layer fill:#e8f3ff,stroke:#2f80ed,stroke-width:1px,color:#111;
    classDef ads fill:#fff7e6,stroke:#f59e0b,stroke-width:1px,color:#111;
    classDef star fill:#f4f0ff,stroke:#8b5cf6,stroke-width:1px,color:#111;
    classDef check fill:#eefbf3,stroke:#22a06b,stroke-width:1px,color:#111;
    class ODS,DWD,DWS1,DWS2 layer;
    class ADS1,ADS2,ADS3,ADS4 ads;
    class U,P,T,G,FO,STAR star;
    class Q1,Q2,Q3 check;
```

说明：`00-09` 仍是业务指标主链路；`11-22` 是基于 DWD 的星型模型扩展，不替代原 DWS / ADS 口径。当前 `run_all_hive.sh` 共 15 个步骤，在 DWS / ADS 结果门禁通过后调用 `run_star_schema_hive.sh`，并由星型模型质量门禁完成最终验收。仓库中的 DolphinScheduler 导入 JSON 仍保留原 12 节点 DAG，用于展示原主链路和 DWD 门禁。

## 3. 技术栈

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
- 星型模型维度建模
- 数据质量校验
- ETL 批次日志记录
- HTML + ECharts（轻量 BI Dashboard）

---

## 4. 项目目录结构

```text
retail_project/
├── README.md
├── sample_data/
│   └── retail_sample.csv           # 最小样例数据，用于验证 Hive 主链路
├── sql/
├── hive_sql/
│   ├── 00_ods_retail_hive.sql
│   ├── 00_load_ods_retail_hive.sql
│   ├── 01_dwd_retail_clean_hive.sql
│   ├── 02_load_dwd_retail_clean_hive.sql
│   ├── 03_dws_customer_value_hive.sql
│   ├── 04_dws_sales_summary_hive.sql
│   ├── 05_ads_high_value_customer_sales_contribution_hive.sql
│   ├── 06_ads_customer_level_distribution_hive.sql
│   ├── 07_ads_country_sales_rank_hive.sql
│   ├── 08_ads_high_value_customer_preference_hive.sql
│   ├── 09_check_hive_result.sql
│   ├── 10_check_ods_retail_hive.sql
│   ├── 11_dim_user_scd2_hive.sql
│   ├── 12_load_dim_user_scd2_hive.sql
│   ├── 13_dim_product_hive.sql
│   ├── 14_load_dim_product_hive.sql
│   ├── 15_fact_order_hive.sql
│   ├── 16_load_fact_order_hive.sql
│   ├── 17_dws_customer_value_star_hive.sql
│   ├── 18_load_dws_customer_value_star_hive.sql
│   ├── 19_dim_date_hive.sql
│   ├── 20_dim_geo_hive.sql
│   ├── 21_load_dim_geo_hive.sql
│   ├── 22_load_dim_date_hive.sql
│   ├── 23_quality_log_hive.sql
│   ├── 24_load_quality_log_hive.sql
│   ├── 25_check_quality_log_hive.sql
│   ├── 26_ads_bi_export_dataset.sql
│   ├── 27_load_result_quality_log_hive.sql
│   ├── 28_load_star_quality_log_hive.sql
│   ├── run_all_hive.sh
│   ├── run_backfill_hive.sh
│   ├── run_t1_window_hive.sh
│   ├── run_idempotency_check_hive.sh
│   ├── run_quality_gate_hive.sh
│   ├── run_result_quality_gate_hive.sh
│   ├── run_star_schema_hive.sh
│   ├── run_star_quality_gate_hive.sh
│   ├── hive_migration_design.md
│   └── interview_hive_talking_points.md
├── dolphinscheduler/
│   ├── dq_check_result.sql
│   ├── etl_task_log_v2.sql
│   ├── hive_task_nodes.md
│   ├── workflow_design.md
│   ├── deployment_mysql_ssh.md
│   └── retail_hive_offline_warehouse_daily_demo.json
├── scripts/
│   ├── 10_run_etl.bat
│   ├── 26_scheduler_demo.bat
│   └── run_etl_linux.sh
└── docs/
    ├── setup_local_hive.md         # 本地 Hive 运行指南
    ├── 25_scheduler_design.txt
    ├── 27_metric_definitions.txt
    ├── result_screenshots/
    │   ├── 01_ds_workflow_instance_success.png
    │   ├── 02_ds_dag_quality_gate_success.png
    │   ├── 03_dwd_quality_gate_passed.png
    │   ├── 04_ads_sales_contribution_20260408.png
    │   ├── 05_ads_customer_level_distribution_20260408.png
    │   ├── 06_ads_country_sales_rank_20260408.png
    │   ├── 07_ads_customer_preference_20260408.png
    │   ├── 08_light_bi_dashboard_top_20260408.png
    │   ├── 09_light_bi_dashboard_bottom_20260408.png
    │   └── README.md
    └── multiday_validation_screenshots/
        ├── 01_7day_ods_partition_check.png
        ├── 02_7day_dwd_partition_check.png
        ├── 03_7day_ads_country_rank_check.png
        ├── 04_idempotency_check_20260403.png
        ├── 05_t1_window_check_20260406_20260407.png
        ├── 06_dwd_cleaning_quality_20260401.png
        ├── 07_quality_log_20260408.png（可选，用于展示 quality_log_hive 查询结果）
        └── README.md
```

说明：原始数据文件较大，仓库中不建议上传完整数据集。运行项目前，需要提前准备同字段结构的订单数据表。`scripts/` 目录中的脚本属于 MySQL 阶段的本地执行与调度模拟脚本，不是 Hive 主链路的生产调度入口。

当前压缩包保留了轻量级 BI Dashboard 的运行截图，但未包含 Dashboard 生成脚本目录，因此 README 仅将其作为已有展示结果，不把它描述为当前代码包可直接重建的模块。

---

## 5. 数据说明

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

### 5.1 样例数据

仓库提供最小样例数据：

```text
sample_data/retail_sample.csv
```

该样例数据用于验证 Hive 主链路能否按业务日期完成 ODS、DWD、DWS、ADS 分层产出，不代表完整原始数据集。完整原始数据量较大，公开仓库中不上传全量数据。

本地运行说明见：

```text
docs/setup_local_hive.md
```

最小验证命令：

```bash
cd hive_sql
bash run_all_hive.sh 2026-04-08
```

---

## 6. Hive 主链路设计

Hive 处理链路统一使用 `dt` 作为业务日期分区字段。当前完整执行流程为：

```text
retail 源表
  ↓
ods_retail_hive
  ↓
dwd_retail_clean_hive
  ↓
DWD 质量门禁（quality_log_hive，6 条 BLOCK 规则）
  ↓
├── dws_customer_value_hive
└── dws_sales_summary_hive
  ↓
四张 ADS 指标表
  ↓
DWS / ADS 结果门禁（result_quality_log_hive，BLOCK / WARN）
  ↓
星型模型：dim_user / dim_product / dim_date / dim_geo / fact_order / star DWS
  ↓
星型模型质量门禁（star_quality_log_hive，12 条规则）
```

核心分区设计：

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

该方式支持指定业务日期重跑，避免重复执行导致重复数据。项目的幂等性验收不再只比较行数，还会对 8 张核心 ODS / DWD / DWS / ADS 表计算两组 CRC32 内容指纹，降低“行数相同但内容变化”被漏检的风险。

## 7. Hive 主链路执行脚本

```text
run_all_hive.sh：执行单个 bizdate 的 15 步完整链路
run_backfill_hive.sh：按日期区间循环回刷
run_t1_window_hive.sh：回刷 bizdate 前一天和当天，支持 T+1 延迟数据修正窗口
run_idempotency_check_hive.sh：重跑指定 bizdate，对比 8 张核心表的行数和两组 CRC32 内容指纹
run_quality_gate_hive.sh：执行 DWD 质量门禁，BLOCK 规则失败时返回非零状态
run_result_quality_gate_hive.sh：执行 DWS / ADS 结果门禁，WARN 只记录，BLOCK 失败时阻断
run_star_schema_hive.sh：构建维表、事实表和星型 DWS，并自动执行星型质量门禁
run_star_quality_gate_hive.sh：执行 12 条星型模型质量规则
```

`run_all_hive.sh` 的 15 个步骤：

```text
01  创建 ODS 表
02  加载 ODS 分区
03  检查 ODS 分区
04  创建 DWD 表
05  加载 DWD 分区
06  执行 DWD 质量门禁
07  构建客户价值 DWS
08  构建国家销售 DWS
09-12  构建四张 ADS 指标表
13  执行 DWS / ADS 结果质量门禁
14  构建星型模型并执行星型质量门禁
15  展示最终结果
```

执行示例：

```bash
bash hive_sql/run_all_hive.sh 2026-04-08
bash hive_sql/run_backfill_hive.sh 2026-04-01 2026-04-08
bash hive_sql/run_t1_window_hive.sh 2026-04-08
bash hive_sql/run_idempotency_check_hive.sh 2026-04-03
bash hive_sql/run_quality_gate_hive.sh 2026-04-08
bash hive_sql/run_result_quality_gate_hive.sh 2026-04-08
bash hive_sql/run_star_schema_hive.sh 2026-04-08
```


### 7.1 MySQL 阶段辅助脚本说明

`scripts/` 目录保留的是 MySQL 阶段的本地执行与调度模拟脚本，用于说明项目早期从单机 SQL 执行到日志记录、质量校验和调度模拟的演进过程。它们不参与当前 Hive 主链路的日常执行，也不替代 DolphinScheduler 中的 Hive DAG。

```text
10_run_etl.bat：Windows 本地快速执行 MySQL 版 08_run_all.sql，适合早期本地验证。
26_scheduler_demo.bat：Windows 本地调度模拟脚本，串联 MySQL ETL、日志检查和数据质量检查，主要用于演示调度思路。
run_etl_linux.sh：Linux 环境下执行 MySQL ETL，并写入 START / SUCCESS / FAILED 状态日志，是 MySQL 阶段较完整的工程化执行脚本。
```

面试或项目说明时，建议将 `scripts/` 定位为“MySQL 阶段辅助脚本”，将 `hive_sql/run_all_hive.sh`、`run_backfill_hive.sh`、`run_t1_window_hive.sh` 和 DolphinScheduler DAG 作为当前 Hive 主链路的重点。

## 8. 三级数据质量门禁

项目将数据质量检查分为三个阶段，并通过 Shell 退出码与调度链路联动：

```text
DWD 前置门禁：quality_log_hive，6 条 BLOCK 规则
DWS / ADS 结果门禁：result_quality_log_hive，11 条规则（含 BLOCK / WARN）
星型模型门禁：star_quality_log_hive，12 条 BLOCK 规则
```

相关文件：

```text
23_quality_log_hive.sql                 创建 DWD 质量日志表
24_load_quality_log_hive.sql            写入 6 条 DWD 质量规则
25_check_quality_log_hive.sql           查询 DWD 质量结果
27_load_result_quality_log_hive.sql     创建并写入 11 条 DWS / ADS 结果规则
28_load_star_quality_log_hive.sql       创建并写入 12 条星型模型规则
run_quality_gate_hive.sh                DWD 门禁执行入口
run_result_quality_gate_hive.sh         DWS / ADS 结果门禁执行入口
run_star_quality_gate_hive.sh           星型模型门禁执行入口
```

质量日志字段在原有 `table_name`、`check_item`、`abnormal_cnt`、`check_status`、`check_time`、`dt` 基础上，增加：

```text
rule_code       质量规则唯一编码
check_level     规则级别：BLOCK / WARN
actual_value    实际指标值
threshold_value 判断阈值
check_detail    详细检查说明
```

DWD 门禁覆盖无效数量、无效价格、空客户、空分区、ODS 与 DWD 行数对账以及 DWD 时间格式检查。结果门禁覆盖 DWS / ADS 非空、DWD 与 DWS 金额对账、占比求和和比例范围等规则。星型门禁覆盖 SCD2 当前版本唯一性、维表业务键唯一性、事实表非空、DWD 与事实表行数金额对账、事实主键唯一性和星型 DWS 对账。

规则处理方式：

- `BLOCK + FAIL`：Shell 返回非零状态，阻断下游任务；
- `WARN + FAIL`：保留告警记录，但不阻断任务；
- Hive SQL 无法执行或无法读取结果：按门禁失败处理。

执行示例：

```bash
bash hive_sql/run_quality_gate_hive.sh 2026-04-08
bash hive_sql/run_result_quality_gate_hive.sh 2026-04-08
bash hive_sql/run_star_quality_gate_hive.sh 2026-04-08
```

项目已验证门禁的成功与失败路径：正常业务日期的星型模型 12 条规则全部 `PASS`；空分区测试日期会触发 `STAR_001`、`STAR_008` 失败，并返回退出码 `1`。

## 9. 星型模型扩展链路

`11-22` 是基于 DWD 清洗明细补充的星型模型扩展链路，不替代 `00-09` 的原业务指标口径。

```text
dwd_retail_clean_hive
  ↓
├── dim_user（每日完整快照式 SCD2）
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

执行脚本：

```bash
bash hive_sql/run_star_schema_hive.sh 2026-04-08
```

说明：

- `dim_user` 保存 `start_date`、`end_date`、`is_current`，支持新客户新增版本、属性未变化时延续版本、属性变化时关闭旧版本并新增当前版本；每个 `dt` 分区保存截至当天的完整 SCD2 历史快照。
- 首日快照使用 `md5(customerid|country|start_date)` 生成用户代理键；后续属性变化会生成新的版本键。
- `dim_product` 使用 `md5(stockcode)` 生成稳定商品代理键，`dim_date` 和 `dim_geo` 分别补充日期与地理维度。
- `fact_order` 保留订单明细粒度，按订单日期关联 `dim_user` 的有效时间范围，而不是只关联当前版本；`order_line_id` 用于标识订单明细。
- `dws_customer_value_star_hive` 基于事实表生成客户价值汇总，避免与原主链路 `dws_customer_value_hive` 表名冲突。
- `run_star_schema_hive.sh` 共 13 步，第 13 步自动执行 `run_star_quality_gate_hive.sh`。

`dt=2026-04-08` 的验收结果：

```text
dim_user：5,878 个版本，5,878 个当前版本，5,878 个客户
dim_product：4,630 行，4,630 个唯一商品
dim_date：1 行，1 个唯一日期
dim_geo：41 行，41 个唯一国家
fact_order：2,416,593 行，order_line_id 唯一
DWD / fact_order：行数均为 2,416,593，金额均为 53,230,287.48
star_quality_log_hive：STAR_001 - STAR_012 全部 PASS
```

## 10. DolphinScheduler 调度设计

工作流逻辑名称：

```text
retail_hive_offline_warehouse_daily
```

已完成的工程配置：

- DolphinScheduler 3.2.2 Docker Standalone；
- 元数据库由 H2 内存库迁移到 MySQL，实现项目、工作流与实例持久化；
- 自定义镜像加入 MySQL Connector/J 与 OpenSSH Client；
- Shell 节点通过 SSH 调用 Hadoop/Hive 主机；
- 12 个节点完整 DAG 已验收成功。

全局参数：

```text
bizdate=$[yyyy-MM-dd-1]
HIVE_USER=<SSH 用户>
HIVE_HOST=<Hive 主机>
PROJECT_HOME=<服务器项目根目录>
```

仓库中的 `hive_sql/` 在服务器部署为 `${PROJECT_HOME}/hive/`，因此普通节点模板为：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/SQL文件名
"
```

质量门禁节点执行：

```bash
bash ${PROJECT_HOME}/hive/run_quality_gate_hive.sh ${bizdate}
```

当前 DAG：

```text
ods_create_retail
  → ods_load_retail
  → dwd_create_table
  → dwd_load_clean_data
  → dwd_quality_gate
      ├→ dws_customer_value
      │    ├→ ads_high_value_customer_sales_contribution
      │    ├→ ads_customer_level_distribution
      │    └→ ads_high_value_customer_preference
      └→ dws_sales_summary
           └→ ads_country_sales_rank

四个 ADS 节点
  → hive_data_quality_check
```

说明：当前导入 JSON 仍是已验收的 12 节点版本，包含原 ODS / DWD / DWS / ADS 主链路和 DWD 门禁；新增加的结果门禁、星型模型和星型门禁已经接入 `run_all_hive.sh`，但尚未同步扩展到该 JSON DAG。面试时应明确区分“已验收的 DolphinScheduler DAG”和“当前完整 Shell 主链路”。

DolphinScheduler 3.2.2 工作流 JSON 导入时，`processTaskRelationList` 必须存在且非空，并使用合法数值任务编码。详细说明见：

- `dolphinscheduler/workflow_design.md`
- `dolphinscheduler/hive_task_nodes.md`
- `dolphinscheduler/deployment_mysql_ssh.md`

---

## 11. 数据质量校验

数据质量校验不只确认 SQL 是否执行成功，还检查分区、业务规则以及上下游对账结果：

- ODS、DWD、DWS、ADS、维表、事实表指定业务日期分区是否有数据；
- ODS 日期是否可解析，DWD 是否仍存在异常数量、异常价格、空客户和非标准时间；
- ODS 按清洗条件推导的预期 DWD 行数是否与实际 DWD 一致；
- 两张 DWS 的销售额是否与 DWD 总销售额一致；
- ADS 人数占比、销售额占比是否约等于 100%，贡献比例是否在合法范围；
- SCD2 是否满足每个客户只有一个当前版本、日期范围有效、当前版本结束日期为 `9999-12-31`；
- 商品、日期和地理维表业务键是否唯一；
- DWD 与事实表的行数、金额是否一致，`order_line_id` 是否唯一；
- 事实表与星型 DWS 的客户数和金额是否一致；
- `BLOCK` 失败时是否返回非零退出码，`WARN` 是否只记录而不阻断。

## 12. 多天分区运行验证

为证明项目不是只能跑单天样例，本项目额外构造了 `2026-04-01` 到 `2026-04-07` 共 7 天连续业务日期数据，并完成完整链路验证。

验证过程：

```bash
sh hive_sql/run_backfill_hive.sh 2026-04-01 2026-04-07
sh hive_sql/run_idempotency_check_hive.sh 2026-04-03
sh hive_sql/run_t1_window_hive.sh 2026-04-07
```

验证结果：

```text
ODS：2026-04-01 到 2026-04-07，每天 3,202,113 行
DWD：2026-04-01 到 2026-04-07，每天 3,124,956 行
ADS 国家销售排行：2026-04-01 到 2026-04-07，每天 43 行
幂等性验证：通过 run_idempotency_check_hive.sh 重复执行 2026-04-03 后，8 张核心 ODS / DWD / DWS / ADS 表的行数和两组 CRC32 内容指纹保持一致
T+1 验证：执行 2026-04-07 修正窗口后，2026-04-06 和 2026-04-07 分区结果保持稳定
```

这组验证说明：

- `bizdate` 参数可以稳定驱动多天分区写入；
- `INSERT OVERWRITE PARTITION` 支持同一天重复执行且不产生重复数据；
- `run_idempotency_check_hive.sh` 可以作为验收脚本，用于对比重跑前后关键表行数和内容指纹是否一致；
- `run_backfill_hive.sh` 可以完成连续分区回刷；
- `run_t1_window_hive.sh` 可以完成前一天和当天的延迟数据修正；
- ODS、DWD、ADS 在跨天场景下结果稳定。



### 12.1 Hive 性能优化与回归验证

在不改变核心业务表名、分区字段和 `bizdate` 参数的前提下，本项目补充了一轮 Hive 性能优化与回归验证。

本轮优化主要包括：

- **数据倾斜定位**：通过 `country`、`customerid`、`stockcode` 分布检查，发现 `country='United Kingdom'` 在 `dt=2026-04-08` 的 DWD 分区中约 2,175,699 行，占比分区总量约 69.6%，属于典型国家维度数据倾斜。
- **DWS 倾斜处理**：针对 `04_dws_sales_summary_hive.sql` 中的 `GROUP BY country`，将国家销售汇总改造为手写 Salt + 两阶段聚合。销售额先按 `country + salt_key` 局部聚合，再回收为国家粒度；订单数和客户数涉及去重统计，采用先 `country + invoice/customerid` 去重、再按国家汇总的方式，避免 Salt 后重复计数。
- **Join 优化**：针对 `05_ads_high_value_customer_sales_contribution_hive.sql` 和 `08_ads_high_value_customer_preference_hive.sql` 中 DWD 明细大表 Join DWS 客户价值小表的场景，使用 `MAPJOIN` 广播小表，减少 Shuffle 开销。
- **分区裁剪修正**：在 ADS Join 逻辑中补充 `dws.dt='${hiveconf:bizdate}'` 条件，避免跨分区 Join 导致结果重复放大。
- **DWD 清洗修正**：修正 `02_load_dwd_retail_clean_hive.sql` 中清洗条件拼接问题，并补充 `stockcode`、`country`、`invoicedate` 的非空和非空字符串过滤。
- **EXPLAIN 验证**：通过 `EXPLAIN` 确认 ADS Join 查询中出现 `Map Join Operator`，说明 MAPJOIN 生效。
- **链路回归**：完成 ODS、DWD、DWS、ADS 主链路回归；在本次升级中又逐表验证 SCD2 用户维度、其他维表、事实表、星型 DWS 和 12 条星型质量规则。

这轮优化的重点不是单纯修改 SQL，而是形成了“发现倾斜 → 定位热点 key → 改写 SQL → EXPLAIN 验证 → 全链路回归”的完整优化闭环。

---

## 13. 项目亮点

1. 完成 MySQL 到 Hive 的核心指标迁移，形成 ODS、DWD、DWS、ADS 分层主链路。
2. 设计 `dt` 分区、ORC 存储、`bizdate` 参数和 `INSERT OVERWRITE PARTITION`，支持按业务日期重跑。
3. 基于 7 天连续业务日期完成跨天分区、区间回刷和 T+1 修正窗口验证。
4. 编写单日执行、区间回刷、T+1 修正和幂等性验收脚本；幂等性由“只比行数”升级为“行数 + 两组 CRC32 内容指纹”。
5. 建立三级数据质量门禁：DWD 6 条规则、DWS / ADS 11 条规则、星型模型 12 条规则，并使用 `BLOCK / WARN` 区分阻断与告警。
6. 实现每日完整快照式 SCD2 用户维度，事实表按业务日期关联有效版本，能够正确处理属性历史变化。
7. 完成商品、日期、地理维度、订单明细事实表和星型客户价值 DWS，并通过行数、金额、主键和维度唯一性对账。
8. 将星型模型及其质量门禁接入 15 步 `run_all_hive.sh`，任一阶段失败都会返回非零退出码并停止下游。
9. 接入 DolphinScheduler 3.2.2，将元数据库由 H2 迁移到 MySQL 持久化，并完成原主链路 12 节点 DAG 验收。
10. 围绕高价值客户形成客户分层、商品偏好、国家销售排行和销售贡献分析链路。
11. 针对 `country` 维度数据倾斜，使用手写 Salt + 两阶段聚合优化国家销售汇总。
12. 针对 DWD 大表 Join DWS 小表场景使用 MAPJOIN，并通过 EXPLAIN 验证 `Map Join Operator` 生效。

### 13.1 轻量级 BI Dashboard 说明

项目运行结果中保留了基于 Hive ADS 数据生成的 HTML + ECharts Dashboard 截图，可展示高价值客户贡献、客户价值分层、国家销售排行和商品偏好。当前压缩包未包含 Dashboard 生成脚本，因此该部分作为已有展示结果，不作为本代码包可直接重建的核心链路。

## 14. 运行结果截图

项目运行截图按用途拆分为两个目录，避免把单日 ADS 展示截图和多天分区验证截图混在一起。

### 14.1 调度与 ADS 结果截图

目录：`docs/result_screenshots/`

该目录用于展示 DolphinScheduler 调度状态、`dt=2026-04-08` 的核心 ADS 结果和轻量级 BI Dashboard 展示截图，主要包括：

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

轻量级 BI Dashboard 截图说明：

- `08_light_bi_dashboard_top_20260408.png`：上半部分展示高价值客户贡献、客户价值分层人数和销售贡献占比。
- `09_light_bi_dashboard_bottom_20260408.png`：下半部分展示国家销售排行 Top10 和高价值客户偏好商品 Top10。

### 14.1.1 核心验收截图预览

工作流实例成功：

![DolphinScheduler 工作流实例成功](docs/result_screenshots/01_ds_workflow_instance_success.png)

完整 DAG（含 DWD 质量门禁）：

![DolphinScheduler DAG 全部成功](docs/result_screenshots/02_ds_dag_quality_gate_success.png)

质量门禁通过：

![DWD 质量门禁通过](docs/result_screenshots/03_dwd_quality_gate_passed.png)

这些截图用于说明：

- DolphinScheduler 工作流实例可以成功执行；
- 主链路 DAG 中 ODS、DWD、DWS、ADS 和最终校验节点依赖关系清晰；
- `dt=2026-04-08` 的高价值客户销售贡献、客户分层分布、国家销售排行和高价值客户商品偏好等 ADS 指标表可以正常查询；
- 基于 ADS 导出数据生成的轻量级 BI Dashboard 可以集中展示核心指标，适合作为项目演示和作品集展示页。

### 14.2 多天分区与工程能力验证截图

目录：`docs/multiday_validation_screenshots/`

该目录用于展示 Hive 主链路的多天分区、区间回刷、幂等性和 T+1 修正窗口验证，主要包括：

```text
01_7day_ods_partition_check.png
02_7day_dwd_partition_check.png
03_7day_ads_country_rank_check.png
04_idempotency_check_20260403.png
05_t1_window_check_20260406_20260407.png
06_dwd_cleaning_quality_20260401.png
07_quality_log_20260408.png（可选，用于展示 quality_log_hive 查询结果）
```

这些截图用于说明：

- `2026-04-01` 到 `2026-04-07` 的 ODS 分区行数稳定；
- `2026-04-01` 到 `2026-04-07` 的 DWD 清洗后分区行数稳定；
- ADS 国家销售排行在连续 7 个业务日期中均能产出结果；
- 重复执行同一业务日期后，关键表行数保持一致，验证 `INSERT OVERWRITE PARTITION` 的幂等性；
- T+1 修正窗口可以回刷前一天和当天分区；
- DWD 清洗校验可以展示异常数量、异常价格、空客户和退货订单等过滤情况；
- 如果补充 `07_quality_log_20260408.png`，可以展示质量日志表按业务日期落表后的 PASS / FAIL 结果。

说明：截图仅作为项目运行验收示例，不作为真实业务运营结论。多天数据用于验证分区回刷能力，不表述为真实业务连续 7 天数据。

---

## 15. 项目边界说明

本项目是面向学习与作品集展示的电商离线数仓项目，主要用于展示 SQL 开发、数仓分层建模、指标沉淀、Hive 迁移、调度编排和数据质量校验能力。项目结果基于当前数据集统计，不等同于真实业务运营指标，也不直接推导实际业务收益。

---

## 16. 运行前准备

运行 Hive 或 DolphinScheduler 调度前，需要完成以下准备：

```text
1. Hive 中已经存在源表 retail，且字段与 README 中的数据说明一致；
2. InvoiceDate 支持 `yyyy-MM-dd HH:mm:ss` 和 `d/M/yyyy HH:mm:ss` 两种格式；DWD 会统一输出为 `yyyy-MM-dd HH:mm:ss`；
3. 仓库 `hive_sql/` 已部署或挂载到服务器 `${PROJECT_HOME}/hive/`；
4. DolphinScheduler 执行环境已配置 HIVE_USER、HIVE_HOST、PROJECT_HOME；
5. SSH 已配置免密或密钥登录；
6. HDFS NameNode、DataNode 以及 Hive 运行环境已启动，`hdfs dfs -ls /` 和 `hive -e "show databases;"` 可正常返回。
```

---

## 17. GitHub 上传说明

公开仓库中不要上传以下内容：

- 真实服务器账号；
- 真实内网 IP 或公网 IP；
- 明文密码；
- 数据库连接凭据；
- 未打码的运行日志截图；
- 大体积原始数据文件。

公开仓库中的调度命令应统一使用占位符形式。实际运行时需要在部署环境中配置 `HIVE_USER`、`HIVE_HOST`、`PROJECT_HOME`，并配置 SSH 免密或密钥登录。