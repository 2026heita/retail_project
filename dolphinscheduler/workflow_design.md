# DolphinScheduler 调度设计说明

## 1. 接入目的

原项目已经具备 MySQL / Hive SQL 脚本、统一执行脚本和数据质量校验脚本。接入 DolphinScheduler 后，将 Hive 离线数仓链路拆分为可视化 DAG 任务节点，实现：

- 按业务日期统一调度；
- 节点依赖编排与失败阻断；
- 工作流、任务实例和日志留痕；
- DWD 进入 DWS 前的数据质量门禁；
- ADS 结果层的最终检查；
- 为后续补数、告警、重试和完整星型链路编排提供扩展基础。

本项目当前同时保留两种执行方式：

1. DolphinScheduler 12 节点演示 DAG，用于展示可视化任务编排和 DWD 质量门禁；
2. `run_all_hive.sh` 15 步完整 Shell 主链路，用于执行 DWD、DWS/ADS、星型模型三级质量门禁。

两者职责不同，文档中不把当前 12 节点演示 DAG 描述成已经包含完整星型模型。

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
ODS → DWD → DWD质量门禁 → DWS → ADS → 结果检查
```

完整 Shell 主链路为：

```text
ODS → DWD → DWD质量门禁
    → DWS / ADS → 结果质量门禁
    → 星型模型 → 星型质量门禁
    → 结果展示
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

当前 DolphinScheduler 演示 DAG：

```text
ODS 建表与分区加载
  → DWD 明细清洗
  → DWD 数据质量门禁
  → DWS 主题汇总
  → ADS 应用指标
  → 结果检查
```

其中：

- `dwd_quality_gate` 是硬门禁，BLOCK 规则失败时直接阻断 DWS 与 ADS；
- `hive_data_quality_check` 位于流程末尾，执行结果展示与人工验收查询；
- 当前导入 JSON 仍是 12 节点演示 DAG，没有直接展开 DWS/ADS 结果门禁和星型模型节点；
- 完整三级门禁已在 `run_all_hive.sh` 中实现，后续可继续映射为 DolphinScheduler 节点。

## 6. 任务节点列表

| 序号 | 节点名称 | 作用 | 执行文件 |
|---:|---|---|---|
| 1 | `ods_create_retail` | 创建/准备 ODS 分区表 | `00_ods_retail_hive.sql` |
| 2 | `ods_load_retail` | 将源表数据写入 ODS 业务日期分区 | `00_load_ods_retail_hive.sql` |
| 3 | `dwd_create_table` | 创建 DWD 清洗明细表 | `01_dwd_retail_clean_hive.sql` |
| 4 | `dwd_load_clean_data` | 从 ODS 清洗并加载 DWD 分区 | `02_load_dwd_retail_clean_hive.sql` |
| 5 | `dwd_quality_gate` | 写入质量日志并在 BLOCK 规则失败时阻断下游 | `run_quality_gate_hive.sh` |
| 6 | `dws_customer_value` | 生成客户价值汇总 | `03_dws_customer_value_hive.sql` |
| 7 | `dws_sales_summary` | 生成国家销售汇总 | `04_dws_sales_summary_hive.sql` |
| 8 | `ads_high_value_customer_sales_contribution` | 高价值客户销售贡献分析 | `05_ads_high_value_customer_sales_contribution_hive.sql` |
| 9 | `ads_customer_level_distribution` | 客户等级分布分析 | `06_ads_customer_level_distribution_hive.sql` |
| 10 | `ads_country_sales_rank` | 国家销售排行分析 | `07_ads_country_sales_rank_hive.sql` |
| 11 | `ads_high_value_customer_preference` | 高价值客户商品偏好分析 | `08_ads_high_value_customer_preference_hive.sql` |
| 12 | `hive_data_quality_check` | 展示并检查 ODS / DWD / DWS / ADS 结果 | `09_check_hive_result.sql` |

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

完整 Shell 主链路也可以作为单个 DolphinScheduler Shell 节点调用：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
bash ${PROJECT_HOME}/hive/run_all_hive.sh ${bizdate}
"
```

这种方式能直接复用已经验证过的 15 步主链路，但会降低 DolphinScheduler DAG 中的节点可视化粒度，因此当前仓库仍保留拆分节点的演示方案。

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
3. 查询 `quality_log_hive` 中 `check_status='FAIL'` 且 `check_level='BLOCK'` 的记录数；
4. 当 `failed_count > 0` 或结果无法读取时返回非零状态；
5. 只有 `failed_count=0` 时允许继续执行 DWS 和 ADS。

当前 DWD 门禁包括无效数量、无效价格、空客户、DWD 分区非空、ODS 与 DWD 行数对账和时间格式检查。

### 9.2 演示 DAG 结果检查

`hive_data_quality_check` 执行 `09_check_hive_result.sql`，用于展示和人工核对：

- ODS / DWD / DWS / ADS 各层分区行数；
- DWD 清洗质量；
- DWS 客户分层边界；
- ADS 指标范围与排行字段。

该节点当前是查询式结果检查，不是依靠质量日志表和非零退出码实现的硬门禁。

### 9.3 完整 Shell 主链路质量门禁

`run_all_hive.sh` 中已经实现三级质量门禁：

1. `run_quality_gate_hive.sh`：DWD 前置门禁；
2. `run_result_quality_gate_hive.sh`：DWS / ADS 后置门禁；
3. `run_star_quality_gate_hive.sh`：星型模型门禁，由 `run_star_schema_hive.sh` 自动调用。

三类门禁都区分 BLOCK 和 WARN。BLOCK 失败时返回非零退出码并停止下游任务，WARN 只记录不阻断。

当前 DolphinScheduler 演示 JSON 只直接展开了第一层 DWD 门禁。完整三级门禁的真实实现以 Shell 主链路为准。

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

该 JSON 对应当前 12 节点演示 DAG，不代表完整 15 步 Shell 主链路已经全部拆分成 DolphinScheduler 节点。

不同项目和不同环境的项目编码可能不同。跨环境迁移时，建议先在目标环境创建一个最小工作流并原生导出，再以该文件为模板调整。

## 12. 验收结果

当前 DolphinScheduler 演示工作流已完成真实运行验收：

- 12 个任务节点全部执行成功；
- DWD 质量门禁输出 `Data quality gate passed.`；
- `failed_count=0`；
- 工作流实例与任务实例正常落入 MySQL 元数据库；
- DolphinScheduler 容器重启后工作流和实例记录仍可保留。

完整 Shell 主链路另外完成了以下验收：

- `run_all_hive.sh` 已接入 DWD、DWS/ADS 和星型模型三级质量门禁；
- 星型模型 12 条质量规则在 `2026-04-08` 全部 PASS；
- 空业务日期测试能够返回非零退出码并阻断任务。

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

1. 将 DWS/ADS 结果门禁和星型模型链路继续拆分为 DolphinScheduler 可视化节点；
2. 增加任务失败告警和通知策略；
3. 增加自动重试和超时策略；
4. 增加历史分区补数工作流；
5. 增加 DolphinScheduler 集群化部署和 Worker 分组。