# Hive DolphinScheduler 任务节点配置

> 文件属性：长期保留，提交代码仓库
> 对应文件：`dolphinscheduler/hive_task_nodes.md`
> 适用范围：当前 12 节点 DolphinScheduler 演示 DAG

---

## 1. 当前工作流范围

DolphinScheduler 容器不直接运行 Hive 客户端。所有 Shell 节点通过 SSH 登录 Hadoop/Hive 主机，再执行远程 SQL 或 Shell 脚本。

当前演示 DAG 共 12 个节点：

```text
ods_create_retail
→ ods_load_retail
→ dwd_create_table
→ dwd_load_clean_data
→ dwd_quality_gate
→ DWS
→ ADS
→ hive_data_quality_check
```

其中：

- `dwd_quality_gate` 是当前 DAG 中的硬阻断门禁；
- `hive_data_quality_check` 主要负责结果查询和人工验收；
- 当前最新、最完整的 Hive 链路仍是 `hive_sql/run_all_hive.sh` 的 20 步流程。

---

## 2. 目录与全局参数

公开仓库目录：

```text
hive_sql/
```

服务器运行目录：

```text
${PROJECT_HOME}/hive/
```

DolphinScheduler 全局参数：

```text
bizdate=$[yyyy-MM-dd-1]
HIVE_USER=your_hive_user
HIVE_HOST=your_hive_host
PROJECT_HOME=/home/your_user/retail_hive_project
```

参数说明：

| 参数 | 说明 |
|---|---|
| `bizdate` | 本次处理的业务日期，默认是调度日前一天 |
| `HIVE_USER` | Hadoop/Hive 主机的 SSH 用户 |
| `HIVE_HOST` | Hadoop/Hive 主机地址 |
| `PROJECT_HOME` | 服务器项目根目录 |

公开仓库不得保存真实用户名、主机名、IP、密码或 SSH 私钥。

---

## 3. 通用 Shell 模板

### 3.1 普通 Hive SQL 节点

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

### 3.2 Hive Shell 门禁节点

```bash
ssh \
  -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes \
  ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
bash ${PROJECT_HOME}/hive/Shell脚本名 ${bizdate}
"
```

### 3.3 执行要求

- Worker 容器必须安装 OpenSSH Client；
- Worker 到 Hive 主机必须配置 SSH 密钥认证；
- `BatchMode=yes` 防止任务等待交互式密码；
- 远程命令返回非零状态时，DolphinScheduler 节点应失败；
- 服务器上的目录和文件名必须与任务命令一致；
- Shell 文件应使用 LF 换行并具有执行权限。

---

## 4. 任务节点明细

## 4.1 `ods_create_retail`

任务类型：

```text
SHELL
```

作用：

创建正常业务 ODS 表：

```text
ods_retail_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/00_ods_retail_hive.sql
"
```

上游任务：

```text
无
```

下游任务：

```text
ods_load_retail
```

兼容性说明：

该节点只创建正常 ODS 表，不创建当前最新链路所需的 ODS Raw 和 ODS Reject 表。

---

## 4.2 `ods_load_retail`

任务类型：

```text
SHELL
```

作用：

执行：

```text
00_load_ods_retail_hive.sql
```

将当前 `bizdate` 的正常业务数据写入：

```text
ods_retail_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/00_load_ods_retail_hive.sql
"
```

上游任务：

```text
ods_create_retail
```

下游任务：

```text
dwd_create_table
```

重要兼容性提示：

当前仓库中的 `00_load_ods_retail_hive.sql` 已改为从：

```text
ods_retail_raw_hive
```

读取数据，而当前 12 节点 DAG 没有创建和加载 ODS Raw 的前置任务。

因此，以下组合不能直接作为完整链路运行：

```text
旧 12 节点 DAG
+
当前最新 00_load_ods_retail_hive.sql
```

正式使用最新 SQL 前，应先升级 DAG，补充 Raw、Reject 和入仓门禁节点。

---

## 4.3 `dwd_create_table`

任务类型：

```text
SHELL
```

作用：

创建 DWD 清洗明细表：

```text
dwd_retail_clean_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/01_dwd_retail_clean_hive.sql
"
```

上游任务：

```text
ods_load_retail
```

下游任务：

```text
dwd_load_clean_data
```

---

## 4.4 `dwd_load_clean_data`

任务类型：

```text
SHELL
```

作用：

从当前 `bizdate` 的正常 ODS 分区加载并清洗 DWD 明细。

主要处理：

- 过滤无效数量；
- 过滤无效价格；
- 过滤空客户；
- 过滤取消或退货订单；
- 过滤关键字符串空值；
- 标准化订单时间；
- 计算销售金额。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/02_load_dwd_retail_clean_hive.sql
"
```

上游任务：

```text
dwd_create_table
```

下游任务：

```text
dwd_quality_gate
```

---

## 4.5 `dwd_quality_gate`

任务类型：

```text
SHELL
```

作用：

执行 DWD 数据质量门禁。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
bash ${PROJECT_HOME}/hive/run_quality_gate_hive.sh ${bizdate}
"
```

门禁流程：

```text
创建或确认 DWD 质量日志表
→ 写入当前 bizdate 的检查结果
→ 查询 BLOCK + FAIL 数量
→ failed_count > 0 时返回非零状态
```

当前 DWD 规则：

```text
DWD_001 - DWD_006
```

覆盖：

- 无效数量；
- 无效价格；
- 空客户；
- DWD 分区非空；
- ODS 理论有效量与 DWD 实际量对账；
- DWD 时间格式标准化。

成功时可看到：

```text
Data quality gate passed.
failed_count=0
```

失败情况：

- 存在 BLOCK 失败项；
- 无法执行质量 SQL；
- 无法读取失败数量；
- 远程 Shell 返回非零状态。

上游任务：

```text
dwd_load_clean_data
```

下游任务：

```text
dws_customer_value
dws_sales_summary
```

---

## 4.6 `dws_customer_value`

任务类型：

```text
SHELL
```

作用：

生成客户价值主题汇总：

```text
dws_customer_value_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/03_dws_customer_value_hive.sql
"
```

上游任务：

```text
dwd_quality_gate
```

下游任务：

```text
ads_high_value_customer_sales_contribution
ads_customer_level_distribution
ads_high_value_customer_preference
```

---

## 4.7 `dws_sales_summary`

任务类型：

```text
SHELL
```

作用：

生成国家销售主题汇总：

```text
dws_sales_summary_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/04_dws_sales_summary_hive.sql
"
```

上游任务：

```text
dwd_quality_gate
```

下游任务：

```text
ads_country_sales_rank
```

---

## 4.8 `ads_high_value_customer_sales_contribution`

任务类型：

```text
SHELL
```

作用：

生成高价值客户的客户数、订单和销售贡献指标：

```text
ads_high_value_customer_sales_contribution_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/05_ads_high_value_customer_sales_contribution_hive.sql
"
```

上游任务：

```text
dws_customer_value
```

下游任务：

```text
hive_data_quality_check
```

---

## 4.9 `ads_customer_level_distribution`

任务类型：

```text
SHELL
```

作用：

生成客户层级的客户数量和销售额分布：

```text
ads_customer_level_distribution_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/06_ads_customer_level_distribution_hive.sql
"
```

上游任务：

```text
dws_customer_value
```

下游任务：

```text
hive_data_quality_check
```

---

## 4.10 `ads_country_sales_rank`

任务类型：

```text
SHELL
```

作用：

生成国家销售排名：

```text
ads_country_sales_rank_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/07_ads_country_sales_rank_hive.sql
"
```

上游任务：

```text
dws_sales_summary
```

下游任务：

```text
hive_data_quality_check
```

---

## 4.11 `ads_high_value_customer_preference`

任务类型：

```text
SHELL
```

作用：

生成高价值客户商品偏好排名：

```text
ads_high_value_customer_preference_hive
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/08_ads_high_value_customer_preference_hive.sql
"
```

上游任务：

```text
dws_customer_value
```

下游任务：

```text
hive_data_quality_check
```

---

## 4.12 `hive_data_quality_check`

任务类型：

```text
SHELL
```

作用：

执行最终结果查询：

```text
09_check_hive_result.sql
```

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive \
  --hiveconf bizdate=${bizdate} \
  -f ${PROJECT_HOME}/hive/09_check_hive_result.sql
"
```

上游任务：

```text
ads_high_value_customer_sales_contribution
ads_customer_level_distribution
ads_country_sales_rank
ads_high_value_customer_preference
```

下游任务：

```text
无
```

实际职责：

- 输出 ODS、DWD、DWS 和 ADS 分区数据量；
- 展示 DWD 清洗结果；
- 展示客户价值分层和 ADS 指标；
- 作为工作流末端的人工验收节点。

边界：

`09_check_hive_result.sql` 主要由查询语句组成，没有形成与：

```text
run_result_quality_gate_hive.sh
```

等价的 `BLOCK + FAIL → 非零退出码` 机制。

因此该节点应称为：

```text
最终结果检查
```

不应称为：

```text
完整 DWS/ADS 阻断门禁
```

---

## 5. DAG 依赖关系

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

当前实际包含：

```text
12 个任务节点
15 条任务关系
```

---

## 6. 当前 DAG 未包含的最新能力

当前 `run_all_hive.sh` 已实现但本 DAG 未包含：

```text
ODS Raw 创建
ODS Raw 加载
ODS Reject 创建
ODS Reject 加载
ODS 入仓完整性门禁
ODS 内容检查
DWS/ADS 结果质量门禁
dim_user
dim_product
dim_date
dim_geo
fact_order
星型客户价值 DWS
星型模型质量门禁
完整最终结果展示
```

因此统一表述为：

```text
当前最完整执行链路：
hive_sql/run_all_hive.sh

当前调度演示：
DolphinScheduler 12 节点 DAG
```

---

## 7. 运行前检查

### 7.1 在 Hadoop/Hive 主机检查

```bash
hdfs dfs -ls /
hive -e "SHOW DATABASES;"
ls -l ${PROJECT_HOME}/hive/
```

### 7.2 在 DolphinScheduler Worker 中检查

```bash
ssh -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} hostname
ssh -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "hive -e 'SHOW DATABASES;'"
```

### 7.3 检查文件格式

```bash
file ${PROJECT_HOME}/hive/*.sh
bash -n ${PROJECT_HOME}/hive/run_quality_gate_hive.sh
```

Shell 文件应使用：

```text
Unix LF
```

而不是：

```text
Windows CRLF
```

---

## 8. 常见问题

### 8.1 `ssh: command not found`

原因：

```text
DolphinScheduler Worker 镜像缺少 OpenSSH Client
```

处理：

```text
在自定义镜像中安装 openssh-client，然后重新构建并启动容器。
```

### 8.2 `Permission denied`

可能原因：

- SSH 私钥没有挂载；
- 公钥未加入远程主机；
- 文件权限不正确；
- 登录用户不正确；
- `BatchMode=yes` 下无法使用密码认证。

### 8.3 `Connection refused`

例如：

```text
hadoop100:8020 Connection refused
```

可能原因：

- HDFS NameNode 未启动；
- 地址或端口错误；
- 容器到主机网络不可达；
- Hadoop 配置指向错误环境。

### 8.4 `pipefail: invalid option name`

常见原因：

```text
Shell 文件使用 Windows CRLF 换行
```

需要转换为 LF。

### 8.5 `No such file or directory`

检查：

```text
PROJECT_HOME
服务器目录是否为 hive/
文件名大小写
Shell 执行权限
```

### 8.6 `Table not found: ods_retail_raw_hive`

原因：

```text
使用了最新正常 ODS 加载 SQL，但仍运行旧 12 节点 DAG。
```

处理：

```text
补充 ODS Raw 创建和加载节点，或使用完整 run_all_hive.sh。
```

### 8.7 工作流显示成功，但最终指标异常

原因：

```text
hive_data_quality_check 当前主要输出查询结果，不会对所有 DWS/ADS 异常主动返回非零状态。
```

处理：

```text
人工检查输出，或升级 DAG 并接入 run_result_quality_gate_hive.sh。
```

---

## 9. 升级到最新链路时的建议节点

建议将 ODS 部分升级为：

```text
ods_raw_create
→ ods_raw_load
→ ods_reject_create
→ ods_reject_load
→ ods_normal_create
→ ods_normal_load
→ ods_ingestion_gate
→ ods_content_check
→ dwd_create_table
→ dwd_load_clean_data
→ dwd_quality_gate
```

DWS/ADS 后增加：

```text
result_quality_gate
```

再继续：

```text
dim_user
dim_product
dim_date
dim_geo
→ fact_order
→ dws_customer_value_star
→ star_quality_gate
→ final_report
```

每增加一组节点，应分别验证：

- 正常成功路径；
- SQL 执行失败；
- BLOCK 质量失败；
- SSH 或环境失败；
- 同一 `bizdate` 重跑；
- 历史日期回刷边界。

---

## 10. 总结

当前文件记录的是已经验收过的 12 节点 DolphinScheduler 演示 DAG。它能够展示：

- SSH 远程执行 Hive；
- DWD 质量阻断；
- DWS 和 ADS 并行；
- 任务依赖和实例状态；
- 参数化业务日期。

同时必须注意：

> 当前最新正常 ODS 加载 SQL已经依赖 ODS Raw，而本 DAG 尚未包含 Raw、Reject 和入仓门禁节点。使用最新代码时，应先升级 DAG，不能直接把旧调度定义与新 SQL 混用。