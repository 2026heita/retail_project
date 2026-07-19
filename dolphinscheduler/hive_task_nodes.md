# Hive DolphinScheduler 任务节点配置

## 1. 当前结论

DolphinScheduler 容器内不直接执行 Hive 命令，Shell 节点通过 SSH 调用部署 Hadoop / Hive 的 Linux 主机执行 Hive SQL。

当前工作流共 12 个节点，完整主链路为：

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

其中 `dwd_quality_gate` 位于 DWD 与 DWS 之间，质量检查失败时返回非零状态并阻断后续节点。

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
HIVE_USER=<SSH 用户>
HIVE_HOST=<Hive 主机>
PROJECT_HOME=<服务器项目根目录>
```

公开仓库不保留真实服务器账号、真实 IP、明文密码和 SSH 私钥。

## 3. 通用 Shell 模板

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

## 4. 任务节点明细

### 1. ods_create_retail

任务类型：Shell

节点作用：创建/准备 ODS 分区表。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/00_ods_retail_hive.sql
"
```

上游任务：无

下游任务：`ods_load_retail`

### 2. ods_load_retail

任务类型：Shell

节点作用：将 `retail` 源表数据写入 `ods_retail_hive` 指定业务日期分区。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/00_load_ods_retail_hive.sql
"
```

上游任务：`ods_create_retail`

下游任务：`dwd_create_table`

### 3. dwd_create_table

任务类型：Shell

节点作用：创建 DWD 清洗明细表。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/01_dwd_retail_clean_hive.sql
"
```

上游任务：`ods_load_retail`

下游任务：`dwd_load_clean_data`

### 4. dwd_load_clean_data

任务类型：Shell

节点作用：从 ODS 分区加载并清洗 DWD 明细数据。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/02_load_dwd_retail_clean_hive.sql
"
```

上游任务：`dwd_create_table`

下游任务：`dwd_quality_gate`

### 5. dwd_quality_gate

任务类型：Shell

节点作用：执行 DWD 数据质量门禁。存在失败项或无法读取质量结果时返回非零状态，阻断两个 DWS 节点。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
bash ${PROJECT_HOME}/hive/run_quality_gate_hive.sh ${bizdate}
"
```

脚本内部依次调用：

```text
23_quality_log_hive.sql
24_load_quality_log_hive.sql
```

成功输出：

```text
Data quality gate passed.
failed_count=0
```

上游任务：`dwd_load_clean_data`

下游任务：`dws_customer_value`、`dws_sales_summary`

### 6. dws_customer_value

任务类型：Shell

节点作用：生成客户价值汇总。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/03_dws_customer_value_hive.sql
"
```

上游任务：`dwd_quality_gate`

下游任务：

- `ads_high_value_customer_sales_contribution`
- `ads_customer_level_distribution`
- `ads_high_value_customer_preference`

### 7. dws_sales_summary

任务类型：Shell

节点作用：生成国家销售汇总。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/04_dws_sales_summary_hive.sql
"
```

上游任务：`dwd_quality_gate`

下游任务：`ads_country_sales_rank`

### 8. ads_high_value_customer_sales_contribution

任务类型：Shell

节点作用：高价值客户销售贡献分析。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/05_ads_high_value_customer_sales_contribution_hive.sql
"
```

上游任务：`dws_customer_value`

下游任务：`hive_data_quality_check`

### 9. ads_customer_level_distribution

任务类型：Shell

节点作用：客户等级分布分析。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/06_ads_customer_level_distribution_hive.sql
"
```

上游任务：`dws_customer_value`

下游任务：`hive_data_quality_check`

### 10. ads_country_sales_rank

任务类型：Shell

节点作用：国家销售排行分析。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/07_ads_country_sales_rank_hive.sql
"
```

上游任务：`dws_sales_summary`

下游任务：`hive_data_quality_check`

### 11. ads_high_value_customer_preference

任务类型：Shell

节点作用：高价值客户商品偏好分析。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/08_ads_high_value_customer_preference_hive.sql
"
```

上游任务：`dws_customer_value`

下游任务：`hive_data_quality_check`

### 12. hive_data_quality_check

任务类型：Shell

节点作用：对 ADS 结果数据进行最终质量检查。

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null || true
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/09_check_hive_result.sql
"
```

上游任务：四个 ADS 节点

下游任务：无

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

## 6. 运行前检查

```bash
hdfs dfs -ls /
hive -e "show databases;"
ssh -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} hostname
```

常见问题：

- `ssh: command not found`：DolphinScheduler 镜像缺少 `openssh-client`；
- `Permission denied`：SSH 免密配置未生效；
- `hadoop100:8020 Connection refused`：HDFS NameNode 未启动；
- `pipefail: invalid option name`：Shell 文件使用了 Windows CRLF，应转换为 LF；
- `No such file or directory`：检查服务器实际目录是否为 `${PROJECT_HOME}/hive/`。