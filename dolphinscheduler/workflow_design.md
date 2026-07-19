# DolphinScheduler 调度设计说明

## 1. 接入目的

原项目已经具备 MySQL / Hive SQL 脚本、统一执行脚本和数据质量校验脚本。接入 DolphinScheduler 后，将 Hive 离线数仓链路拆分为可视化 DAG 任务节点，实现：

- 按业务日期统一调度；
- 节点依赖编排与失败阻断；
- 工作流、任务实例和日志留痕；
- DWD 进入 DWS 前的数据质量门禁；
- ADS 结果层的最终质量检查；
- 为后续补数、告警和重试提供扩展基础。

## 2. 当前实现方式

本项目使用 DolphinScheduler 3.2.2 的 Shell 节点调度 Hive SQL。

DolphinScheduler 运行在 Docker 容器中，容器通过 SSH 调用部署 Hadoop / Hive 的 Linux 主机执行 Hive SQL，不在容器内直接安装 Hive 客户端。

```text
DolphinScheduler 3.2.2（Docker）
  ├── 元数据库：MySQL 持久化
  ├── MySQL Connector/J
  └── OpenSSH Client
          ↓ SSH
Hadoop / HDFS / Hive 主机
          ↓
ODS → DWD → 质量门禁 → DWS → ADS → 最终质量检查
```

公开仓库不保留真实服务器账号、真实 IP、数据库密码或 SSH 私钥，统一使用 `${HIVE_USER}`、`${HIVE_HOST}`、`${PROJECT_HOME}` 等占位参数。

## 3. 工作流名称

```text
retail_hive_offline_warehouse_daily
```

实际导入后，DolphinScheduler 可能在名称后自动追加导入时间戳，不影响工作流逻辑。

## 4. 全局参数

| 参数 | 示例值 | 说明 |
|---|---|---|
| `bizdate` | `$[yyyy-MM-dd-1]` | 默认执行前一业务日 |
| `HIVE_USER` | `your_hive_user` | Hive 主机 SSH 用户 |
| `HIVE_HOST` | `your_hive_host` | Hive 主机地址 |
| `PROJECT_HOME` | `/path/to/retail_hive_project` | 服务器项目根目录 |

仓库中的 SQL 和脚本保存在：

```text
hive_sql/
```

服务器实际运行目录为：

```text
${PROJECT_HOME}/hive/
```

因此 DolphinScheduler 节点使用 `${PROJECT_HOME}/hive/*.sql` 和 `${PROJECT_HOME}/hive/*.sh`。

## 5. 工作流分层设计

```text
ODS 建表与分区加载
  → DWD 明细清洗
  → DWD 数据质量门禁
  → DWS 主题汇总
  → ADS 应用指标
  → ADS 最终质量检查
```

其中：

- `dwd_quality_gate` 是硬门禁，失败时直接阻断 DWS 与 ADS；
- `hive_data_quality_check` 位于流程末尾，用于检查 ADS 结果是否满足预期。

## 6. 任务节点列表

| 序号 | 节点名称 | 作用 | 执行文件 |
|---:|---|---|---|
| 1 | `ods_create_retail` | 创建/准备 ODS 分区表 | `00_ods_retail_hive.sql` |
| 2 | `ods_load_retail` | 将源表数据写入 ODS 业务日期分区 | `00_load_ods_retail_hive.sql` |
| 3 | `dwd_create_table` | 创建 DWD 清洗明细表 | `01_dwd_retail_clean_hive.sql` |
| 4 | `dwd_load_clean_data` | 从 ODS 清洗并加载 DWD 分区 | `02_load_dwd_retail_clean_hive.sql` |
| 5 | `dwd_quality_gate` | 写入质量日志并在存在 FAIL 时阻断下游 | `run_quality_gate_hive.sh` |
| 6 | `dws_customer_value` | 生成客户价值汇总 | `03_dws_customer_value_hive.sql` |
| 7 | `dws_sales_summary` | 生成国家销售汇总 | `04_dws_sales_summary_hive.sql` |
| 8 | `ads_high_value_customer_sales_contribution` | 高价值客户销售贡献分析 | `05_ads_high_value_customer_sales_contribution_hive.sql` |
| 9 | `ads_customer_level_distribution` | 客户等级分布分析 | `06_ads_customer_level_distribution_hive.sql` |
| 10 | `ads_country_sales_rank` | 国家销售排行分析 | `07_ads_country_sales_rank_hive.sql` |
| 11 | `ads_high_value_customer_preference` | 高价值客户商品偏好分析 | `08_ads_high_value_customer_preference_hive.sql` |
| 12 | `hive_data_quality_check` | ADS 结果数据质量校验 | `09_check_hive_result.sql` |

## 7. 调度执行方式

普通 Hive SQL 节点：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/SQL文件名
"
```

DWD 质量门禁节点：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
bash ${PROJECT_HOME}/hive/run_quality_gate_hive.sh ${bizdate}
"
```

## 8. DAG 依赖关系

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

ads_high_value_customer_sales_contribution
ads_customer_level_distribution
ads_high_value_customer_preference
ads_country_sales_rank
  → hive_data_quality_check
```

## 9. 数据质量校验设计

### 9.1 DWD 质量门禁

`dwd_quality_gate` 调用 `run_quality_gate_hive.sh`，依次执行：

1. `23_quality_log_hive.sql`：创建质量日志表；
2. `24_load_quality_log_hive.sql`：写入指定 `bizdate` 的检查结果；
3. 查询 `quality_log_hive` 中 `check_status='FAIL'` 的记录数；
4. 当 `failed_count > 0` 或结果无法读取时返回非零状态；
5. 只有 `failed_count=0` 时允许继续执行 DWS 和 ADS。

### 9.2 ADS 最终质量检查

`hive_data_quality_check` 执行 `09_check_hive_result.sql`，用于核对 ADS 结果表是否存在数据和是否满足最终输出要求。

DWD 质量门禁与 ADS 最终检查职责不同：前者负责阻断脏数据继续向下游传播，后者负责确认结果层产出完整。

## 10. DolphinScheduler 元数据库持久化

Standalone 默认 H2 内存数据库不适合长期保存项目元数据。本项目已将 DolphinScheduler 元数据库迁移到 MySQL，并通过自定义镜像加入：

- `mysql-connector-j-8.0.33.jar`；
- `openssh-client`。

迁移后，项目、工作流定义、任务关系、工作流实例和任务实例可在容器重启后继续保留。

## 11. 工作流 JSON 说明

`retail_hive_offline_warehouse_daily_demo.json` 使用 DolphinScheduler 3.2.2 原生导出结构作为基础，必须包含：

- 非空的 `processTaskRelationList`；
- 合法的数值型 `preTaskCode`、`postTaskCode`；
- 首节点根关系（`preTaskCode = 0`）；
- 与任务关系编码一致的 `taskDefinitionList`。

不同项目和不同环境的项目编码可能不同。跨环境迁移时，建议先在目标环境创建一个最小工作流并原生导出，再以该文件为模板调整。

## 12. 验收结果

当前工作流已完成真实运行验收：

- 12 个任务节点全部执行成功；
- DWD 质量门禁输出 `Data quality gate passed.`；
- `failed_count=0`；
- 工作流实例与任务实例正常落入 MySQL 元数据库；
- DolphinScheduler 容器重启后工作流和实例记录仍可保留。

验收截图：

- `docs/result_screenshots/01_ds_workflow_instance_success.png`
- `docs/result_screenshots/02_ds_dag_quality_gate_success.png`
- `docs/result_screenshots/03_dwd_quality_gate_passed.png`

## 13. GitHub 安全说明

公开仓库不得提交：

- 真实服务器 IP 和 SSH 用户；
- MySQL 明文密码；
- 实际 `application.yaml` 私密配置；
- SSH 私钥或 `.ssh` 目录；
- 内网完整访问地址。

## 14. 后续优化方向

1. 增加任务失败告警和通知策略；
2. 增加自动重试和超时策略；
3. 增加历史分区补数工作流；
4. 将更多质量规则扩展到完整性、唯一性、及时性和一致性维度；
5. 增加 DolphinScheduler 集群化部署和 Worker 分组。