# DolphinScheduler 调度设计说明

## 1. 接入目的

原项目已经具备 MySQL / Hive SQL 脚本、统一执行脚本和数据质量校验脚本。接入 DolphinScheduler 后，将 Hive 离线数仓链路拆分为可视化 DAG 任务节点，实现任务依赖编排、按业务日期调度、运行过程留痕和数据质量校验、并为后续历史分区补数提供扩展基础。

## 2. 当前实现方式

本项目采用 DolphinScheduler Shell 节点调度 Hive SQL。由于 DolphinScheduler 运行在容器中，容器内部不直接依赖 Hive 客户端环境。每个 Shell 节点通过 SSH 调用部署 Hive 的 Linux 主机执行 Hive SQL。

公开仓库中不保留真实服务器账号、真实 IP 或明文密码，统一使用占位符：`${HIVE_USER}`、`${HIVE_HOST}`、`${PROJECT_HOME}`。

## 3. 工作流名称

```text
retail_hive_offline_warehouse_daily
```

## 4. 全局参数

```text
bizdate = $[yyyy-MM-dd-1]
```

## 5. 工作流分层设计

```text
ODS 建表
  -> ODS 分区加载
  -> DWD 明细清洗层
  -> DWS 汇总层
  -> ADS 应用结果层
  -> 数据质量校验
```

调度链路包含 `ods_load_retail` 节点，避免 DWD 直接依赖 ODS 建表节点。`00_ods_retail_hive.sql` 负责创建/准备 ODS 表，`00_load_ods_retail_hive.sql` 负责把 `retail` 源表数据写入 `ods_retail_hive` 指定业务日期分区。

## 6. 任务节点列表

| 序号 | 节点名称 | 作用 | SQL 文件 |
|---:|---|---|---|
| 1 | ods_create_retail | 创建/准备 ODS 分区表 | 00_ods_retail_hive.sql |
| 2 | ods_load_retail | 将 retail 源表数据写入 ods_retail_hive 正式 ODS 分区表 | 00_load_ods_retail_hive.sql |
| 3 | dwd_create_table | 创建 DWD 清洗明细表 | 01_dwd_retail_clean_hive.sql |
| 4 | dwd_load_clean_data | 从 ODS 分区加载并清洗 DWD 明细数据 | 02_load_dwd_retail_clean_hive.sql |
| 5 | dws_customer_value | 生成客户价值汇总 | 03_dws_customer_value_hive.sql |
| 6 | dws_sales_summary | 生成国家销售汇总 | 04_dws_sales_summary_hive.sql |
| 7 | ads_high_value_customer_sales_contribution | 高价值客户销售贡献分析 | 05_ads_high_value_customer_sales_contribution_hive.sql |
| 8 | ads_customer_level_distribution | 客户等级分布分析 | 06_ads_customer_level_distribution_hive.sql |
| 9 | ads_country_sales_rank | 国家销售排行分析 | 07_ads_country_sales_rank_hive.sql |
| 10 | ads_high_value_customer_preference | 高价值客户商品偏好分析 | 08_ads_high_value_customer_preference_hive.sql |
| 11 | hive_data_quality_check | ADS 结果数据质量校验 | 09_check_hive_result.sql |

## 7. 调度执行方式

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/SQL文件名
"
```

## 8. DAG 依赖关系

```text
ods_create_retail
  -> ods_load_retail
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
ads_high_value_customer_preference
ads_country_sales_rank
  -> hive_data_quality_check
```

## 9. 数据质量校验设计

工作流最后设置 `hive_data_quality_check` 节点，对 ADS 层结果数据进行校验。MySQL 侧保留 `dq_check_result.sql` 和 `etl_task_log_v2.sql` 两类工程化表设计，便于后续扩展质量校验结果落表和任务状态追踪。

## 10. GitHub 安全说明

公开仓库中的 DolphinScheduler 示例配置只保留 `${HIVE_USER}`、`${HIVE_HOST}`、`${PROJECT_HOME}` 等占位符，不保留真实服务器账号、真实 IP 或明文密码。实际运行时，建议在部署环境中通过环境变量、密钥或 DolphinScheduler 环境管理能力配置连接信息。


## 11. 工作流 JSON 说明

`retail_hive_offline_warehouse_daily_demo.json` 用于公开仓库展示任务节点、Shell 模板和 DAG 依赖说明。不同 DolphinScheduler 版本的导入字段可能存在差异，实际迁移工作流时建议以 DolphinScheduler 页面重新导出的官方 JSON 为准。

## 12. 后续优化方向

1. DolphinScheduler 元数据库持久化。
2. 使用 SSH 免密或密钥方式，避免脚本或工作流配置中保存明文密码。
3. 将质量校验结果落入 `dq_check_result` 表。
4. 将每个任务的 START/SUCCESS/FAILED 状态写入 `etl_task_log_v2` 表。
5. 增加失败告警和重试策略。
