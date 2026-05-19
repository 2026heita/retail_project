# Hive DolphinScheduler 任务节点配置

## 1. 当前结论

本文件为公开仓库示例版。DolphinScheduler 容器内不直接执行 Hive 命令，Shell 节点通过 SSH 调用部署 Hive 的 Linux 主机执行 Hive SQL。公开仓库中不保留真实服务器账号、真实 IP 或明文密码。

当前调度链路已包含 ODS 加载节点，并形成完整主链路：ods_create_retail -> ods_load_retail -> dwd_create_table -> dwd_load_clean_data -> DWS -> ADS -> hive_data_quality_check。其中 `ods_create_retail` 只负责创建/准备 ODS 表，`ods_load_retail` 负责将 `retail` 源表数据写入 `ods_retail_hive` 正式 ODS 分区表。

## 2. 全局参数

```text
bizdate = $[yyyy-MM-dd-1]
```

## 3. 通用 Shell 模板

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/SQL文件名
"
```

### 1. ods_create_retail

任务类型：Shell

节点作用：创建/准备 ODS 分区表

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/00_ods_retail_hive.sql
"
```

上游任务：无

下游任务：ods_load_retail

### 2. ods_load_retail

任务类型：Shell

节点作用：将 retail 源表数据写入 ods_retail_hive 正式 ODS 分区表

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/00_load_ods_retail_hive.sql
"
```

上游任务：ods_create_retail

下游任务：dwd_create_table

### 3. dwd_create_table

任务类型：Shell

节点作用：创建 DWD 清洗明细表

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/01_dwd_retail_clean_hive.sql
"
```

上游任务：ods_load_retail

下游任务：dwd_load_clean_data

### 4. dwd_load_clean_data

任务类型：Shell

节点作用：从 ODS 分区加载并清洗 DWD 明细数据

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/02_load_dwd_retail_clean_hive.sql
"
```

上游任务：dwd_create_table

下游任务：dws_customer_value、dws_sales_summary

### 5. dws_customer_value

任务类型：Shell

节点作用：生成客户价值汇总

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/03_dws_customer_value_hive.sql
"
```

上游任务：dwd_load_clean_data

下游任务：ads_customer_level_distribution、ads_high_value_customer_sales_contribution、ads_high_value_customer_preference

### 6. dws_sales_summary

任务类型：Shell

节点作用：生成国家销售汇总

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/04_dws_sales_summary_hive.sql
"
```

上游任务：dwd_load_clean_data

下游任务：ads_country_sales_rank

### 7. ads_high_value_customer_sales_contribution

任务类型：Shell

节点作用：高价值客户销售贡献分析

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/05_ads_high_value_customer_sales_contribution_hive.sql
"
```

上游任务：dws_customer_value

下游任务：hive_data_quality_check

### 8. ads_customer_level_distribution

任务类型：Shell

节点作用：客户等级分布分析

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/06_ads_customer_level_distribution_hive.sql
"
```

上游任务：dws_customer_value

下游任务：hive_data_quality_check

### 9. ads_country_sales_rank

任务类型：Shell

节点作用：国家销售排行分析

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/07_ads_country_sales_rank_hive.sql
"
```

上游任务：dws_sales_summary

下游任务：hive_data_quality_check

### 10. ads_high_value_customer_preference

任务类型：Shell

节点作用：高价值客户商品偏好分析

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/08_ads_high_value_customer_preference_hive.sql
"
```

上游任务：dws_customer_value

下游任务：hive_data_quality_check

### 11. hive_data_quality_check

任务类型：Shell

节点作用：ADS 结果数据质量校验

执行命令：

```bash
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive_sql/09_check_hive_result.sql
"
```

上游任务：ADS 结果任务

下游任务：无

## 4. DAG 依赖关系

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
