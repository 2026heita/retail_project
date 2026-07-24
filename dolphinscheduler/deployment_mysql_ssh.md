# DolphinScheduler 3.2.2：MySQL 持久化与 SSH 执行说明

> 文件属性：长期保留，提交代码仓库
> 对应文件：`dolphinscheduler/deployment_mysql_ssh.md`
> 本文只保留可公开的部署模板。真实数据库密码、服务器地址、SSH 私钥和含凭据配置不得提交仓库。

---

## 1. 部署目标

本项目使用 DolphinScheduler 3.2.2 Standalone 进行 Hive 工作流调度。

部署主要解决三个问题：

1. 使用 H2 内存数据库时，容器重启后项目、工作流和运行记录可能丢失；
2. 默认 Standalone 镜像可能缺少 MySQL JDBC 驱动；
3. 默认镜像可能缺少 `ssh` 命令，无法远程执行 Hadoop/Hive 主机上的脚本。

最终架构：

```text
浏览器
  ↓
DolphinScheduler 3.2.2 Standalone 容器
  ├── API / Master / Worker
  ├── MySQL Connector/J
  └── OpenSSH Client
          │
          │ SSH
          ▼
Hadoop / HDFS / Hive 主机
  └── 零售 Hive 项目文件

DolphinScheduler 元数据
  ↓
MySQL dolphinscheduler 数据库
```

DolphinScheduler 负责：

- 工作流定义；
- 任务依赖；
- 参数传递；
- 实例状态；
- 调度记录；
- 运行日志。

Hadoop/Hive 主机负责：

- HDFS；
- Hive；
- Hive SQL；
- Shell 主脚本；
- 实际离线计算。

---

## 2. 为什么使用 MySQL 元数据库

Standalone 临时环境可能使用：

```text
jdbc:h2:mem:dolphinscheduler
```

H2 内存模式适合快速体验，不适合作为长期项目环境。进程或容器重启后，内存中的元数据可能丢失。

本项目改用独立 MySQL 数据库，持久化：

- 项目；
- 工作流定义；
- 任务定义；
- 任务依赖；
- 工作流实例；
- 任务实例；
- 调度配置；
- 运行记录。

---

## 3. 创建 MySQL 元数据库

以下命令仅为模板，请替换密码，不要把真实密码写入仓库。

```sql
CREATE DATABASE IF NOT EXISTS dolphinscheduler
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_general_ci;

CREATE USER IF NOT EXISTS 'dolphinscheduler'@'%'
IDENTIFIED BY '<STRONG_PASSWORD>';

GRANT ALL PRIVILEGES ON dolphinscheduler.*
TO 'dolphinscheduler'@'%';

FLUSH PRIVILEGES;
```

验证账号：

```bash
mysql \
  -h <MYSQL_HOST> \
  -P 3306 \
  -u dolphinscheduler \
  -p \
  -e "SELECT VERSION(); SHOW DATABASES LIKE 'dolphinscheduler';"
```

生产或长期环境应限制数据库账号来源地址，不建议始终使用 `%`。

---

## 4. 初始化 DolphinScheduler 表结构

可使用官方 tools 镜像：

```text
apache/dolphinscheduler-tools:3.2.2
```

准备与环境兼容的 MySQL Connector/J，例如：

```text
mysql-connector-j-8.0.33.jar
```

不要把空宿主机目录直接挂载到：

```text
/opt/dolphinscheduler/tools/libs
```

否则可能覆盖镜像原有依赖。

可以先创建临时容器：

```bash
docker run -d \
  --name ds-tools-tmp \
  --entrypoint bash \
  apache/dolphinscheduler-tools:3.2.2 \
  -c "sleep infinity"
```

复制 JDBC 驱动：

```bash
docker cp \
  mysql-connector-j-8.0.33.jar \
  ds-tools-tmp:/opt/dolphinscheduler/tools/libs/
```

进入容器：

```bash
docker exec -it ds-tools-tmp bash
```

配置 MySQL 数据源后执行：

```bash
export DATABASE=mysql
bash /opt/dolphinscheduler/tools/bin/upgrade-schema.sh
```

初始化成功后检查核心表：

```sql
SHOW TABLES LIKE 't_ds_process_definition';
SHOW TABLES LIKE 't_ds_task_definition';
SHOW TABLES LIKE 't_ds_process_task_relation';
SHOW TABLES LIKE 't_ds_process_instance';
SHOW TABLES LIKE 't_ds_task_instance';
```

临时容器使用完成后可删除：

```bash
docker rm -f ds-tools-tmp
```

---

## 5. 构建自定义 Standalone 镜像

默认镜像可能缺少 MySQL JDBC 驱动和 OpenSSH Client。

Dockerfile 示例：

```dockerfile
FROM apache/dolphinscheduler-standalone-server:3.2.2

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY mysql-connector-j-8.0.33.jar \
    /opt/dolphinscheduler/libs/standalone-server/mysql-connector-j-8.0.33.jar
```

构建：

```bash
docker build \
  -t retail-dolphinscheduler-standalone:3.2.2-mysql-ssh .
```

验证 SSH：

```bash
docker run --rm \
  --entrypoint bash \
  retail-dolphinscheduler-standalone:3.2.2-mysql-ssh \
  -lc 'which ssh && ssh -V'
```

验证 JDBC 驱动：

```bash
docker run --rm \
  --entrypoint bash \
  retail-dolphinscheduler-standalone:3.2.2-mysql-ssh \
  -lc 'find /opt/dolphinscheduler -name "mysql-connector-j*.jar"'
```

---

## 6. 配置 MySQL 数据源

`application.yaml` 中启用 MySQL profile：

```yaml
spring:
  profiles:
    active: mysql
```

MySQL 数据源模板：

```yaml
spring:
  config:
    activate:
      on-profile: mysql

  datasource:
    driver-class-name: com.mysql.cj.jdbc.Driver
    url: >-
      jdbc:mysql://<MYSQL_HOST>:3306/dolphinscheduler
      ?useUnicode=true
      &characterEncoding=UTF-8
      &useSSL=false
      &allowPublicKeyRetrieval=true
      &serverTimezone=Asia/Shanghai
    username: dolphinscheduler
    password: "<STRONG_PASSWORD>"
```

实际使用时应把 JDBC URL 写成连续一行，避免 YAML 折叠后意外加入空格。

示例：

```yaml
spring:
  datasource:
    driver-class-name: com.mysql.cj.jdbc.Driver
    url: jdbc:mysql://<MYSQL_HOST>:3306/dolphinscheduler?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai
    username: dolphinscheduler
    password: "<STRONG_PASSWORD>"
```

安全要求：

- 含真实密码的 `application.yaml` 不提交仓库；
- 文件权限仅开放给部署用户；
- 生产环境优先使用环境变量或密钥管理系统；
- `serverTimezone` 应与实际部署时区一致。

---

## 7. 启动 Standalone 容器

示例：

```bash
docker run -d \
  --name dolphinscheduler-standalone \
  --restart unless-stopped \
  -p 12345:12345 \
  -e TZ=Asia/Shanghai \
  -v /path/to/application.yaml:/opt/dolphinscheduler/conf/application.yaml:ro \
  -v /path/to/ssh-directory:/root/.ssh:ro \
  retail-dolphinscheduler-standalone:3.2.2-mysql-ssh
```

说明：

- `application.yaml` 使用只读挂载；
- SSH 目录使用只读挂载；
- 私钥不得放入代码仓库；
- 私钥权限应满足 SSH 要求；
- 宿主机路径需要替换成真实部署路径。

当前调度任务通过 SSH 使用远程项目文件，因此不要求把零售 Hive 项目挂载到容器内。

---

## 8. 配置 SSH 密钥认证

在部署主机准备专用 SSH 密钥。不要把私钥提交仓库。

验证私钥权限：

```bash
chmod 700 /path/to/ssh-directory
chmod 600 /path/to/ssh-directory/id_rsa
chmod 644 /path/to/ssh-directory/id_rsa.pub
```

在 Hive 主机上，将公钥加入目标用户：

```text
~/.ssh/authorized_keys
```

容器启动后验证：

```bash
docker exec dolphinscheduler-standalone bash -lc \
  'ssh -o BatchMode=yes <HIVE_USER>@<HIVE_HOST> hostname'
```

进一步验证 Hive：

```bash
docker exec dolphinscheduler-standalone bash -lc \
  'ssh -o BatchMode=yes <HIVE_USER>@<HIVE_HOST> "hive -e '\''SHOW DATABASES;'\''"'
```

`BatchMode=yes` 的作用是：

- 禁止交互式密码提示；
- 密钥认证失败时立即返回错误；
- 防止调度任务长时间等待人工输入。

---

## 9. DolphinScheduler Shell 节点

当前公开模板使用以下全局参数：

```text
bizdate=$[yyyy-MM-dd-1]
HIVE_USER=your_hive_user
HIVE_HOST=your_hive_host
PROJECT_HOME=/home/your_user/retail_hive_project
```

普通 Hive SQL 节点：

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

质量门禁节点：

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

远程命令返回非零状态时，DolphinScheduler 节点应失败。

---

## 10. 启动后检查

检查容器：

```bash
docker ps --filter name=dolphinscheduler-standalone
```

检查 SSH：

```bash
docker exec dolphinscheduler-standalone bash -lc \
  'which ssh && ssh -V'
```

检查 JDBC 驱动：

```bash
docker exec dolphinscheduler-standalone bash -lc \
  'find /opt/dolphinscheduler -name "mysql-connector-j*.jar"'
```

检查启动日志：

```bash
docker logs dolphinscheduler-standalone 2>&1 | tail -100
```

检查元数据库是否为 MySQL：

```bash
docker logs dolphinscheduler-standalone 2>&1 \
  | grep -Ei 'jdbc:mysql|datasource|mysql'
```

在 Hadoop/Hive 主机检查：

```bash
jps
ss -lntp | grep 8020
hdfs dfs -ls /
hive -e "SHOW DATABASES;"
```

---

## 11. 负载保护

资源较小的实验环境中，DolphinScheduler 可能因 CPU 或内存采样触发 Master/Worker 负载保护，表现为：

```text
Master node is BUSY
Current master is not in active master list
```

先检查真实资源：

```bash
free -h
docker stats --no-stream
df -h
```

测试环境中可以根据实际情况调整阈值，例如：

```yaml
max-system-cpu-usage-percentage-thresholds: 1.0
max-system-memory-usage-percentage-thresholds: 1.0
```

注意：

- 该配置接近关闭保护；
- 只适用于资源受限的实验环境；
- 生产环境应优先增加资源并设置合理阈值；
- 不应把调高阈值作为所有 BUSY 问题的默认解决方法。

---

## 12. 导入工作流 JSON

当前导入文件：

```text
dolphinscheduler/retail_hive_offline_warehouse_daily_demo.json
```

导入前验证 JSON 语法：

```powershell
python -c "import json,pathlib; p=pathlib.Path(r'.\dolphinscheduler\retail_hive_offline_warehouse_daily_demo.json'); json.loads(p.read_text(encoding='utf-8-sig')); print('JSON format OK')"
```

导入文件必须包含：

```text
processDefinition
taskDefinitionList
processTaskRelationList
schedule
```

其中：

- `processTaskRelationList` 必须存在且非空；
- 任务关系中的编码必须能匹配任务定义；
- 当前 `schedule` 为 `null`；
- 导入后不会自动启用定时计划；
- 应先修改环境参数并手动运行。

当前 JSON 是 12 节点演示 DAG。最新完整 Hive 链路是 20 步 Shell 主流程，两者范围不同。

---

## 13. 当前版本兼容性提醒

当前仓库中的：

```text
00_load_ods_retail_hive.sql
```

已经改为从：

```text
ods_retail_raw_hive
```

读取。

但当前 12 节点 DolphinScheduler DAG 没有 ODS Raw、ODS Reject 和 ODS 入仓门禁节点。

因此：

> 旧 12 节点 DAG 不能在未升级前置节点的情况下直接配合全部最新 Hive SQL 使用。

当前最完整执行入口：

```bash
bash ${PROJECT_HOME}/hive/run_all_hive.sh ${bizdate}
```

DAG 升级建议详见：

```text
dolphinscheduler/workflow_design.md
dolphinscheduler/hive_task_nodes.md
```

---

## 14. 常见问题

### 14.1 `ssh: command not found`

原因：

```text
Standalone 镜像中没有 OpenSSH Client。
```

处理：

```text
使用自定义镜像安装 openssh-client。
```

### 14.2 `Permission denied (publickey)`

检查：

- 私钥是否挂载；
- 私钥权限；
- 公钥是否加入远程 `authorized_keys`；
- 登录用户是否正确；
- 容器实际用户是否能读取私钥。

### 14.3 `Connection refused ... :8020`

可能原因：

- HDFS NameNode 未启动；
- 8020 端口未监听；
- Hadoop 配置地址错误；
- 容器或远程主机网络不通。

检查：

```bash
jps
ss -lntp | grep 8020
hdfs dfs -ls /
```

### 14.4 工作流重启后消失

可能原因：

```text
实际仍在使用 H2 内存数据库。
```

检查日志中生效的 JDBC URL 是否为：

```text
jdbc:mysql://.../dolphinscheduler
```

### 14.5 `数据[ProcessTaskRelationList]不能为空`

原因：

- 导入文件缺少任务关系；
- JSON 不是目标版本可识别的结构；
- 任务关系编码无效。

处理：

- 保留 `processTaskRelationList`；
- 不随意删除任务编码；
- 使用经过验证的原生导出 JSON；
- 导入前先做标准 JSON 语法检查。

### 14.6 `Table not found: ods_retail_raw_hive`

原因：

```text
旧 DAG 使用了最新正常 ODS 加载 SQL，但没有先创建和加载 ODS Raw。
```

处理：

- 升级 DAG，补充 Raw、Reject 和入仓门禁；
- 或由单个 Shell 节点调用完整 `run_all_hive.sh`。

### 14.7 `pipefail: invalid option name`

常见原因：

```text
Shell 文件使用 Windows CRLF 换行。
```

处理：

```bash
sed -i 's/\r$//' 文件名.sh
bash -n 文件名.sh
```

---

## 15. 安全要求

禁止提交：

- 数据库真实密码；
- 真实服务器 IP、主机名和账号；
- SSH 私钥；
- 含凭据的 `application.yaml`；
- MySQL 登录配置；
- 未脱敏日志；
- 未脱敏截图；
- 容器内导出的密钥或配置备份。

建议：

- 配置文件使用只读挂载；
- SSH 使用专用低权限账号；
- 数据库账号只授予所需数据库权限；
- 定期轮换密码和密钥；
- 公开 JSON 只保留占位参数；
- 提交前使用 `git status` 和全文搜索检查敏感信息。

---

## 16. 验收清单

部署完成后至少验证：

```text
1. 容器正常运行。
2. Web 页面可以访问。
3. 元数据库实际连接 MySQL。
4. 容器中存在 MySQL Connector/J。
5. 容器中存在 ssh 命令。
6. SSH 密钥认证成功。
7. 远程 Hive 命令可以执行。
8. 工作流 JSON 可以导入。
9. 任务关系显示正常。
10. 固定 bizdate 手动运行成功。
11. 容器重启后项目、工作流和实例仍存在。
12. 真实凭据没有进入 Git 仓库。
```

---

## 17. 总结

当前部署方案实现了：

```text
H2 临时元数据
→ MySQL 持久化元数据

默认 Standalone 镜像
→ 加入 MySQL Connector/J 和 OpenSSH Client

容器内直接运行 Hive
→ Shell 节点通过 SSH 调用 Hadoop/Hive 主机

硬编码环境信息
→ DolphinScheduler 全局参数和公开占位值
```

该部署已经能够支持 12 节点演示 DAG 的持久化和远程执行。最新 20 步 Hive 主链路尚未全部拆分到 DolphinScheduler 节点中，使用最新 SQL 前需要先处理 ODS Raw 等前置依赖。