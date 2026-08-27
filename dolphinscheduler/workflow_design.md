# DolphinScheduler 工作流设计说明

> 文件属性：长期保留，提交代码仓库
> 对应文件：`dolphinscheduler/workflow_design.md`
> 适用范围：当前仓库中的 DolphinScheduler 12 节点演示工作流

---

## 1. 接入目的

Hive 数仓已经具备 SQL、Shell 主脚本和质量门禁。接入 DolphinScheduler 的主要目的不是替代 SQL，而是把任务依赖和运行状态显式化：

- 统一传递业务日期；
- 展示 ODS、DWD、DWS、ADS 的上下游关系；
- 在 DWD 质量失败时阻断下游；
- 并行执行可以独立运行的主题任务；
- 保存工作流实例、任务实例和运行日志；
- 支持失败节点修复后的重跑；
- 为后续加入结果门禁、星型模型、告警和补数工作流提供基础。

当前项目同时保留两种执行方式：

```text
完整执行：
hive_sql/run_all_hive.sh（当前 20 步主链路）

调度展示：
DolphinScheduler 12 节点演示 DAG
```

二者不能描述为完全一致。

---

## 2. 部署架构

当前设计使用 DolphinScheduler 3.2.2 的 Shell 节点，通过 SSH 调用 Hadoop/Hive 主机：

```text
DolphinScheduler 3.2.2（Docker）
  ├── MySQL 元数据库
  ├── MySQL Connector/J
  └── OpenSSH Client
          │
          │ SSH
          ▼
Hadoop / HDFS / Hive 主机
  └── ${PROJECT_HOME}/hive/
```

采用 SSH 方式的原因：

- DolphinScheduler 容器不必安装完整 Hive 客户端；
- Hive 环境变量、配置文件和依赖继续由 Hadoop/Hive 主机维护；
- 调度平台负责依赖、状态和日志，远程主机负责实际计算。

公开仓库不保存真实主机、用户、密码或 SSH 私钥。

---

## 3. 工作流文件状态

导入文件：

```text
retail_hive_offline_warehouse_daily_demo.json
```

当前 JSON 已核对：

```text
任务节点数：12
任务关系数：15
发布状态：OFFLINE
schedule：null
任务类型：SHELL
失败重试次数：0
任务超时：关闭
```

JSON 中的流程名称带有导入时间后缀。它不影响 DAG 逻辑，导入后可在目标环境中调整显示名称。

`schedule=null` 表示该公开模板不携带自动启用的定时计划。正确流程是：

```text
导入
→ 修改环境参数
→ 手动执行指定 bizdate
→ 检查结果
→ 再配置正式调度
```

---

## 4. 全局参数

当前模板统一使用：

| 参数 | 模板值 | 说明 |
|---|---|---|
| `bizdate` | `$[yyyy-MM-dd-1]` | 默认处理调度日前一天 |
| `HIVE_USER` | `your_hive_user` | Hive 主机 SSH 用户 |
| `HIVE_HOST` | `your_hive_host` | Hive 主机地址 |
| `PROJECT_HOME` | `/home/your_user/retail_hive_project` | 远程项目根目录 |

JSON 中以下三种参数表示已经保持一致：

```text
globalParams
globalParamList
globalParamMap
```

任务命令从以下目录读取文件：

```text
${PROJECT_HOME}/hive/
```

仓库目录名是：

```text
hive_sql/
```

部署时可以把它上传或同步为服务器上的 `hive/`，但实际路径必须与调度命令一致。

---

## 5. 当前 12 节点 DAG

### 5.1 节点清单

| 序号 | 节点 | 执行文件 |
|---:|---|---|
| 1 | `ods_create_retail` | `00_ods_retail_hive.sql` |
| 2 | `ods_load_retail` | `00_load_ods_retail_hive.sql` |
| 3 | `dwd_create_table` | `01_dwd_retail_clean_hive.sql` |
| 4 | `dwd_load_clean_data` | `02_load_dwd_retail_clean_hive.sql` |
| 5 | `dwd_quality_gate` | `run_quality_gate_hive.sh` |
| 6 | `dws_customer_value` | `03_dws_customer_value_hive.sql` |
| 7 | `dws_sales_summary` | `04_dws_sales_summary_hive.sql` |
| 8 | `ads_high_value_customer_sales_contribution` | `05_ads_high_value_customer_sales_contribution_hive.sql` |
| 9 | `ads_customer_level_distribution` | `06_ads_customer_level_distribution_hive.sql` |
| 10 | `ads_country_sales_rank` | `07_ads_country_sales_rank_hive.sql` |
| 11 | `ads_high_value_customer_preference` | `08_ads_high_value_customer_preference_hive.sql` |
| 12 | `hive_data_quality_check` | `09_check_hive_result.sql` |

### 5.2 依赖关系

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

设计原则：

- ODS 和 DWD 严格串行；
- DWD 门禁通过后才启动主题层；
- 两张 DWS 可以并行；
- 同一 DWS 下的 ADS 可以并行；
- 四张 ADS 全部成功后执行最终检查。

---

## 6. Shell 节点执行方式

普通 Hive SQL 节点使用：

```bash
ssh \
  -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes \
  ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/SQL文件名
"
```

DWD 门禁节点使用：

```bash
ssh \
  -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes \
  ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
bash ${PROJECT_HOME}/hive/run_quality_gate_hive.sh ${bizdate}
"
```

关键要求：

- SSH 必须使用密钥认证；
- `BatchMode=yes` 防止任务等待交互式密码；
- 远程 Shell 或 Hive 返回非零状态时，DolphinScheduler 节点应失败；
- Hive 环境变量应由远程主机负责加载。

---

## 7. 数据质量设计

### 7.1 DWD 质量门禁

`dwd_quality_gate` 调用：

```text
run_quality_gate_hive.sh
```

内部流程：

```text
创建质量日志表
→ 写入当前 bizdate 的 DWD 检查结果
→ 查询 BLOCK + FAIL 数量
→ failed_count > 0 时返回非零状态
```

当前包括 6 条 DWD BLOCK 规则：

- 无效数量；
- 无效价格；
- 空客户；
- DWD 分区非空；
- ODS 理论有效量与 DWD 实际量对账；
- DWD 时间格式检查。

这是当前 12 节点 DAG 中真正控制下游是否继续执行的硬门禁。

### 7.2 最终结果检查

`hive_data_quality_check` 执行：

```text
09_check_hive_result.sql
```

它主要输出：

- ODS、DWD、DWS、ADS 分区数量；
- DWD 清洗结果；
- 客户分层；
- ADS 指标范围和排名结果。

该 SQL 主要用于查询展示和人工验收，没有形成与 `run_result_quality_gate_hive.sh` 等价的完整阻断逻辑。因此不能把它描述为最新 DWS/ADS 结果门禁。

---

## 8. 与最新 Hive 代码的兼容性边界

这是当前文档中最重要的边界。

最新仓库中的：

```text
00_load_ods_retail_hive.sql
```

已经改为从：

```text
ods_retail_raw_hive
```

读取数据。

但当前 12 节点 DAG 没有以下前置节点：

```text
创建 ODS Raw
加载 ODS Raw
创建 ODS Reject
加载 ODS Reject
ODS 入仓完整性门禁
```

因此，当前 JSON 与最新 ODS SQL **不是一套完整自包含的运行组合**。

过去的 12 节点成功截图证明的是当时部署版本的调度链路已经运行成功；它不能证明把当前仓库全部最新 SQL 直接覆盖到旧服务器后仍能原样运行。

安全处理方式只有两种：

### 方式一：升级 DAG

在 `ods_load_retail` 之前增加：

```text
ods_raw_create
→ ods_raw_load
→ ods_reject_create
→ ods_reject_load
→ ods_normal_create
→ ods_normal_load
→ ods_ingestion_gate
```

然后继续执行 DWD。

### 方式二：单节点调用完整主脚本

由一个 Shell 节点执行：

```bash
bash ${PROJECT_HOME}/hive/run_all_hive.sh ${bizdate}
```

优点是直接复用已验证的 20 步链路；缺点是 DolphinScheduler 页面无法看到每个内部步骤的独立节点状态。

在新 DAG 完成并验收之前，不应宣称当前 JSON 已完整覆盖最新代码。

---

## 9. 当前未进入 DAG 的能力

最新 `run_all_hive.sh` 已包含，但当前 JSON 未拆分的能力：

- ODS Raw；
- ODS Reject；
- ODS 入仓完整性门禁；
- ODS 内容检查；
- DWS/ADS 结果门禁；
- `dim_user`、`dim_product`、`dim_date`、`dim_geo`；
- `fact_order`；
- 星型客户价值 DWS；
- 星型模型门禁；
- 最终完整结果展示。

统一口径：

```text
最完整实现：21 步 Shell 主链路
调度演示：12 节点 DolphinScheduler DAG
```

---

## 10. JSON 导入注意事项

DolphinScheduler 3.2.2 导入文件需要保持：

- `taskDefinitionList` 中任务编码合法；
- `processTaskRelationList` 存在且非空；
- 首节点具有 `preTaskCode=0` 的根关系；
- 所有 `postTaskCode` 都能匹配任务定义；
- 上下游关系不能随意删除；
- 参数值不能残留真实服务器信息。

建议验证：

```powershell
python -c "import json,pathlib; p=pathlib.Path(r'.\dolphinscheduler\retail_hive_offline_warehouse_daily_demo.json'); json.loads(p.read_text(encoding='utf-8-sig')); print('JSON format OK')"
```

语法通过只代表 JSON 格式正确，不代表：

- 远程主机可连接；
- SQL 文件存在；
- DAG 与最新代码兼容；
- 业务结果正确。

导入后仍需手动执行验收。

---

## 11. 失败处理与重跑

当前任务配置：

```text
failRetryTimes = 0
timeoutFlag = CLOSE
```

这意味着节点失败后不会自动重试，也没有任务级超时。

当前阶段保留该配置的原因：

- SQL 逻辑错误不应盲目重试；
- SSH、Hive 环境和数据质量失败需要先判断原因；
- 学习项目优先保持行为清晰。

重跑原则：

1. SSH 或临时资源故障：修复后重跑失败节点及下游；
2. SQL 逻辑错误：修复代码后使用同一 `bizdate` 重跑；
3. DWD 门禁失败：修复上游数据或规则后，从对应上游节点重跑；
4. 历史 SCD2 日期修正：不能只重跑单个中间日期，应升序回刷后续日期；
5. `INSERT OVERWRITE` 可以防止同一分区不断追加，但完整幂等性仍应由指纹脚本验证。

后续增加自动重试和超时时，应区分：

```text
可重试的基础设施故障
不可盲目重试的 SQL 或质量故障
```

---

## 12. 已有验收证据

仓库中保留的截图包括：

```text
docs/result_screenshots/01_ds_workflow_instance_success.png
docs/result_screenshots/02_ds_dag_quality_gate_success.png
docs/result_screenshots/03_dwd_quality_gate_passed.png
```

这些截图证明：

- 当时的 12 节点工作流实例执行成功；
- DAG 依赖关系可以正常运行；
- DWD 质量门禁输出通过；
- DolphinScheduler 任务和实例可以保留在 MySQL 元数据库中。

它们属于历史调度验收证据，不等同于最新 20 步 Shell 链路的完整调度验收。

---

## 13. 部署检查清单

导入和运行前检查：

```text
1. DolphinScheduler 元数据库使用 MySQL，而不是临时 H2。
2. 容器中存在 MySQL Connector/J。
3. Worker 容器中存在 ssh 客户端。
4. Worker 到 Hive 主机的 SSH 密钥认证正常。
5. HIVE_USER、HIVE_HOST、PROJECT_HOME 已替换为目标环境值。
6. ${PROJECT_HOME}/hive/ 下存在任务引用的文件。
7. Shell 文件具有执行权限。
8. 目标 Hive 源表和依赖表存在。
9. 当前使用的 DAG 与部署 SQL 版本一致。
10. 先用固定 bizdate 手动运行。
11. 检查 DWD 门禁失败数和各层结果。
12. 验收成功后再创建定时计划。
```

---

## 14. 后续升级顺序

建议按以下顺序升级调度：

1. 增加 ODS Raw 和 Reject 节点；
2. 增加 ODS 入仓完整性门禁；
3. 验证新 ODS 链路的成功和失败路径；
4. 增加 DWS/ADS 结果门禁；
5. 增加四张维表和事实表；
6. 增加星型 DWS 和星型门禁；
7. 增加任务超时、基础设施重试和告警；
8. 增加历史区间回刷专用工作流；
9. 全链路验收后重新导出公开模板 JSON。

---

## 15. 总结

当前 DolphinScheduler 设计已经展示了：

- Shell 节点通过 SSH 执行 Hive；
- 12 节点 DAG 依赖；
- DWD 质量失败阻断；
- DWS 和 ADS 并行；
- MySQL 元数据库持久化；
- 环境参数占位化；
- 调度实例和运行日志留痕。

同时需要明确：

> 当前 JSON 是历史已验收的 12 节点演示 DAG，最新仓库中的完整实现是 21 步 Shell 主链路。由于正常 ODS 已改为从 ODS Raw 读取，旧 DAG 不能在未补充 Raw 前置任务的情况下直接套用最新 SQL。