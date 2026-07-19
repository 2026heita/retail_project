\# DolphinScheduler 3.2.2：MySQL 持久化与 SSH 执行说明



本文档记录本项目中 DolphinScheduler Standalone 的工程化部署方式。目标是解决 H2 内存库重启后元数据丢失、默认镜像缺少 MySQL JDBC 驱动和 SSH 客户端等问题，使工作流定义、任务关系和运行实例能够持久保存，并由 Shell 节点远程执行 Hadoop/Hive 主机上的 SQL。



> 本文仅保留可公开的配置模板。数据库密码、真实服务器地址和 SSH 私钥不得提交到 Git 仓库。



\## 1. 部署结构



```text

浏览器

&#x20; ↓

DolphinScheduler 3.2.2 Standalone 容器

&#x20; ├── API / Master / Worker

&#x20; ├── MySQL Connector/J

&#x20; └── OpenSSH Client

&#x20;       ↓ SSH

Hadoop / Hive 主机

&#x20;       ↓

HDFS + Hive



DolphinScheduler 元数据

&#x20;       ↓

MySQL dolphinscheduler 数据库

```



\## 2. 为什么不用 H2 内存库



Standalone 默认配置可能使用：



```text

jdbc:h2:mem:dolphinscheduler

```



该模式适合临时体验，不适合作为项目展示或长期调度环境。进程或容器重启后，内存数据库中的项目、工作流、任务依赖和运行实例可能丢失。



本项目改用独立 MySQL 元数据库，持久化：



\- 项目和工作流定义；

\- `processTaskRelationList` 任务依赖；

\- 工作流实例与任务实例；

\- 调度配置和运行记录。



\## 3. 创建 MySQL 元数据库



下面仅为模板，请自行替换强密码：



```sql

CREATE DATABASE IF NOT EXISTS dolphinscheduler

DEFAULT CHARACTER SET utf8mb4

DEFAULT COLLATE utf8mb4\_general\_ci;



CREATE USER IF NOT EXISTS 'dolphinscheduler'@'%'

IDENTIFIED BY '<STRONG\_PASSWORD>';



GRANT ALL PRIVILEGES ON dolphinscheduler.\*

TO 'dolphinscheduler'@'%';



FLUSH PRIVILEGES;

```



验证账号可连接：



```bash

mysql -h <MYSQL\_HOST> -P 3306 -u dolphinscheduler -p \\

&#x20; -e "SELECT VERSION(); SHOW DATABASES LIKE 'dolphinscheduler';"

```



\## 4. 初始化 DolphinScheduler 表结构



DolphinScheduler 3.2.2 的 Standalone 镜像不一定包含数据库升级工具，建议使用官方 tools 镜像：



```text

apache/dolphinscheduler-tools:3.2.2

```



MySQL Connector/J 需要额外准备，例如：



```text

mysql-connector-j-8.0.33.jar

```



注意：不要把宿主机目录直接挂载到 `/opt/dolphinscheduler/tools/libs`，否则会覆盖 tools 镜像原有依赖。可创建临时容器后，将 JDBC 驱动复制进已有目录：



```bash

docker run -d \\

&#x20; --name ds-tools-tmp \\

&#x20; --entrypoint bash \\

&#x20; apache/dolphinscheduler-tools:3.2.2 \\

&#x20; -c "sleep infinity"



docker cp mysql-connector-j-8.0.33.jar \\

&#x20; ds-tools-tmp:/opt/dolphinscheduler/tools/libs/

```



然后在临时容器内配置 MySQL 连接，并执行：



```bash

export DATABASE=mysql

bash /opt/dolphinscheduler/tools/bin/upgrade-schema.sh

```



成功后应看到数据库初始化完成信息，并可检查核心表：



```sql

SHOW TABLES LIKE 't\_ds\_process\_definition';

SHOW TABLES LIKE 't\_ds\_task\_definition';

SHOW TABLES LIKE 't\_ds\_process\_task\_relation';

```



\## 5. 自定义 Standalone 镜像



默认 Standalone 镜像可能缺少 MySQL JDBC 驱动和 `ssh` 命令。本项目使用以下 Dockerfile：



```dockerfile

FROM apache/dolphinscheduler-standalone-server:3.2.2



USER root



RUN apt-get update \\

&#x20;   \&\& apt-get install -y --no-install-recommends openssh-client \\

&#x20;   \&\& rm -rf /var/lib/apt/lists/\*



COPY mysql-connector-j-8.0.33.jar \\

&#x20;    /opt/dolphinscheduler/libs/standalone-server/mysql-connector-j-8.0.33.jar

```



构建示例：



```bash

docker build \\

&#x20; -t retail-dolphinscheduler-standalone:3.2.2-mysql-ssh .

```



验证镜像内 SSH：



```bash

docker run --rm \\

&#x20; --entrypoint bash \\

&#x20; retail-dolphinscheduler-standalone:3.2.2-mysql-ssh \\

&#x20; -lc 'which ssh \&\& ssh -V'

```



\## 6. application.yaml 配置要点



启用 MySQL profile：



```yaml

spring:

&#x20; profiles:

&#x20;   active: mysql

```



MySQL 数据源示例：



```yaml

spring:

&#x20; config:

&#x20;   activate:

&#x20;     on-profile: mysql

&#x20; datasource:

&#x20;   driver-class-name: com.mysql.cj.jdbc.Driver

&#x20;   url: jdbc:mysql://<MYSQL\_HOST>:3306/dolphinscheduler?useUnicode=true\&characterEncoding=UTF-8\&useSSL=false\&allowPublicKeyRetrieval=true\&serverTimezone=Asia/Shanghai

&#x20;   username: dolphinscheduler

&#x20;   password: "<STRONG\_PASSWORD>"

```



实际 `application.yaml` 应通过部署主机挂载，不应提交含密码的版本。



\## 7. 启动容器



示例：



```bash

docker run -d \\

&#x20; --name dolphinscheduler-standalone \\

&#x20; --restart unless-stopped \\

&#x20; -p 12345:12345 \\

&#x20; -e TZ=Asia/Shanghai \\

&#x20; -v /path/to/application.yaml:/opt/dolphinscheduler/conf/application.yaml:ro \\

&#x20; -v /path/to/ssh-directory:/root/.ssh \\

&#x20; -v /path/to/retail\_hive\_project:/opt/retail\_hive\_project \\

&#x20; retail-dolphinscheduler-standalone:3.2.2-mysql-ssh

```



公开仓库中只保留命令模板，不保存真实 SSH 私钥。



\## 8. SSH 执行方式



普通 Hive 节点通过 SSH 调用远程主机：



```bash

ssh -o StrictHostKeyChecking=accept-new \\

&#x20;   -o BatchMode=yes \\

&#x20;   ${HIVE\_USER}@${HIVE\_HOST} "

source /etc/profile

source \~/.bash\_profile 2>/dev/null || true

hive --hiveconf bizdate=${bizdate} \\

&#x20; -f ${PROJECT\_HOME}/hive/SQL文件名

"

```



质量门禁节点执行：



```bash

bash ${PROJECT\_HOME}/hive/run\_quality\_gate\_hive.sh ${bizdate}

```



\## 9. 负载保护配置



资源较小的实验环境中，容器可能因宿主机 CPU 或内存瞬时采样触发 Master/Worker 负载保护，表现为：



```text

Master node is BUSY

Current master is not in active master list

```



应先通过 `free -h`、`docker stats --no-stream` 判断真实资源使用情况，再谨慎调整以下参数：



```yaml

max-system-cpu-usage-percentage-thresholds: 1.0

max-system-memory-usage-percentage-thresholds: 1.0

```



生产环境不建议直接关闭保护，应增加资源并设置合理阈值。



\## 10. 启动后检查



```bash

docker ps --filter name=dolphinscheduler-standalone



docker exec dolphinscheduler-standalone bash -lc \\

&#x20; 'which ssh \&\& ssh -V'



docker logs dolphinscheduler-standalone 2>\&1 | tail -100

```



验证 SSH 免密：



```bash

docker exec dolphinscheduler-standalone bash -lc \\

&#x20; 'ssh -o BatchMode=yes <HIVE\_USER>@<HIVE\_HOST> hostname'

```



调度前确认 Hadoop/HDFS/Hive 可用：



```bash

jps

ss -lntp | grep 8020

hdfs dfs -ls /

hive -e "show databases;"

```



\## 11. 常见问题



\### 11.1 `ssh: command not found`



原因：默认镜像没有 OpenSSH Client。



处理：在自定义镜像中安装 `openssh-client`。



\### 11.2 `Connection refused ... :8020`



原因：HDFS NameNode 未启动或 8020 端口未监听。



处理：检查 `jps`、`start-dfs.sh` 和 `ss -lntp | grep 8020`。



\### 11.3 工作流重启后消失



原因：仍在使用 H2 内存库。



处理：检查实际生效配置是否为 `jdbc:mysql://.../dolphinscheduler`。



\### 11.4 `数据\[ProcessTaskRelationList]不能为空`



原因：导入文件不是 DolphinScheduler 3.2.2 原生结构，或缺少非空任务关系。



处理：导入 JSON 必须包含：



```text

processDefinition

taskDefinitionList

processTaskRelationList

schedule

```



并保证所有 `preTaskCode`、`postTaskCode` 与任务定义中的数值编码一致。



\## 12. 安全要求



禁止提交：



\- 数据库真实密码；

\- 真实服务器 IP；

\- SSH 私钥；

\- 含凭据的 `application.yaml`；

\- 未脱敏的日志和截图。

