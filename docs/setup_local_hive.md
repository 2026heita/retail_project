# 本地 Hive 运行指南

> 文件属性：长期保留，提交代码仓库
> 对应文件：`docs/setup_local_hive.md`

本文说明如何使用仓库中的最小样例数据，在独立 Hive 环境中复现当前零售离线数仓主链路。

---

## 1. 数据链路

```text
本地 CSV
  ↓
Hive 源表 retail
  ↓
ODS Raw
  ├── 日期异常 → ODS Reject
  └── 日期正常 → 正常 ODS
                    ↓
                   DWD
                    ↓
                DWS / ADS
                    ↓
               星型模型与质量门禁
```

需要说明：

- MySQL 的 `retail` 与 Hive 的 `retail` 是两个独立对象；
- Hive SQL 中的 `FROM retail` 读取 Hive Metastore 中登记的表；
- 将 CSV 导入 MySQL 后，Hive不会自动读取 MySQL 表；
- 当前最小复现方式是 `CSV → Hive retail → Hive 数仓链路`；
- 项目没有内置 MySQL 到 Hive 的自动同步任务。

---

## 2. 环境要求

建议环境：

- Linux 服务器或虚拟机；
- Hadoop/HDFS 可用；
- Hive 3.x；
- Bash；
- Java 和 Hive 环境变量配置正确。

检查 HDFS：

```bash
hdfs dfs -ls /
```

检查 Hive：

```bash
hive -e "SHOW DATABASES;"
```

两个命令均正常返回后，再运行项目。

---

## 3. 项目目录

以下命令使用公开占位路径：

```text
/home/your_user/retail_hive_project
```

请替换为实际目录。例如当前测试环境可使用：

```text
/home/admin/retail_hive_project
```

服务器目录示例：

```text
retail_hive_project/
├── hive/
├── sample_data/
├── docs/
└── logs/
```

仓库中的目录名是：

```text
hive_sql/
```

上传到服务器时可以改为：

```text
hive/
```

但脚本、文档和 DolphinScheduler 中引用的路径必须与服务器实际目录一致。

---

## 4. 上传文件

需要上传：

```text
hive_sql/           → 服务器的 hive/
sample_data/
docs/
```

Shell 文件从 Windows 上传后，建议检查换行和权限：

```bash
sed -i 's/\r$//' /home/your_user/retail_hive_project/hive/*.sh
chmod +x /home/your_user/retail_hive_project/hive/*.sh
```

检查语法：

```bash
bash -n /home/your_user/retail_hive_project/hive/run_all_hive.sh
bash -n /home/your_user/retail_hive_project/hive/run_daily_hive_profiled.sh
bash -n /home/your_user/retail_hive_project/hive/check_scd2_backfill_guard.sh
```

没有输出表示 Bash 语法检查通过。

---

## 5. 创建 Hive 样例源表

样例文件：

```text
sample_data/retail_sample.csv
```

当前样例共 35 条数据，主要业务日期为：

```text
2026-04-08
```

另外包含 1 条业务日期为 `2026-04-07` 的旧日期样例，用于验证按 `bizdate` 写入正常 ODS 分区。

样例中还包含：

- 正常订单；
- 取消且数量为负的订单；
- 数量为 0 的订单；
- 价格为 0 的订单；
- 空客户；
- 空国家；
- 空商品编码；
- 空商品描述。

当前样例没有日期为空或日期解析失败记录，因此预期 Reject 数量为 0。

### 5.1 使用限制

`00_bootstrap_sample_source_hive.sql` 会执行：

```sql
DROP TABLE IF EXISTS retail PURGE;
```

只应在以下场景执行：

- 新环境首次部署；
- 独立测试环境；
- 使用样例数据复现项目。

不要在保存正式源表的环境中直接执行。

### 5.2 执行

```bash
cd /home/your_user/retail_hive_project/hive

hive \
  --hiveconf source_file=/home/your_user/retail_hive_project/sample_data/retail_sample.csv \
  -f 00_bootstrap_sample_source_hive.sql
```

该脚本会：

1. 删除旧的 Hive `retail`；
2. 创建字段全部为 `STRING` 的源表；
3. 使用 OpenCSVSerde 解析带引号和逗号的 CSV；
4. 跳过 CSV 表头；
5. 使用本地 CSV 覆盖加载源表。

---

## 6. 验证源表

检查表：

```bash
hive -S -e "SHOW TABLES LIKE 'retail';"
```

检查字段：

```bash
hive -e "DESC retail;"
```

检查数据量：

```bash
hive -e "SELECT COUNT(*) FROM retail;"
```

使用仓库样例时，预期：

```text
35
```

查看数据：

```bash
hive -e "SELECT * FROM retail LIMIT 10;"
```

---

## 7. 首次执行完整链路

执行：

```bash
bash /home/your_user/retail_hive_project/hive/run_all_hive.sh 2026-04-08
```

当前主脚本共 20 步，包括：

```text
ODS Raw / Reject / 正常 ODS
→ ODS 入仓完整性门禁
→ ODS 内容检查
→ DWD 与 DWD 门禁
→ DWS / ADS 与结果门禁
→ 星型模型与星型门禁
→ 最终结果展示
```

脚本内部使用：

```bash
set -Eeuo pipefail
```

任何 SQL、Shell 子任务或 BLOCK 门禁失败时，主链路会停止并返回非零状态。

---

## 8. 样例数据预期结果

使用原始仓库样例和 `bizdate=2026-04-08` 时，基础预期为：

```text
Hive 源表 retail：35
ODS Raw：35
正常 ODS：34
ODS Reject：0
DWD：28
```

正常 ODS 比源表少 1 条，是因为样例中有 1 条订单日期为：

```text
2026-04-07
```

该记录日期可以正常解析，因此不会进入 Reject；但它不属于 `bizdate=2026-04-08`，所以不会写入 `2026-04-08` 的正常 ODS 分区。

DWD 从当前日期的 34 条正常 ODS 记录中再过滤 6 条：

```text
1 条取消且数量为负的订单
1 条数量为 0 的订单
1 条价格为 0 的订单
1 条客户为空的订单
1 条国家为空的订单
1 条商品编码为空的订单
```

样例中的空商品描述记录当前仍会进入 DWD，因为现有 DWD SQL 没有把 `description` 为空作为过滤条件。

取消订单同时也满足数量异常，但它仍然只是一条明细，因此不能把各异常分类数量直接相加后当成被过滤的唯一行数。

最终应以 SQL 实际结果和质量门禁状态为准。

---

## 9. ODS 数据入口

### 9.1 ODS Raw

```text
retail → ods_retail_raw_hive
```

特点：

- 不执行业务过滤；
- 不执行数值类型转换；
- 原始字段按 `STRING` 保存；
- 按处理批次 `batch_dt` 分区；
- 使用 `INSERT OVERWRITE` 支持同批次重跑。

### 9.2 ODS Reject

```text
ods_retail_raw_hive → ods_retail_reject_hive
```

当前只接收：

- `InvoiceDate` 为空；
- `InvoiceDate` 不符合当前支持的日期格式。

支持格式：

```text
yyyy-MM-dd HH:mm:ss
d/M/yyyy HH:mm:ss
```

数量、价格、客户和取消订单异常当前不进入 Reject，而是在正常 ODS 内容检查和 DWD 清洗阶段处理。

### 9.3 正常 ODS

```text
ods_retail_raw_hive → ods_retail_hive
```

正常 ODS：

- 从当前 `batch_dt` 的 Raw 分区读取；
- 解析订单日期；
- 只写入业务日期等于 `bizdate` 的记录；
- 按业务日期 `dt` 分区。

区别：

```text
batch_dt：ETL 处理批次
dt：订单业务日期
```

---

## 10. ODS 入仓完整性门禁

文件：

```text
10_check_ods_ingestion_hive.sql
```

单独执行：

```bash
hive \
  --hiveconf bizdate=2026-04-08 \
  -f /home/your_user/retail_hive_project/hive/10_check_ods_ingestion_hive.sql
```

检查：

```text
源表行数 = ODS Raw 行数
预期正常行数 = 正常 ODS 实际行数
预期异常行数 = Reject 实际行数
```

三个差值都应为 0。

`ASSERT_TRUE()` 条件成立时，Hive 可能显示：

```text
NULL
```

这是正常现象。条件不成立时，SQL 会失败并阻断下游。

---

## 11. ODS 内容检查

文件：

```text
10_check_ods_retail_hive.sql
```

执行：

```bash
hive \
  --hiveconf bizdate=2026-04-08 \
  -f /home/your_user/retail_hive_project/hive/10_check_ods_retail_hive.sql
```

用于查看：

- 正常 ODS 数量；
- 核心字段空值；
- 数量和价格异常；
- 取消或退货订单；
- Reject 数量和分类；
- 正常和异常样例。

它是内容检查和报告，不替代入仓断言。

---

## 12. 日常运行与局部重跑

首次完整运行并创建所有表后，可以使用日常脚本：

```bash
bash /home/your_user/retail_hive_project/hive/run_daily_hive_profiled.sh 2026-04-08
```

从 DWD 开始：

```bash
bash /home/your_user/retail_hive_project/hive/run_daily_hive_profiled.sh 2026-04-08 dwd
```

从 DWS / ADS 开始：

```bash
bash /home/your_user/retail_hive_project/hive/run_daily_hive_profiled.sh 2026-04-08 mart
```

只从星型模型开始：

```bash
bash /home/your_user/retail_hive_project/hive/run_daily_hive_profiled.sh 2026-04-08 star
```

执行详细报告：

```bash
RUN_REPORTS=1 \
bash /home/your_user/retail_hive_project/hive/run_daily_hive_profiled.sh 2026-04-08
```

日志输出到：

```text
logs/hive_run_*.log
logs/hive_timing_*.tsv
```

`logs/` 属于运行产物，不提交仓库。

---

## 13. 回刷、T+1 与 SCD2 保护

区间回刷：

```bash
bash /home/your_user/retail_hive_project/hive/run_backfill_hive.sh \
  2026-04-01 \
  2026-04-08
```

T+1 修正：

```bash
bash /home/your_user/retail_hive_project/hive/run_t1_window_hive.sh 2026-04-08
```

SCD2 历史回刷检查：

```bash
bash /home/your_user/retail_hive_project/hive/check_scd2_backfill_guard.sh 2026-04-08
```

保护规则：

- `dim_user` 尚不存在或没有分区：允许；
- 重跑当前最大日期：允许；
- 加载更晚日期：允许；
- 已存在后续快照时单独重跑旧日期：阻断。

该保护脚本目前是独立工具，尚未自动接入 `run_all_hive.sh`。

---

## 14. 幂等性检查

执行：

```bash
bash /home/your_user/retail_hive_project/hive/run_idempotency_check_hive.sh 2026-04-08
```

当前检查：

- 8 张核心 ODS / DWD / DWS / ADS 表；
- 重跑前后行数；
- 两组 CRC32 内容指纹。

当前未覆盖：

- ODS Raw；
- ODS Reject；
- 星型模型表。

CRC32 用于工程验收，不是密码学哈希。

---

## 15. MySQL 部分如何理解

仓库中的 MySQL 文件用于展示：

- MySQL 清洗与分析；
- DWS / ADS 指标；
- 批次日志；
- 数据质量门禁；
- 本地调度模拟。

本地 Hive 复现不依赖 MySQL。

需要自动同步时，应另行接入：

- DataX；
- Sqoop；
- SeaTunnel；
- DolphinScheduler 数据同步任务；
- 其他适合目标环境的同步工具。

---

## 16. 常见问题

### 16.1 `Table not found retail`

原因：

```text
Hive 中没有创建源表，只有 MySQL 中存在同名表。
```

处理：

```bash
hive \
  --hiveconf source_file=/home/your_user/retail_hive_project/sample_data/retail_sample.csv \
  -f /home/your_user/retail_hive_project/hive/00_bootstrap_sample_source_hive.sql
```

### 16.2 `Table not found ods_retail_raw_hive`

原因：

```text
直接执行了正常 ODS 加载 SQL，但尚未创建并加载 ODS Raw。
```

处理：

```text
首次部署应直接运行 run_all_hive.sh，不要跳过 ODS Raw 前置步骤。
```

### 16.3 Shell 出现 `^M`、解释器错误或 `pipefail` 错误

处理：

```bash
sed -i 's/\r$//' /home/your_user/retail_hive_project/hive/*.sh
chmod +x /home/your_user/retail_hive_project/hive/*.sh
```

### 16.4 HDFS `Connection refused`

先检查：

```bash
jps
ss -lntp | grep 8020
hdfs dfs -ls /
```

不要先修改业务 SQL。

### 16.5 Hive 显示 `no hbase`

项目未使用 HBase时，只要 Hive SQL 最终正常执行，该提示通常不影响当前项目。

### 16.6 主脚本运行较慢

单机虚拟机中，多个 Hive/MapReduce 作业存在固定启动成本。开发阶段应优先使用：

```text
run_daily_hive_profiled.sh
+
dwd / mart / star 局部重跑
```

不要在尚未定位瓶颈前盲目修改大量 SQL。

---

## 17. 最小复现成功标准

以下条件同时满足，才表示复现成功：

1. Hive `retail` 创建成功；
2. 样例 CSV 与 Hive 源表数量一致；
3. ODS Raw 与源表对账差值为 0；
4. 正常 ODS 与预期正常数据差值为 0；
5. Reject 与预期异常数据差值为 0；
6. DWD、DWS、ADS 和星型模型执行成功；
7. 所有 BLOCK 质量规则通过；
8. 主脚本返回 0；
9. 最终查询结果与当前样例口径一致。

使用仓库原始样例时，至少应看到：

```text
retail=35
ODS Raw=35
正常 ODS=34
Reject=0
DWD=28
```