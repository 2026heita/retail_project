# Hive DolphinScheduler 任务节点配置

## 1. 当前结论

本文件为 GitHub 安全版。DolphinScheduler 容器内不直接执行 Hive 命令，Shell 节点通过 SSH 调用部署 Hive 的 Linux 主机执行 Hive SQL。公开仓库中不保留真实服务器账号、真实 IP 或明文密码。

## 2. 全局参数

```text
bizdate = $[yyyy-MM-dd-1]
```

## 3. 通用 Shell 模板

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/SQL文件名
"
```

### 1. ods_create_retail

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/00_ods_retail_hive.sql
"
```

上游任务：无

下游任务：dwd_create_table

### 2. dwd_create_table

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/01_dwd_retail_clean_hive.sql
"
```

上游任务：ods_create_retail

下游任务：dwd_load_clean_data

### 3. dwd_load_clean_data

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/02_load_dwd_retail_clean_hive.sql
"
```

上游任务：dwd_create_table

下游任务：dws_customer_value、dws_sales_summary

### 4. dws_customer_value

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/03_dws_customer_value_hive.sql
"
```

上游任务：dwd_load_clean_data

下游任务：ads_customer_level_distribution、ads_high_value_customer_sales_contribution、ads_high_value_customer_preference

### 5. dws_sales_summary

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/04_dws_sales_summary_hive.sql
"
```

上游任务：dwd_load_clean_data

下游任务：ads_country_sales_rank

### 6. ads_high_value_customer_sales_contribution

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/05_ads_high_value_customer_sales_contribution_hive.sql
"
```

上游任务：dws_customer_value

下游任务：hive_data_quality_check

### 7. ads_customer_level_distribution

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/06_ads_customer_level_distribution_hive.sql
"
```

上游任务：dws_customer_value

下游任务：hive_data_quality_check

### 8. ads_country_sales_rank

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/07_ads_country_sales_rank_hive.sql
"
```

上游任务：dws_sales_summary

下游任务：hive_data_quality_check

### 9. ads_high_value_customer_preference

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/08_ads_high_value_customer_preference_hive.sql
"
```

上游任务：dws_customer_value

下游任务：hive_data_quality_check

### 10. hive_data_quality_check

任务类型：Shell

执行命令：

```bash
ssh -o StrictHostKeyChecking=no ${HIVE_USER}@${HIVE_HOST} "
source /etc/profile
source ~/.bash_profile 2>/dev/null
hive --hiveconf bizdate=${bizdate} -f ${PROJECT_HOME}/hive/09_check_hive_result.sql
"
```

上游任务：ADS 结果任务

下游任务：无

## 4. DAG 依赖关系

```text
ods_create_retail
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
ads_country_sales_rank
ads_high_value_customer_preference
  -> hive_data_quality_check
```
