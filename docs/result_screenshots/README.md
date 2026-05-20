# 结果截图说明：调度与 ADS 结果

本目录用于保存 DolphinScheduler 调度运行状态和 Hive ADS 层核心结果截图，主要展示主链路 DAG 可以跑通，以及 `dt=2026-04-08` 的核心 ADS 指标可以正常查询。

## 截图列表

| 文件名 | 说明 |
|---|---|
| `01_ds_workflow_instance_success.png` | DolphinScheduler 工作流实例运行成功。 |
| `02_ds_dag_all_tasks_success.png` | DAG 任务节点执行成功，展示 ODS、DWD、DWS、ADS 与结果校验节点的依赖关系。 |
| `03_ads_sales_contribution_20260408.png` | 高价值客户销售贡献结果示例，业务日期为 `2026-04-08`。 |
| `04_ads_customer_level_distribution_20260408.png` | 客户价值分层分布结果示例，业务日期为 `2026-04-08`。 |
| `05_ads_country_sales_rank_20260408.png` | 国家销售排行结果示例，业务日期为 `2026-04-08`。 |
| `06_ads_customer_preference_20260408.png` | 高价值客户商品偏好结果示例，业务日期为 `2026-04-08`。 |
|` 07_light_bi_dashboard_top_20260408.png：轻量级 BI Dashboard 上半部分，展示高价值客户数、订单数、销售额、销售贡献占比，以及客户价值分层人数和销售贡献占比。 |
|` 08_light_bi_dashboard_bottom_20260408.png：轻量级 BI Dashboard 下半部分，展示国家销售额 Top10 和高价值客户偏好商品 Top10。 |

## 使用说明

本目录只放置调度运行和单日 ADS 结果截图。多天分区、区间回刷、幂等性和 T+1 修正窗口验证截图，请放入：

```text
docs/result_screenshots_validation/
```

截图仅作为项目运行验收材料，不作为真实业务运营结论。公开仓库截图中不展示真实服务器账号、真实 IP、明文密码或本机调试路径。
