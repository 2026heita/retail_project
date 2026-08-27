# Hive 离线数仓项目面试讲解要点

> 文件属性：长期保留，提交代码仓库
> 适用文件：`hive_sql/interview_hive_talking_points.md`
> 使用原则：只讲已经实现或已经验证的内容；未完成部分要主动说明边界。

---

## 1. 一句话介绍

> 这是一个把零售订单分析从 MySQL 迁移到 Hive 的离线数仓项目。我构建了 ODS Raw、Reject、正常 ODS、DWD、DWS、ADS 和星型模型，并补充了数据对账、质量门禁、分区重跑、区间回刷、T+1 修正、SCD2 用户维度、批次日志和 DolphinScheduler 调度演示。

这句话需要控制在 20 秒左右，不要一开始就堆所有表名。

---

## 2. 60 秒标准讲法

> 这个项目最初使用 MySQL 对零售订单做清洗和指标分析，后来我把核心链路迁移到 Hive，按照离线数仓思路重新设计。
>
> 数据先从 Hive 源表 `retail` 完整落入 `ods_retail_raw_hive`。Raw 层所有业务字段先按 STRING 保存，不提前删除日期或数值异常。满足技术解析条件（日期、数量、价格均可解析）且属于当前业务日的数据进入 `ods_retail_hive`；日期为空、日期解析失败、数量为空、数量解析失败、价格为空、价格解析失败等 6 类技术解析异常进入 `ods_retail_reject_hive`。源表、Raw、正常 ODS 和 Reject 之间通过三组数量对账和 `ASSERT_TRUE` 形成 ODS 入仓门禁。
>
> 后续 DWD 负责过滤无效数量、无效价格、空客户和取消订单，并统一订单时间；DWS 沉淀客户价值和国家销售汇总；ADS 产出高价值客户销售贡献、客户层级分布、国家销售排行和高价值客户商品偏好。
>
> 工程化方面，我使用 `bizdate`、ORC、日期分区和 `INSERT OVERWRITE` 支持指定日期重跑，并增加区间回刷、T+1 修正、内容指纹幂等性检查，以及 DWD、DWS/ADS、星型模型三层业务质量门禁。完整 Shell 主链路共 21 个顶层执行步骤，覆盖 ODS 入仓、DWD、DWS/ADS、BI 经营总览 ADS、各层质量门禁、Star Schema 和最终结果展示；任意 BLOCK 门禁失败都会返回非零状态并阻断下游。
>
> 星型模型部分包含 SCD2 用户维度、商品维度、日期维度、地理维度、订单事实表和星型客户价值汇总。当前 `2026-04-08` 历史工程回归（engineering_legacy_3x）中，源表与 Raw 都是 3,202,113 行，DWD 与事实表都是 2,416,593 行、金额都是 53,230,287.48，星型模型 12 条规则全部通过。
>
> 当前 Canonical 基线（1,067,371 行 Raw，DWD 805,531 行，DWD 金额 17,743,429.16）中，Star 质量规则定义为 17 条，2010-03-04 质量结果为 17/17/17/0。

---

## 3. 3 分钟完整讲法

> 项目可以分成 MySQL、Hive 和调度三个部分。
>
> 第一部分是 MySQL 分析链路。我先完成订单清洗、客户价值分层、国家销售分析和多个 ADS 指标，并用 Windows 批处理模拟调度。调度脚本会为每次运行生成 `BATCH_ID`，依次写入 START、SUCCESS 或 FAILED。MySQL 数据质量脚本包含 20 项检查，失败时使用 `SIGNAL SQLSTATE '45000'` 返回非零状态，而不是只打印异常数量。
>
> 第二部分是 Hive 离线数仓。原设计直接从 `retail` 写正常 ODS，日期解析失败的数据可能在进入 ODS 前被过滤，后续检查无法发现。我把入口改成 Raw、Reject 和正常 ODS 三部分。Raw 按处理批次 `batch_dt` 保存完整源数据；Reject 保存 6 类技术解析异常（日期为空、日期解析失败、数量为空、数量解析失败、价格为空、价格解析失败）；正常 ODS 按业务日期 `dt` 保存满足技术解析条件且属于当前业务日的数据。
>
> ODS 后面是 DWD、DWS 和 ADS。DWD 保存清洗后的有效订单明细，DWS 分别形成客户价值和国家销售汇总，ADS 形成高价值客户贡献、客户层级分布、国家销售排行和商品偏好。国家维度中 United Kingdom 曾占约 69.6%，所以我对国家销售汇总使用 Salt 和两阶段聚合；DWD 大表关联客户价值小表时使用 MAPJOIN，并通过 EXPLAIN 验证。
>
> 第三部分是星型模型和工程化。用户维度采用按业务日物化完整历史快照的 SCD2，每个 dt 分区保存截至当天的完整历史状态，属性未变化时延续当前版本，属性变化才关闭旧版本并创建新版本；事实表按订单日期匹配有效期内的用户版本，不是只关联当前版本。项目还有区间回刷、T+1 修正、幂等性指纹检查和历史回刷保护。
>
> 完整 run_all_hive.sh 当前共 21 个顶层执行步骤，包含 ODS Raw/Reject/正常 ODS、ODS 入仓断言、DWD 及 6 条 BLOCK 规则、DWS/ADS 指标构建、BI 经营总览日 ADS、DWS/ADS 11 条结果质量规则，以及 Star Schema 与 17 条 Star 质量规则，最后输出结果检查。DolphinScheduler 的 12 节点 JSON 已完成演示验收，但它是较早版本，目前最完整的链路仍然是 Shell 主脚本，调度 JSON 尚未同步新增的 Raw、Reject、结果门禁和星型模型。

---

## 4. 项目分层怎么解释

### 4.1 ODS Raw

表：

```text
ods_retail_raw_hive
```

回答：

> ODS Raw 的目标是保真，不是清洗。所有源字段先按 STRING 保存，避免非法日期、非法数量或特殊格式在类型转换时丢失原值。Raw 使用 `batch_dt` 分区，因为订单日期本身可能无法解析，但入仓批次一定可以确定。

### 4.2 ODS Reject

表：

```text
ods_retail_reject_hive
```

回答：

> Reject 表用于隔离不能进入正常业务链路的技术解析异常，同时保留原始字段、异常编码、异常原因和处理批次。当前覆盖 6 类技术解析异常：日期为空、日期解析失败、数量为空、数量解析失败、价格为空、价格解析失败。不应夸大为已经覆盖全部异常类型。

### 4.3 正常 ODS

表：

```text
ods_retail_hive
```

回答：

> 正常 ODS 从 Raw 读取，解析订单日期后，只把属于当前 `bizdate` 的记录写入 `dt` 分区。它不再直接读取 `retail`，这样正常链路和异常链路共用同一份原始输入，口径更一致。

### 4.4 DWD

表：

```text
dwd_retail_clean_hive
```

回答：

> DWD 保存清洗后的有效订单明细，主要排除无效数量、无效价格、空客户、取消订单和关键字段异常，并生成销售金额。后续业务指标统一基于 DWD，而不是直接基于 Raw 或 Reject。

### 4.5 DWS

表：

```text
dws_customer_value_hive
dws_sales_summary_hive
```

回答：

> DWS 负责形成可复用的主题汇总。客户价值表按客户聚合订单、金额等指标并划分客户层级；国家销售表按国家聚合订单数、客户数、销售额和平均订单金额。

### 4.6 ADS

表：

```text
ads_high_value_customer_sales_contribution_hive
ads_customer_level_distribution_hive
ads_country_sales_rank_hive
ads_high_value_customer_preference_hive
ads_sales_anomaly_daily_hive
```

回答：

> ADS 面向最终分析或展示场景，每张表对应一个清晰主题，不再承担复杂明细清洗。新增的经营异常 ADS 基于规则检测日度经营异常，识别 HIGH / MEDIUM 等级异常并分析主要驱动指标（ORDERS 或 AVG_ORDER_VALUE）。

---

## 5. `batch_dt` 和 `dt` 有什么区别

可以回答：

> `batch_dt` 表示数据在什么时候被 ETL 处理，主要用于 Raw 和 Reject 的技术追踪；`dt` 表示订单属于哪个业务日期，主要用于正常 ODS 及下游业务表。
>
> 日期解析失败的数据没有可靠业务日期，因此不能直接按 `dt` 落地，但仍然可以按 `batch_dt` 追踪。

关键词：

```text
处理批次
业务日期
技术追踪
异常数据没有可靠业务日期
```

---

## 6. 为什么叫伪增量，而不是真正增量

可以回答：

> 这个项目没有接入数据库 Binlog、CDC 或消息队列，因此不是实时增量。它按照 `bizdate` 重建指定业务日期分区，并用 `INSERT OVERWRITE` 覆盖当天结果。
>
> Raw 层当前会把源表完整写入一个 `batch_dt` 分区，正常 ODS 再按订单日期筛选当前业务日。因此更准确地说，它是按业务日期分区重算和批次快照，不是真正只读取新增记录的 CDC 增量。

不要说：

```text
每天只扫描当天新增源数据
```

当前代码不能支持这个说法。

---

## 7. 为什么使用 `INSERT OVERWRITE`

可以回答：

> `INSERT OVERWRITE PARTITION` 会重建指定分区，同一天重复执行不会不断追加重复数据，适合离线数仓的补数、重跑和回刷。
>
> 但它只能保证覆盖写入，不自动证明结果内容完全一致，所以项目又增加了行数和内容指纹幂等性检查。

---

## 8. 完整主链路为什么是 21 步

当前入口：

```bash
bash run_all_hive.sh 2026-04-08
```

21 个顶层执行步骤为：

```text
01  创建 ODS Raw
02  创建 ODS Reject
03  创建正常 ODS
04  加载 ODS Raw
05  加载 ODS Reject
06  加载正常 ODS
07  ODS 入仓完整性门禁
08  ODS 内容检查
09  创建 DWD
10  加载 DWD
11  DWD 质量门禁
12  构建客户价值 DWS
13  构建国家销售 DWS
14  构建高价值客户贡献 ADS
15  构建客户层级分布 ADS
16  构建国家销售排行 ADS
17  构建高价值客户偏好 ADS
18  构建 BI 经营总览日 ADS
19  DWS/ADS 结果质量门禁
20  构建并校验 Star Schema
21  最终结果展示
```

面试表达：

> 主链路早期只有约 15 个步骤；加入 ODS Raw、Reject、ODS 入仓门禁等工程能力后扩展到 20 步；后来又将 BI 经营总览日 ADS（ads_sales_overview_daily_hive）正式接入主入口，因此当前 run_all_hive.sh 为 21 个顶层执行步骤。面试时应以当前源码为准，不再使用 15 步或 20 步的旧口径。

---

## 9. `00-10` 和 `11-22` 是什么关系

可以回答：

> 文件编号只是项目组织方式，不能简单理解成两条互相替代的链路。
>
> ODS、DWD、DWS、ADS 指标主链路主要由 00 系列、01-10 和 23-27 组成；11-22 是在 DWD 基础上继续构建的星型模型扩展；28 是星型模型质量日志。
>
> 星型模型不是替代原 DWS/ADS，而是展示维度建模、SCD2 和事实表能力。完整运行时，DWS/ADS 结果门禁通过后才进入星型模型。

---

## 10. 数据质量体系怎么讲

最准确的说法是：

> 项目有一个 ODS 入仓完整性门禁，加上三层业务质量门禁。

不要简单说“总共三级”，因为现在 ODS 入口还有单独一层断言。

### 10.1 ODS 入仓完整性门禁

文件：

```text
10_check_ods_ingestion_hive.sql
```

三组对账：

```text
源表数量 = ODS Raw 数量
预期正常数量 = 正常 ODS 数量
预期异常数量 = Reject 数量
```

回答：

> ODS 门禁直接使用 `ASSERT_TRUE`。差值不为 0 时 Hive 任务失败，错误数据不会继续进入 DWD。

### 10.2 ODS 内容检查

文件：

```text
10_check_ods_retail_hive.sql
```

回答：

> 这个文件用于查看空值、非正数量、非正价格、取消订单、Reject 数量和样例，不承担入仓完整性阻断。数据画像和质量门禁不能混为一谈。

### 10.3 DWD 门禁

日志表：

```text
quality_log_hive
```

规则：

```text
DWD_001 - DWD_006
```

共 6 条 BLOCK 规则，覆盖：

- 无效数量；
- 无效价格；
- 空客户；
- DWD 分区非空；
- ODS 理论有效量与 DWD 实际量对账；
- DWD 时间格式标准化。

### 10.4 DWS/ADS 结果门禁

日志表：

```text
result_quality_log_hive
```

规则：

```text
RESULT_001 - RESULT_011
```

共 11 条规则，包含 BLOCK 和 WARN，覆盖：

- DWS 分区非空；
- DWD 与 DWS 销售额对账；
- 核心 ADS 分区非空；
- 客户和销售额占比汇总；
- 高价值客户贡献率范围。

### 10.5 星型模型门禁

日志表：

```text
star_quality_log_hive
```

规则：

```text
STAR_001 - STAR_017
```

当前 17 条规则均为 BLOCK，覆盖：

- 用户维度分区非空；
- 每个客户只能有一个当前版本；
- SCD2 日期范围合法；
- 当前版本 `end_date` 正确；
- 商品、日期和地理业务键唯一；
- 事实表分区非空；
- DWD 与事实表行数、金额一致；
- `order_line_id` 唯一；
- 事实表与星型 DWS 客户数、金额一致。

### 10.6 BLOCK 和 WARN

可以回答：

> BLOCK 失败必须返回非零状态，停止下游；WARN 只记录和展示，不阻断。门禁脚本如果无法读取检查结果，也不能默认通过，而是按失败处理。

---

## 11. 质量日志表为什么有价值

可以回答：

> 控制台输出只能说明某次运行发生了什么，质量日志表可以按 `dt` 保存规则编号、检查对象、实际值、阈值、异常数量、状态和检查时间，便于追踪历史质量变化，也方便调度系统查询失败项。

主要字段：

```text
rule_code
table_name
check_item
check_level
actual_value
threshold_value
abnormal_cnt
check_status
check_detail
check_time
dt
```

---

## 12. 如何证明不是只会跑一个成功样例

回答时必须区分当前回归和历史多日验证。

### 12.1 当前完整数据回归

`2026-04-08` 已验证：

```text
源表 retail：3,202,113
ODS Raw：3,202,113
源表与 Raw 差值：0

预期正常 ODS：3,202,113
正常 ODS：3,202,113
正常 ODS 差值：0

预期 Reject：0
实际 Reject：0
Reject 差值：0

DWD：2,416,593
fact_order：2,416,593
DWD 与事实表金额：53,230,287.48
客户：5,878
商品：4,630
国家：41
高价值客户销售贡献率：86.68%
```

### 12.2 质量门禁成功和失败路径

可以回答：

> 正常业务日星型规则全部通过（历史工程验证时为 12 条，当前规则定义为 17 条）；项目还使用空分区日期测试过失败路径，门禁会返回退出码 1，而不是错误地显示成功。

### 12.3 历史 7 天验证

可以回答：

> 项目还保存了较早版本的 7 天分区、区间回刷、T+1 和幂等性截图，用来证明脚本可以跨日期运行。
>
> 但历史截图中的 DWD 3,124,956 行和国家 43 个，与当前回归中的 DWD 2,416,593 行和国家 41 个不是同一数据或清洗规则基线，所以我不会把两组数字直接比较。

这段主动说明差异，反而更可信。

---

## 13. 幂等性怎么验证

脚本：

```bash
bash run_idempotency_check_hive.sh 2026-04-03
```

可以回答：

> 我先采集重跑前的表快照，再执行完整链路，最后采集重跑后的快照。快照不仅比较行数，还比较两组 CRC32 内容指纹，降低“行数相同但内容变化”的漏检风险。任意表不一致时脚本返回非零状态。

当前覆盖 8 张核心表：

```text
正常 ODS
DWD
两张 DWS
四张 ADS
```

边界：

> 当前幂等性脚本尚未覆盖 ODS Raw、Reject 和星型模型表；CRC32 也是工程验收指纹，不是密码学哈希。

---

## 14. 区间回刷和 T+1 怎么做

### 14.1 区间回刷

```bash
bash run_backfill_hive.sh 2026-04-01 2026-04-08
```

回答：

> 脚本按日期升序调用完整主链路。任意一天失败就停止，避免后续日期在错误上游结果上继续计算。

### 14.2 T+1 修正

```bash
bash run_t1_window_hive.sh 2026-04-08
```

回答：

> 脚本自动计算前一天，然后回刷前一天和当天，用于处理晚到或修正数据。

### 14.3 SCD2 历史回刷保护

```bash
bash check_scd2_backfill_guard.sh 2026-04-08
```

回答：

> 按业务日物化完整历史快照的 SCD2 存在日期依赖。如果已经存在更晚快照，却只重跑较早的一天，后续快照可能继续继承旧状态。保护脚本会比较本次日期和最大分区日期，历史单日重跑会被阻断，并提示从该日期升序回刷到最大日期。

边界：

> 该保护脚本目前是独立工具，尚未自动接入 `run_all_hive.sh`，所以不能说系统已经完全消除误操作。

---

## 15. 用户维度是不是完整 SCD2

建议回答：

> Star 历史已连续回刷并验证至 2010-03-04，覆盖 73 个真实业务日期；其中在 2010-03-04 对 customerid=12431 的 Belgium → Australia 真实属性变化进行了重点 SCD2 验证。完整 DWD 保留 604 个真实业务日期。

具体逻辑：

1. 从当前 DWD 中选出每个客户当天最新国家属性；
2. 读取业务日期之前最近的完整维度快照；
3. 历史非当前版本继续保留；
4. 当前属性不变时延续原版本；
5. 属性变化时把旧版本关闭到前一天；
6. 为新客户或属性变化客户生成新当前版本；
7. 当天没有出现的历史客户继续保留当前版本；
8. 通过 `INSERT OVERWRITE` 生成当天完整快照。

代理键：

```text
user_id = md5(customerid | country | 版本开始日期)
```

当前代码中版本开始日期由 `bizdate` 表示。

当前验证：

```text
dim_user 总版本数：5,878
当前版本数：5,878
客户数：5,878
实际分区：dt=2026-04-08
```

不要说：

```text
已经用连续多天属性变化完整验证了所有 SCD2 场景
```

目前没有足够证据支持这个说法。

---

## 16. 为什么 SCD2 使用临时 ORC 表

可以回答：

> Hive 3.1.3 和 MapReduce 环境中，复杂 CTE、JOIN、UNION ALL 组合容易形成很复杂的执行计划。我把当天客户、上一完整快照和上一当前版本物化为临时 ORC 表，降低优化器重复展开的复杂度，同时保持离线快照和可重跑语义。

临时表：

```text
tmp_dim_user_today
tmp_dim_user_prev_all
tmp_dim_user_prev_current
```

这些是 Hive 会话中的临时计算对象，不是需要长期提交的业务表。

---

## 17. 事实表怎么关联 SCD2

事实表：

```text
fact_order
```

回答：

> 事实表不能只关联 `is_current=true`，因为历史订单应该匹配订单发生时有效的客户版本。当前 SQL 按 `customerid` 关联，并要求订单日期位于 `start_date` 和 `end_date` 之间，同时取当前 `dt` 下的完整 SCD2 快照。

关联逻辑：

```text
invoice_date >= start_date
invoice_date <= end_date
```

事实粒度：

> 一行订单商品明细。

代理键：

> `order_line_id` 对订单、客户、国家、商品、日期、数量、金额和 `duplicate_seq` 做 MD5。`duplicate_seq` 用于区分字段完全相同的重复明细，降低代理键冲突。

---

## 18. 星型模型包含什么

维表：

```text
dim_user
dim_product
dim_date
dim_geo
```

事实表：

```text
fact_order
```

星型主题汇总：

```text
dws_customer_value_star_hive
```

可以回答：

> 星型模型用于展示维度建模能力，而原 DWS/ADS 用于展示面向主题和报表的指标建设，两者是补充关系，不是替代关系。

边界：

> `dim_product` 当前是从订单明细中选择一个代表性商品描述，不等同于独立商品主数据系统。

---

## 19. 做过哪些 Hive SQL 优化

### 19.1 数据倾斜

可以回答：

> 我先统计 `country` 分布，一个回归中 United Kingdom 约 217 万行，占总量约 69.6%，说明 `GROUP BY country` 存在热点 Key 风险。国家销售汇总对销售金额使用 20 个 Salt 和两阶段聚合，再按国家汇总。

注意：

> 订单数和客户数不能简单在加盐后求和，因为同一订单或客户可能跨 Salt 重复。因此代码对 `country+invoice` 和 `country+customerid` 单独去重后统计。

### 19.2 MAPJOIN

可以回答：

> 高价值客户相关 ADS 是 DWD 明细大表关联客户价值小表，使用 `MAPJOIN` 广播小表，减少 Shuffle，并通过 EXPLAIN 检查 `Map Join Operator`。

### 19.3 分区裁剪

可以回答：

> 多表关联时同时限制 DWD 和 DWS 的 `dt='${hiveconf:bizdate}'`，避免读到其他日期分区，也避免跨日期关联导致结果放大。

### 19.4 空值兜底

可以回答：

> 聚合没有匹配记录时 `SUM` 可能返回 NULL。我在高价值客户销售额和总销售额中增加 `COALESCE(...,0)`，保证 ADS 和 BI 导出得到明确的 0，而不是空值。

---

## 20. 性能为什么约 30 分钟，是否优化过

实测：

```text
TOTAL_PIPELINE：1963 秒，约 32 分 43 秒
```

主要耗时：

```text
星型模型链路                    758 秒
DWS/ADS 结果质量门禁            237 秒
ODS 入仓完整性门禁              151 秒
DWD 质量门禁                    130 秒
国家销售 DWS                    109 秒
```

实测（代表性真实业务日，非严格 benchmark）：

```text
优化前（2009-12-18）：
总耗时约 1060.39 秒，总 MR Job：43
Star quality 阶段约 491.8 秒，quality 阶段 MR Job：24

优化 28_load_star_quality_log_hive.sql 后（2009-12-20）：
总耗时约 979.87 秒，总 MR Job：39
Star quality 阶段约 412.01 秒，quality 阶段 MR Job：21
```

建议回答：

> 我先增加步骤级耗时监控，而不是直接盲目调参数。结果表明星型模型和多层质量门禁占了主要时间。当前运行环境是单机虚拟机，多个独立 Hive/MapReduce 作业有较高固定启动成本。
>
> 在代表性真实业务日中，质量阶段从约 492 秒降至约 412 秒，MR Job 从 24 降至 21；总 Job 从 43 降至 39，总耗时从约 1060 秒降至约 980 秒。但两个测试日期不同、数据规模不同，因此不是严格同数据集 benchmark，不能把百分比描述成严格性能保证。
>
> 我完成了倾斜、MAPJOIN、分区裁剪和局部重跑等低风险优化，但没有为了把 30 分钟压缩几分钟而大规模合并 SQL，因为那会增加维护复杂度和质量风险。生产环境还要结合 Tez/Spark 执行引擎、资源配置和 SLA 再优化。

开发阶段提速方式：

```bash
bash run_daily_hive_profiled.sh 2026-04-08 dwd
bash run_daily_hive_profiled.sh 2026-04-08 mart
bash run_daily_hive_profiled.sh 2026-04-08 star
```

关键词：

```text
先度量再优化
减少重复扫描
减少 Shuffle
局部重跑
考虑维护成本
```

---

## 21. DolphinScheduler 怎么讲

可以回答：

> 我使用 DolphinScheduler 3.2.2 Standalone 做过 12 节点演示 DAG，并把元数据库从 H2 内存库迁移到 MySQL，使工作流和实例可以持久化。默认镜像缺少 MySQL Connector/J 和 SSH 客户端，所以通过自定义镜像补充 JDBC 驱动和 OpenSSH Client，再由 Shell 节点通过 SSH 调用 Hive 主机。

当前 JSON 参数：

```text
bizdate=$[yyyy-MM-dd-1]
HIVE_USER=your_hive_user
HIVE_HOST=your_hive_host
PROJECT_HOME=/home/your_user/retail_hive_project
```

关键边界：

> 当前 DolphinScheduler JSON 是已验收的较早 12 节点演示 DAG，尚未同步后来新增的 ODS Raw、Reject、ODS 入仓门禁、DWS/ADS 结果门禁、Star Schema 以及 BI 经营总览 ADS 等能力；当前最完整执行链路以 `run_all_hive.sh` 的 21 个顶层执行步骤为准，因此不能声称 DolphinScheduler 已经覆盖最新完整链路。

为什么 `schedule=null`：

> 公开导入模板不自动携带启用中的定时计划。导入后应先修改环境参数、手动验证，再根据目标环境时区和业务窗口配置调度。

---

## 22. MySQL 阶段怎么和 Hive 阶段联系

可以回答：

> MySQL 是项目的早期分析和调度模拟阶段，Hive 是后续离线数仓迁移阶段。两边使用相似业务指标，但不是同一个数据库里的表，也没有内置自动同步。
>
> MySQL 阶段展示 SQL 分析、20 项质量门禁和批次日志；Hive 阶段展示分层、分区、回刷、质量日志、SCD2 和调度编排。

MySQL 调度流程：

```text
确认 etl_task_log
→ 写 START
→ 执行 08_run_all.sql
→ 执行 20 项质量门禁
→ 写 SUCCESS 或 FAILED
→ 按当前 batch_id 查询日志
```

认证：

> 使用 `mysql_config_editor` 的 login-path，避免在脚本和仓库中保存明文密码。

---

## 23. 当前项目有哪些真实边界

面试中主动说明以下边界不会减分，反而能体现判断力：

1. 当前是离线分区重算，不是 CDC 实时增量。
2. ODS Raw 每个批次仍会完整读取源表，数据量大时成本较高。
3. 当前 canonical 基线 reject=0；新版 Reject 已扩展为 4 种日期格式和 6 类技术异常识别，目前只完成 10 行功能样本验证，尚未完成新版逻辑的 1,067,371 行全量重跑。
4. SCD2 SQL 逻辑已经实现，当前已验证至 2010-03-04，覆盖 73 个真实业务日期，包含真实的属性变化案例。
5. SCD2 回刷保护是独立脚本，尚未自动接入主入口。
6. 幂等性检查只覆盖 8 张核心业务表。
7. DolphinScheduler JSON 仍是较早的 12 节点演示 DAG。
8. BI Dashboard 只有截图，没有生成脚本。
9. 历史 7 天截图与当前回归不是同一数据基线。
10. 单机 Hive 链路约 30 分钟，尚未进行高风险深度性能重构。
11. 商品维度来源于交易明细，不是独立主数据系统。
12. 项目没有内置 MySQL 到 Hive 的自动同步。
13. Hive ADS 范围写入采用动态分区，一次范围式 ADS DML 覆盖 604 个真实业务日期；脚本仍保留独立的 DWD 前置检查和 ADS 后置验证查询。
14. Hive → MySQL 同步采用范围式一次 Hive 查询 + 批量 MySQL UPSERT，不是逐日同步。
15. 跨系统 DECIMAL 对账需要按数值类型比较，避免 Hive 输出 341.4 与 MySQL DECIMAL 输出 341.40 的字符串格式差异导致假失败。
16. Spring Boot 环比接口当前使用"同一 source_system 下上一可用业务日"语义，不是固定"前一日（date.minusDays(1)）"，以应对真实业务日期存在缺口的情况。
17. Star Schema 目前只连续验证至 2010-03-04（73 个真实业务日期），不是 604 天全量历史。

---

## 24. 不建议的说法

不要说：

- “这是生产级实时数仓。”
- “每天只读取新增数据。”
- “DolphinScheduler 已经完整调度最新 21 步。”
- “Reject 已经覆盖所有脏数据。”
- “SCD2 在所有 604 个业务日期上的多版本属性变化都已完整验证。”（当前仅连续验证至 2010-03-04，73 个真实业务日期，并包含 customerid=12431 的真实属性变化案例）
- “CRC32 能绝对保证数据内容不变。”
- “所有性能问题都已经解决。”
- “MySQL 表可以被 Hive 直接读取。”
- “历史 7 天结果和当前回归完全一致。”
- “ODS 内容检查就是 ODS 入仓门禁。”

建议说：

- “这是学习型离线数仓项目，重点是分层、可追溯、可重跑和质量阻断。”
- “当前采用业务日期分区重算和批次快照。”
- “Shell 是当前最完整链路，DolphinScheduler 是已验收演示 DAG。”
- “SCD2 逻辑已实现，已连续验证至 2010-03-04（73 个真实业务日期），并通过 customerid=12431 的 Belgium → Australia 真实属性变化案例验证多版本行为。”
- “性能已经完成分步骤定位，深度优化需要结合执行引擎和 SLA。”

---

## 25. 简历项目描述

```text
零售数据分析 MySQL 到 Hive 离线数仓迁移

- 基于约 320 万行工程扩展零售订单数据，将 MySQL 分析链路迁移到 Hive，构建 ODS Raw、ODS Reject、正常 ODS、DWD、DWS、ADS 和星型模型。
- 设计 Raw 原始保真和 Reject 技术解析异常分流（6 类：日期/数量/价格的空值与解析失败），使用 batch_dt 与 dt 区分处理批次和业务日期；通过三组行数对账和 ASSERT_TRUE 构建 ODS 入仓完整性门禁。
- 使用 ORC、日期分区、bizdate 参数和 INSERT OVERWRITE 支持指定日期重跑，并实现区间回刷、T+1 修正和分阶段局部重跑。
- 建立 DWD 6 条、DWS/ADS 11 条和星型模型规则（历史工程验证时为 12 条，当前规则定义为 17 条）；BLOCK 失败时 Shell 返回非零状态，阻断下游任务。
- 基于 DWD 构建 dim_user、dim_product、dim_date、dim_geo 和 fact_order，实现按业务日物化完整历史快照的 SCD2 用户维度及事实表有效期关联。
- 使用行数和双 CRC32 内容指纹验证 8 张核心表重跑幂等性，并增加 SCD2 历史日期回刷保护。
- 针对 United Kingdom 热点 Key 使用 Salt 与两阶段聚合，针对大表关联小表使用 MAPJOIN，并通过 EXPLAIN 验证执行计划。
- 为 MySQL 调度模拟增加批次级 START、SUCCESS、FAILED 日志和 20 项可阻断质量检查；为 DolphinScheduler 统一环境占位参数并完成 12 节点 DAG 演示。
- 历史工程回归（engineering_legacy_3x，2026-04-08）中源表与 ODS Raw 均为 3,202,113 行，DWD 与事实表均为 2,416,593 行、金额均为 53,230,287.48，星型质量规则全部通过；当前 Canonical 基线（1,067,371 行 Raw，DWD 805,531 行，DWD 金额 17,743,429.16）中 Star 质量规则为 17 条，2010-03-04 质量结果为 17/17/17/0。
```

如果简历空间不足，保留前 6 条即可。

---

## 26. STAR 法面试回答示例

### 场景一：发现 ODS 会静默丢数

**S（背景）**

> 原加载脚本先解析日期再按业务日过滤，日期解析失败记录不会进入 ODS。

**T（任务）**

> 我需要保证源数据可追溯，并让质量检查能够真正发现异常。

**A（行动）**

> 增加 ODS Raw，所有字段先按 STRING 保存；增加 Reject 技术解析异常表；正常 ODS 从 Raw 读取；增加源表、Raw、正常 ODS、Reject 三组对账和断言。

**R（结果）**

> `2026-04-08` 源表和 Raw 都是 3,202,113 行，三组差值均为 0，Reject=0。以后即使出现解析异常，也会被 Reject 接住而不是静默消失。

### 场景二：把质量检查改成质量门禁

**S**

> 原质量 SQL 只输出异常数量，调度程序仍可能显示成功。

**T**

> 让检查结果能够直接控制任务状态。

**A**

> Hive 门禁统计 BLOCK 失败数量并返回非零状态；MySQL 将 20 项规则写入临时结果表，失败时使用 `SIGNAL SQLSTATE '45000'`。

**R**

> 调度脚本能够写入 START、SUCCESS 或 FAILED，形成可自动阻断的运行闭环。

### 场景三：处理数据倾斜

**S**

> 国家维度中 United Kingdom 占约 69.6%，国家聚合存在 Reduce 热点风险。

**T**

> 在不改变订单数和客户数口径的前提下缓解倾斜。

**A**

> 销售金额使用 Salt 和两阶段聚合；订单数、客户数分别按业务键去重；关联小表时使用 MAPJOIN，并用 EXPLAIN 验证。

**R**

> 优化后全链路质量门禁和金额对账继续通过，业务结果未改变。

### 场景四：Hive/MySQL DECIMAL 格式差异导致对账假失败

**S（背景）**

> Hive → MySQL 同步后需要逐行对账验证数据一致性。

**T（任务）**

> 确保 604 个业务日期的 total_sales、total_orders 等指标完全一致。

**A（行动）**

> 发现 Hive 输出 DECIMAL 为 341.4，而 MySQL DECIMAL 输出为 341.40，字符串比较导致假失败。
> 修改对账脚本：日期和整数严格比较，DECIMAL 按数值容差比较（CAST AS DECIMAL 后比较）。

**R（结果）**

> 604 行逐行对账全部 PASS，duplicate_dt_count=0，total_sales=17,743,429.16 完全一致。

### 场景五：真实业务日期非连续导致环比失效

**S（背景）**

> Spring Boot 环比接口原实现使用 date.minusDays(1) 作为比较日期。

**T（任务）**

> 真实 canonical 数据验证发现业务日期存在缺口，例如 2009-12-13 的上一日 2009-12-12 无数据。

**A（行动）**

> 修改环比语义为"同一 source_system 下上一可用业务日"。
> 新增 Mapper 方法 selectPreviousAvailable(date, sourceSystem)，SQL 使用 WHERE dt < #{date} ORDER BY dt DESC LIMIT 1。
> 更新单元测试：新增日期缺口场景测试（2009-12-13 → 2009-12-11），防止退回 minusDays(1) 逻辑。

**R（结果）**

> 真实 API 验证：2009-12-13 → 2009-12-11，comparisonAvailable=true，两边 sourceSystem 均为 retail_canonical_ads。
> 连续日期回归：2009-12-03 → 2009-12-02 仍然 PASS。
> Spring Boot 自动化测试：单元测试与集成测试全部通过，其中包含基于 Testcontainers + MySQL 8 的 SalesOverviewMapper 集成测试，覆盖单日查询、日期范围查询和上一可用业务日查询；Backend CI 执行 `./mvnw -B clean verify`。

---

## 27. 面试前自查清单

```text
1. 能否说清楚 Raw、Reject、正常 ODS 的区别？
2. 能否说清楚 batch_dt 与 dt 的区别？
3. 能否说清楚为什么不是 CDC 真增量？
4. 能否准确说出 run_all_hive.sh 当前是 21 个顶层执行步骤？
5. 能否区分 ODS 内容检查和 ODS 入仓门禁？
6. 能否说明一个入口门禁加三层业务门禁？
7. 能否说清楚 BLOCK 与 WARN 的不同？
8. 能否说清楚 DWD 与事实表如何做行数和金额对账？
9. 能否解释 SCD2 新增、延续、关闭和新版本生成？
10. 能否解释事实表为什么按有效期关联用户版本？
11. 能否说明 SCD2 当前的验证范围和真实案例？
12. 能否说清楚区间回刷、T+1 和历史回刷保护？
13. 能否说明幂等性脚本只覆盖 8 张表？
14. 能否解释 Salt 后为什么订单数和客户数不能直接相加？
15. 能否说明 MAPJOIN 适用的大表 Join 小表场景？
16. 能否说清楚代表性真实业务日的耗时和主要瓶颈？
17. 能否说明为什么没有盲目做深度性能重构？
18. 能否说清楚 MySQL 与 Hive 不是自动连通的？
19. 能否说明 DolphinScheduler 12 节点 DAG 与当前 21 个顶层 Shell 执行步骤的差异？
20. 能否主动说明项目的真实边界而不夸大？
```

---

## 28. 最后总结

最稳妥的项目定位：

> 这是一个从 MySQL 分析迁移到 Hive 的学习型离线数仓项目。它不仅包含 ODS、DWD、DWS、ADS 和星型模型，还围绕原始数据保真、异常分流、数据对账、质量阻断、回刷、幂等性、SCD2、调度和性能分析做了工程化补充。当前 Shell 链路是最完整实现，DolphinScheduler 是已验收的调度演示。Star Schema 已连续验证到 2010-03-04，共 73 个真实业务日期，并验证了 customerid=12431 Belgium→Australia 的真实属性变化。项目已经验证核心成功和失败路径，但仍保留实时增量、604 日 Star 全量历史验证、完整调度同步和进一步性能优化等后续空间。