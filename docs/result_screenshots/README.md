# 结果截图说明：DolphinScheduler、质量门禁与 ADS 结果

本目录保存已完成验收的调度截图、DWD 质量门禁执行证据、Hive ADS 查询结果和轻量 BI Dashboard。调度截图对应完整的 12 节点 DAG；ADS 查询截图使用示例业务日期 `dt=2026-04-08`。

## 截图列表

| 文件名 | 说明 |
|---|---|
| `01_ds_workflow_instance_success.png` | DolphinScheduler 工作流实例成功，显示开始/结束时间与运行时长；已裁去主机地址和操作列。 |
| `02_ds_dag_quality_gate_success.png` | 完整 DAG 全部节点成功，包含 `dwd_quality_gate` 以及 DWS/ADS 分支汇聚。 |
| `03_dwd_quality_gate_passed.png` | 质量日志写入完成，脚本输出 `Data quality gate passed` 和 `failed_count=0`。 |
| `04_ads_sales_contribution_20260408.png` | 高价值客户销售贡献指标查询结果。 |
| `05_ads_customer_level_distribution_20260408.png` | 客户价值分层分布指标查询结果。 |
| `06_ads_country_sales_rank_20260408.png` | 国家销售排行指标查询结果。 |
| `07_ads_customer_preference_20260408.png` | 高价值客户商品偏好指标查询结果。 |
| `08_light_bi_dashboard_top_20260408.png` | BI Dashboard 上半部分：高价值客户、订单、销售额及客户分层。 |
| `09_light_bi_dashboard_bottom_20260408.png` | BI Dashboard 下半部分：国家销售额 Top10 与偏好商品 Top10。 |

## 截图验收口径

```text
ODS 建表/加载成功
→ DWD 建表/加载成功
→ dwd_quality_gate 通过（FAIL 数量为 0）
→ DWS 两条分支成功
→ ADS 四个指标节点成功
→ 最终结果校验成功
```

多天分区、区间回刷、幂等性和 T+1 修正窗口截图位于：

```text
docs/multiday_validation_screenshots/
```

公开截图不得包含真实服务器 IP、密码、SSH 私钥或数据库凭据。截图只用于工程链路验收，不代表真实业务运营结论。