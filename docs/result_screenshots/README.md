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

| 文件名 | 内容说明 |
|---|---|
| `01_ds_workflow_instance_success.png` | DolphinScheduler 工作流实例执行成功，展示开始时间、结束时间和运行时长；敏感主机信息已裁剪。 |
| `02_ds_dag_quality_gate_success.png` | 12 节点 DAG 全部成功，包含 `dwd_quality_gate`、两条 DWS 分支、四条 ADS 分支及最终汇聚节点。 |
| `03_dwd_quality_gate_passed.png` | DWD 质量门禁执行结果，显示 `Data quality gate passed` 和 `failed_count=0`。 |
| `04_ads_sales_contribution_20260408.png` | `dt=2026-04-08` 的高价值客户销售贡献查询结果。 |
| `05_ads_customer_level_distribution_20260408.png` | `dt=2026-04-08` 的客户价值层级分布查询结果。 |
| `06_ads_country_sales_rank_20260408.png` | `dt=2026-04-08` 的国家销售排行查询结果。 |
| `07_ads_customer_preference_20260408.png` | `dt=2026-04-08` 的高价值客户商品偏好查询结果。 |
| `08_light_bi_dashboard_top_20260408.png` | 轻量 BI Dashboard 上半部分：高价值客户指标和客户层级分布。 |
| `09_light_bi_dashboard_bottom_20260408.png` | 轻量 BI Dashboard 下半部分：国家销售额 Top10 和偏好商品 Top10。 |

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

ADS 截图用于展示指定业务日期分区的查询结果，不代表真实生产经营结论。

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

该目录属于较早的数据和清洗规则基线，与当前 `2026-04-08` 完整回归结果需要分开解释。

---

## 安全要求

公开截图不得包含：

- 真实服务器 IP 或主机名；
- 数据库密码；
- SSH 私钥；
- 个人账号信息；
- 未脱敏的连接配置。

本目录截图仅用于工程链路和结果验收。