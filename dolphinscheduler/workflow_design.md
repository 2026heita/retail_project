# DolphinScheduler 调度设计说明

## 1. 接入目的
原项目已经具备 MySQL / Hive SQL 脚本、统一执行脚本和数据质量校验脚本。接入 DolphinScheduler 后，将 Hive 离线数仓链路拆分为可视化 DAG 任务节点，实现任务依赖编排、按业务日期调度、历史分区补数、运行过程留痕和数据质量校验。

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
ODS 原始层
  -> DWD 明细清洗层
  -> DWS 汇总层
  -> ADS 应用结果层
  -> 数据质量校验
```

## 6. 任务节点列表
| 序号 | 节点名称 | 作用 | SQL 文件 |
|---:|---|---|---|
| 1 | ods_create_retail | 创建/准备 ODS 层数据 | 00_ods_retail_hive.sql |
| 2 | dwd_create_table | 创建 DWD 清洗明细表 | 01_dwd_retail_clean_hive.sql |
| 3 | dwd_load_clean_data | 加载清洗后的 DWD 数据 | 02_load_dwd_retail_clean_hive.sql |
| 4 | dws_customer_value | 生成客户价值汇总 | 03_dws_customer_value_hive.sql |
| 5 | dws_sales_summary | 生成销售汇总 | 04_dws_sales_summary_hive.sql |
| 6 | ads_high_value_customer_sales_contribution | 高价值客户销售贡献分析 | 05_ads_high_value_customer_sales_contribution_hive.sql |
| 7 | ads_customer_level_distribution | 客户等级分布分析 | 06_ads_customer_level_distribution_hive.sql |
| 8 | ads_country_sales_rank | 国家销售排行分析 | 07_ads_country_sales_rank_hive.sql |
| 9 | ads_high_value_customer_preference | 高价值客户商品偏好分析 | 08_ads_high_value_customer_preference_hive.sql |
| 10 | hive_data_quality_check | ADS 结果数据质量校验 | 09_check_hive_result.sql |

## 7. 调度执行方式
```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/SQL文件名
"
```

## 8. 数据质量校验设计
工作流最后设置 `hive_data_quality_check` 节点，对 ADS 层结果数据进行校验。MySQL 侧保留 `dq_check_result.sql` 和 `etl_task_log_v2.sql` 两类工程化表设计，便于后续扩展质量校验结果落表和任务状态追踪。

## 9. 后续优化方向
1. DolphinScheduler 元数据库持久化。
2. 使用 SSH 免密或密钥方式，避免脚本或工作流配置中保存明文密码。
3. 将质量校验结果落入 dq_check_result 表。
4. 将每个任务的 START/SUCCESS/FAILED 状态写入 etl_task_log_v2 表。
5. 增加失败告警和重试策略。
