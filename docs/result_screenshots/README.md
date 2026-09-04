# 结果截图说明：DolphinScheduler、质量门禁与 ADS 结果

> 文件属性：长期保留，提交代码仓库
> 对应目录：`docs/result_screenshots/`

本目录保存 DolphinScheduler 调度验收、DWD 质量门禁、Hive ADS 查询结果和轻量 BI Dashboard 截图。

需要区分两套范围：

```text
截图中的调度链路：
已验收的 DolphinScheduler 12 节点演示 DAG

当前仓库最完整链路：
hive_sql/run_all_hive.sh 的 20 步 Shell 主流程
```

DolphinScheduler 截图不代表 ODS Raw、ODS Reject、ODS 入仓完整性门禁、DWS/ADS 结果门禁和星型模型已经全部拆分为调度节点。

---

## 截图列表

截图按「调度验证 → 数据质量 → 数仓结果 → BI 分析 → 异常诊断」的工程链路逻辑排序。本目录仅存放业务结果截图；数据概览与异常诊断辅助演示截图位于 `docs/evidence/`。

### 调度验证

| 文件名 | 内容说明 |
|---|---|
| `01_ds_workflow_instance_success.png` | DolphinScheduler 工作流实例执行成功，展示开始时间、结束时间和运行时长；敏感主机信息已裁剪。 |
| `02_ds_dag_quality_gate_success.png` | 12 节点 DAG 全部成功，包含 `dwd_quality_gate`、两条 DWS 分支、四条 ADS 分支及最终汇聚节点。 |

### 数据质量

| 文件名 | 内容说明 |
|---|---|
| `03_dwd_quality_gate_passed.png` | DWD 质量门禁执行结果，显示 `Data quality gate passed` 和 `failed_count=0`。 |

### 数仓结果

| 文件名 | 内容说明 |
|---|---|
| `04_ads_sales_contribution_20260408.png` | engineering_legacy_3x 历史工程验证：`dt=2026-04-08` 的高价值客户销售贡献查询结果。 |
| `05_ads_customer_level_distribution_20260408.png` | engineering_legacy_3x 历史工程验证：`dt=2026-04-08` 的客户价值层级分布查询结果。 |
| `06_ads_country_sales_rank_20260408.png` | engineering_legacy_3x 历史工程验证：`dt=2026-04-08` 的国家销售排行查询结果。 |
| `07_ads_customer_preference_20260408.png` | engineering_legacy_3x 历史工程验证：`dt=2026-04-08` 的高价值客户商品偏好查询结果。 |

### BI 分析

| 文件名 | 内容说明 |
|---|---|
| `08_light_bi_dashboard_top_20260408.png` | engineering_legacy_3x 历史工程验证：轻量 BI Dashboard 上半部分，高价值客户指标和客户层级分布。 |
| `09_light_bi_dashboard_bottom_20260408.png` | engineering_legacy_3x 历史工程验证：轻量 BI Dashboard 下半部分，国家销售额 Top10 和偏好商品 Top10。 |
| `10_retail_bi_connector_success.png` | 前端零售 BI 连接器接入成功：外部数据源折叠面板展开，API 地址和日期范围配置完成。 |
| `11_retail_bi_overview_comparison.png` | 前端单日经营概览与日环比分析：五个核心 KPI 卡片及日环比变化百分比（基于 `engineering_legacy_3x` 历史工程回归数据）。 |
| `12_retail_bi_sales_trend.png` | 前端多日趋势分析：时间趋势折线图展示销售额、订单数等指标在日期范围内的变化（基于 `synthetic_multiday` 多日期工程验证数据）。 |
| `13_retail_bi_canonical_business_day_comparison.png` | 前端 canonical 真实数据日环比验证：截图直接证明 2009-12-13 与上一可用业务日 2009-12-11 的前端比较，跳过无数据的 2009-12-12。对应 API 验证结果中 comparisonAvailable=true、sourceSystem=retail_canonical_ads。 |
| `14_daily_operation_comparison.png` | 展示业务日期经营指标对比分析能力：同一业务日多项核心经营指标的横向对比。 |
| `15_canonical_sales_trend.png` | 展示基于 canonical 真实数据的销售趋势分析能力：核心销售指标在多业务日区间内的趋势变化。 |

### 异常诊断

| 文件名 | 内容说明 |
|---|---|
| `anomaly_case_high_2010-09-28.png` | Hive 经营异常检测结果：2010-09-28 为 HIGH 等级异常，sales_change_pct=-65.11%，primary_driver=AVG_ORDER_VALUE。 |
| `anomaly_api_high_2010-09-28.png` | Spring Boot 异常 API 真实验证：查询 2010-09-28 返回 HIGH 等级异常，sourceSystem=retail_canonical_anomaly_ads。 |
| `docs/evidence/anomaly_analysis_canonical.png` | 基于 canonical 真实业务数据的经营异常分析结果。 |
| `docs/evidence/ai_anomaly_diagnosis_demo.png` | 经营异常智能诊断辅助能力演示：对单条经营异常展示关键影响因素、影响评估与优化建议。为业务洞察辅助能力，非 AI 预测模型。 |
| `docs/evidence/dataset_profile_overview.png` | 数据规模、来源与数据概览，用于提高项目可信度。 |

> 说明：`anomaly_case_high_2010-09-28.png` 与 `anomaly_api_high_2010-09-28.png` 等同于"异常诊断"环节的规则检测与接口验证截图，与 `docs/evidence/` 下的智能诊断辅助截图互为补充。

---

## 调度截图的验收范围

截图对应的 12 节点链路为：

```text
正常 ODS 建表与加载
→ DWD 建表与加载
→ DWD 质量门禁
→ 两张 DWS
→ 四张 ADS
→ 最终结果检查
```

其中：

- `dwd_quality_gate` 会在 BLOCK 规则失败时返回非零状态并阻断下游；
- 最终节点执行 `09_check_hive_result.sql`，主要用于查询展示和人工验收；
- 最终节点不等同于当前 `run_result_quality_gate_hive.sh` 的完整 DWS/ADS 阻断门禁。

---

## 版本与兼容性说明

这些调度截图来自已经成功验收的 12 节点部署版本。

当前仓库中的 `00_load_ods_retail_hive.sql` 已改为从 `ods_retail_raw_hive` 读取，但截图中的旧 DAG 没有 ODS Raw、Reject 和入仓门禁节点。因此：

> 截图能够证明当时的调度版本运行成功，但不能证明旧 12 节点 DAG 可以直接搭配当前全部最新 SQL 运行。

当前最新、最完整的执行与验收口径以以下文件为准：

```text
README.md
hive_sql/run_all_hive.sh
hive_sql/hive_migration_design.md
```

---

## ADS 与 BI 截图说明

ADS 截图用于展示指定业务日期分区的查询结果，不代表生产经营结论。

轻量 BI Dashboard 目前只保留运行截图，仓库中没有对应的生成脚本。因此它可以作为结果展示材料，但不能仅凭当前代码包重新生成。

指标定义以：

```text
docs/27_metric_definitions.txt
```

为准。

---

## 其他工程验证截图

多天分区、区间回刷、幂等性和 T+1 修正窗口截图位于：

```text
docs/multiday_validation_screenshots/
```

该目录属于较早的数据和清洗规则基线，与 engineering_legacy_3x 的 `2026-04-08` 历史完整回归结果需要分开解释。

---

## 安全要求

公开截图不得包含：

- 真实服务器 IP 或主机名；
- 数据库密码；
- SSH 私钥；
- 个人账号信息；
- 未脱敏的连接配置。

本目录截图仅用于工程链路和结果验收。