# Hive 迁移与离线数仓设计说明

> 文件属性：长期保留，提交代码仓库
> 适用文件：`hive_sql/hive_migration_design.md`
> 文档口径：以当前仓库代码、`run_all_hive.sh` 和已经完成的回归结果为准。

---

## 1. 文档目的

本文说明零售数据分析项目从 MySQL 迁移到 Hive 后的整体设计，包括：

- 为什么迁移；
- MySQL 与 Hive 的职责边界；
- Hive 分层和数据入口设计；
- 主链路与星型模型的关系；
- 分区重跑、回刷、T+1 和幂等性设计；
- 数据质量门禁；
- SQL 性能优化；
- DolphinScheduler 调度范围；
- 当前已经验证的结果和仍然存在的边界。

本文不是简单的文件清单，而是用于说明当前代码为什么这样组织，以及每个模块在完整链路中的职责。

---

## 2. 项目定位

本项目是在原 MySQL 零售数据分析项目基础上，将核心离线处理链路迁移到 Hive，形成一套学习型离线数仓项目。

MySQL 阶段主要展示：

- 关系型数据库中的订单清洗；
- DWS / ADS 指标开发；
- Windows 和 Linux 调度模拟；
- ETL 批次日志；
- 20 项可阻断数据质量规则。

Hive 阶段主要展示：

- ODS Raw、Reject、正常 ODS、DWD、DWS、ADS 分层；
- ORC 和日期分区；
- `bizdate` 参数化；
- 分区覆盖重跑；
- 质量日志和失败阻断；
- 区间回刷、T+1 和幂等性；
- SCD2 用户维度、事实表和星型模型；
- DolphinScheduler 调度演示。

MySQL 和 Hive 中的同名表是两个独立系统中的对象。当前项目没有内置 MySQL 到 Hive 的自动同步，因此 Hive 最小复现链路采用：

```text
CSV → Hive 源表 retail → Hive 数仓链路
```

---

## 3. 迁移目标

MySQL 版已经能够完成业务分析，但随着数据量、历史分区和调度要求增加，存在以下局限：

1. 明细表和结果表缺少清晰的离线数仓分层。
2. 业务日期重跑、区间回刷和历史快照表达不够统一。
3. 单机关系型数据库不适合作为大规模离线明细计算的主要展示平台。
4. 数据质量检查原本更偏向查询输出，缺少统一日志和阻断机制。
5. 维度建模、SCD2 和事实表能力无法完整表达。
6. 调度平台需要依赖明确的任务返回码判断成功或失败。

因此，Hive 迁移目标不是逐句复制 MySQL SQL，而是重新组织为：

```text
原始接入
→ 数据清洗
→ 主题汇总
→ 应用指标
→ 维度建模
→ 质量门禁
→ 调度执行
```

---

## 4. 当前 Hive 总体架构

```text
Hive 源表 retail
  ↓
ods_retail_raw_hive
  ├── ods_retail_reject_hive
  └── ods_retail_hive
          ↓
dwd_retail_clean_hive
  ├── quality_log_hive
  ├── dws_customer_value_hive
  └── dws_sales_summary_hive
          ↓
  ├── ads_high_value_customer_sales_contribution_hive
  ├── ads_customer_level_distribution_hive
  ├── ads_country_sales_rank_hive
  └── ads_high_value_customer_preference_hive
          ↓
result_quality_log_hive
          ↓
  ├── dim_user
  ├── dim_product
  ├── dim_date
  └── dim_geo
          ↓
      fact_order
          ↓
dws_customer_value_star_hive
          ↓
star_quality_log_hive
```

对应执行入口：

```text
run_all_hive.sh
```

该脚本串联当前最完整的 20 步 Hive 主链路。

---

## 5. ODS 数据入口重新设计

### 5.1 原设计的问题

原设计直接执行：

```text
retail → ods_retail_hive
```

并在写入 ODS 前解析订单日期、按业务日期过滤。

如果 `InvoiceDate` 为空或无法解析，记录会在进入 ODS 前被过滤。后续再从正常 ODS 中检查日期解析失败，通常只能得到 0，因为异常记录已经不在表中。

这会形成：

```text
源数据异常
→ 进入 ODS 前被过滤
→ 后续检查无法发现
→ 静默丢数
```

### 5.2 ODS Raw

新增：

```text
ods_retail_raw_hive
```

设计原则：

- 所有业务字段使用 `STRING`；
- 不做业务清洗；
- 不做日期过滤；
- 不提前转换数量和价格；
- 按处理批次 `batch_dt` 分区；
- 使用 `INSERT OVERWRITE` 保证同批次重跑不追加重复数据。

数据加载：

```text
retail → ods_retail_raw_hive
```

Raw 使用 `batch_dt`，而不是订单业务日期，是因为日期异常记录无法可靠确定业务日期，但仍然可以追踪其进入系统的处理批次。

### 5.3 ODS Reject

新增：

```text
ods_retail_reject_hive
```

当前支持 6 类技术 Reject（按优先级排序）：

```text
EMPTY_INVOICE_DATE
DATE_PARSE_FAILED
EMPTY_QUANTITY
QUANTITY_PARSE_FAILED
EMPTY_PRICE
PRICE_PARSE_FAILED
```

Reject 保存：

```text
原始业务字段
parsed_bizdate
reject_code
reject_reason
batch_dt
```

当前支持的日期格式：

```text
yyyy-MM-dd HH:mm:ss
yyyy-MM-dd HH:mm
d/M/yyyy HH:mm:ss
d/M/yyyy HH:mm
```

当前 canonical 已验收基线 reject=0；新版 Reject 逻辑已支持 4 种日期格式和 6 类技术 Reject，并完成 10 行功能样本验证，但尚未使用新版逻辑对 1,067,371 行 canonical 数据执行完整重跑。

### 5.4 正常 ODS

表：

```text
ods_retail_hive
```

正常 ODS 改为从 Raw 读取：

```text
ods_retail_raw_hive → ods_retail_hive
```

处理逻辑：

1. 读取当前 `batch_dt` 的 Raw 分区；
2. 尝试按 4 种日期格式解析 `invoicedate`；
3. 只保留解析成功且业务日期等于 `bizdate` 的记录；
4. 将数量和价格转换为业务类型；
5. 覆盖写入正常 ODS 的 `dt` 分区。

因此：

```text
batch_dt = 数据处理批次
dt       = 订单业务日期
```

两个日期字段职责不同。

---

## 6. ODS 入仓完整性门禁

文件：

```text
10_check_ods_ingestion_hive.sql
```

该门禁同时计算：

```text
source_cnt
raw_cnt
expected_ods_cnt
ods_cnt
expected_reject_cnt
reject_cnt
```

三组对账：

```text
retail 行数 = ODS Raw 行数
预期正常 ODS 行数 = 正常 ODS 实际行数
预期 Reject 行数 = Reject 实际行数
```

使用：

```sql
ASSERT_TRUE(...)
```

行为：

- 条件成立：Hive 通常返回 `NULL`，SQL 正常结束；
- 条件不成立：Hive 抛出异常，主脚本停止；
- 不能读取结果：任务本身失败，不继续下游。

当前 `2026-04-08` 回归结果：

```text
retail                  3,202,113
ODS Raw                 3,202,113
source_raw_diff                 0

expected_ods_cnt        3,202,113
ods_cnt                 3,202,113
expected_ods_diff               0

expected_reject_cnt             0
reject_cnt                      0
expected_reject_diff            0
```

### 6.1 ODS 内容检查

文件：

```text
10_check_ods_retail_hive.sql
```

该文件用于查看：

- ODS 行数、订单数、客户数、商品数和国家数；
- 核心字段空值；
- 数量、价格和金额异常；
- 取消或退货订单；
- Reject 数量和异常分类；
- 正常和异常样例。

它属于内容质量分析和报告，不替代入仓完整性门禁。

---

## 7. DWD 设计

表：

```text
dwd_retail_clean_hive
```

DWD 负责将正常 ODS 转换为可供业务指标使用的有效订单明细。

主要处理：

- 过滤无效数量；
- 过滤无效价格；
- 过滤空客户；
- 过滤取消或退货订单；
- 过滤关键字符串空值；
- 标准化订单时间；
- 计算销售金额；
- 按 `dt` 分区覆盖写入。

业务指标默认基于 DWD，而不是 Raw、Reject 或未经清洗的正常 ODS。

---

## 8. DWS 与 ADS 设计

### 8.1 DWS 客户价值

表：

```text
dws_customer_value_hive
```

职责：

- 按客户聚合订单数；
- 汇总销售额；
- 形成客户价值层级；
- 为高价值客户相关 ADS 提供复用数据。

当前客户层级：

```text
High Value
Medium Value
Low Value
```

### 8.2 DWS 国家销售汇总

表：

```text
dws_sales_summary_hive
```

职责：

- 国家订单数；
- 国家客户数；
- 国家销售额；
- 平均订单金额。

该表针对 `country` 热点 Key 采用 Salt 和两阶段销售额聚合。订单数和客户数采用独立去重路径，避免加盐后重复统计。

### 8.3 ADS

当前核心 ADS：

```text
ads_high_value_customer_sales_contribution_hive
ads_customer_level_distribution_hive
ads_country_sales_rank_hive
ads_high_value_customer_preference_hive
ads_sales_anomaly_daily_hive
```

分别用于：

- 高价值客户数量、订单和销售贡献；
- 客户层级数量及销售额分布；
- 国家销售排名；
- 高价值客户偏好商品排名；
- **经营异常检测**：基于规则识别日度经营异常（HIGH/MEDIUM 等级），分析主要驱动指标（ORDERS 或 AVG_ORDER_VALUE），覆盖 604 个真实业务日期（2009-12-01 ~ 2011-12-09）。

高价值客户贡献表对无匹配结果增加 `COALESCE(...,0)`，避免 `SUM()` 返回 `NULL`，保证后续 BI 导出和质量检查得到明确数值。

可选 BI 导出文件：

```text
26_ads_bi_export_dataset.sql
```

统一输出：

```text
dt
metric_name
metric_value
```

该查询不属于 `run_all_hive.sh` 的必要步骤。

---

## 9. 当前完整主链路

执行：

```bash
bash run_all_hive.sh 2026-04-08
```

当前 20 步：

```text
01  创建 ODS Raw 表
02  创建 ODS Reject 表
03  创建正常 ODS 表
04  加载 ODS Raw 分区
05  加载 ODS Reject 分区
06  加载正常 ODS 分区
07  执行 ODS 入仓完整性门禁
08  执行 ODS 内容质量检查
09  创建 DWD 表
10  加载 DWD 分区
11  执行 DWD 质量门禁
12  构建客户价值 DWS
13  构建国家销售 DWS
14  构建高价值客户销售贡献 ADS
15  构建客户层级分布 ADS
16  构建国家销售排行 ADS
17  构建高价值客户商品偏好 ADS
18  执行 DWS / ADS 结果门禁
19  构建星型模型并执行星型模型门禁
20  展示结果
```

`run_all_hive.sh` 使用：

```bash
set -Eeuo pipefail
```

并对文件不存在、SQL 执行失败、子门禁失败等情况主动返回非零状态。

---

## 10. 质量日志与业务门禁

当前质量体系由以下部分组成：

```text
ODS 入仓完整性门禁
+
DWD 门禁
+
DWS / ADS 结果门禁
+
星型模型门禁
```

### 10.1 DWD 质量日志

相关文件：

```text
23_quality_log_hive.sql
24_load_quality_log_hive.sql
25_check_quality_log_hive.sql
run_quality_gate_hive.sh
```

规则：

```text
DWD_001 - DWD_006
```

共 6 条 `BLOCK` 规则，覆盖：

- 无效数量；
- 无效价格；
- 空客户；
- DWD 分区非空；
- ODS 理论有效量和 DWD 实际量对账；
- DWD 时间格式标准化。

### 10.2 DWS / ADS 结果质量日志

相关文件：

```text
27_load_result_quality_log_hive.sql
run_result_quality_gate_hive.sh
```

规则：

```text
RESULT_001 - RESULT_011
```

共 11 条规则。

`BLOCK` 规则覆盖：

- 两张 DWS 分区非空；
- DWD 与客户 DWS 销售额一致；
- DWD 与国家 DWS 销售额一致；
- 三张核心 ADS 分区非空；
- 客户占比汇总接近 100%；
- 销售额占比汇总接近 100%；
- 高价值客户贡献率合法。

`WARN` 规则：

```text
RESULT_008
```

高价值客户偏好表为空时只告警，因为低交易量日期可能没有高价值客户。

### 10.3 星型模型质量日志

相关文件：

```text
28_load_star_quality_log_hive.sql
run_star_quality_gate_hive.sh
```

规则：

```text
STAR_001 - STAR_017
```

当前 17 条规则都是 `BLOCK`，覆盖：

- 用户维度分区非空；
- 每个客户只有一个当前版本；
- SCD2 日期范围合法；
- 当前版本结束日期为 `9999-12-31`；
- 商品业务键唯一；
- 国家业务键唯一；
- 日期业务键唯一；
- 事实表分区非空；
- DWD 与事实表行数一致；
- DWD 与事实表金额差小于等于 0.01；
- `order_line_id` 唯一；
- 事实表与星型 DWS 的客户数和金额一致；
- 代理键唯一性；
- 外键非空与非孤儿；
- 维度基数；
- 日期分区一致性。

### 10.4 门禁处理原则

质量日志主要字段：

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

处理规则：

```text
BLOCK + FAIL → 返回非零状态，阻断下游
WARN + FAIL  → 记录和展示，不阻断
无法读取结果 → 按失败处理
```

项目不仅验证了成功路径，也使用空分区日期验证过星型门禁失败路径，脚本能够返回退出码 1。

---

## 11. 主指标链路与星型模型的关系

不能再简单按“00-09 主链路、11-22 扩展链路”描述全部当前代码，因为新增的 Raw、Reject 和质量文件也使用 00、10、23-28 等编号。

更准确的关系是：

### 11.1 指标主链路

```text
ODS Raw / Reject / 正常 ODS
→ DWD
→ 两张 DWS
→ 四张 ADS
→ DWS / ADS 结果门禁
```

用于展示：

- 数据分层；
- 主题汇总；
- 报表指标；
- 质量对账。

### 11.2 星型模型链路

```text
DWD
→ 四张维表
→ fact_order
→ dws_customer_value_star_hive
→ 星型模型门禁
```

用于展示：

- 维度建模；
- SCD2；
- 代理键；
- 事实表粒度；
- 有效期关联；
- 维度和事实对账。

两条链路是补充关系。当前完整执行时，DWS / ADS 结果门禁通过后才进入星型模型。

---

## 12. 星型模型设计

### 12.1 模型结构

```text
dim_user
dim_product
dim_date
dim_geo
    ↓
fact_order
    ↓
dws_customer_value_star_hive
```

### 12.2 用户维度

表：

```text
dim_user
```

字段：

```text
user_id
customerid
country
start_date
end_date
is_current
dt
```

当前实现是按业务日物化完整历史快照的 SCD2：

1. 从当前 DWD 中选出每个客户当天最新的国家属性；
2. 读取当前业务日之前最近的完整 `dim_user` 快照；
3. 保留历史非当前版本；
4. 属性未变化时延续当前版本；
5. 属性变化时将旧版本关闭到前一天；
6. 新客户或属性变化客户生成新版本；
7. 当天没有出现的历史客户继续保留原当前版本；
8. 使用 `INSERT OVERWRITE` 生成当天完整快照。

新版本代理键：

```text
user_id = md5(customerid | country | bizdate)
```

这里的 `bizdate` 同时是该新版本的 `start_date`。

为了适配 Hive 3.1.3 和 MapReduce 执行环境，SCD2 SQL 使用临时 ORC 表物化：

```text
tmp_dim_user_today
tmp_dim_user_prev_all
tmp_dim_user_prev_current
```

### 12.3 事实表

表：

```text
fact_order
```

粒度：

```text
一行有效订单商品明细
```

事实表不能只关联 `is_current=true` 的用户版本，而是按订单日期命中 SCD2 有效期：

```text
invoice_date >= start_date
invoice_date <= end_date
```

同时限制：

```text
dim_user.dt = bizdate
```

因为 `dim_user` 的每个 `dt` 分区保存截至当天的完整历史快照。

`order_line_id` 对以下字段进行 MD5：

```text
invoice
customerid
country
stockcode
invoice_date
quantity
amount
duplicate_seq
```

`duplicate_seq` 用于区分字段完全相同的重复明细，降低代理键重复风险。

### 12.4 其他维表

```text
dim_product
dim_date
dim_geo
```

当前均按 `dt` 保存每日快照。

边界：

- 商品维度来自交易明细，不是独立商品主数据；
- 商品描述的代表值选择仍可继续优化；
- Star 历史已连续回刷并验证至 2010-03-04，覆盖 73 个真实业务日期；其中在 2010-03-04 对 customerid=12431 的 Belgium → Australia 真实属性变化进行了重点 SCD2 验证。完整 DWD 保留 604 个真实业务日期。

---

## 13. 分区、重跑与回刷

### 13.1 分区覆盖写入

主业务表使用：

```text
INSERT OVERWRITE TABLE ... PARTITION(...)
```

优点：

- 同一日期重复执行不会追加重复记录；
- 可以只重建受影响分区；
- 支持补数和回刷；
- 任务失败后可以重新执行当前日期。

需要注意：

> 覆盖写入能够减少追加重复，但不能单独证明重跑前后内容完全一致。

### 13.2 单日运行

```bash
bash run_all_hive.sh 2026-04-08
```

### 13.3 区间回刷

```bash
bash run_backfill_hive.sh 2026-04-01 2026-04-08
```

按日期升序执行，某天失败后停止。

### 13.4 T+1 修正

```bash
bash run_t1_window_hive.sh 2026-04-08
```

自动重跑前一天和当天。

### 13.5 SCD2 历史回刷保护

```bash
bash check_scd2_backfill_guard.sh 2026-04-08
```

规则：

- `bizdate` 等于 `dim_user` 最大分区：允许；
- `bizdate` 晚于最大分区：允许；
- `bizdate` 早于最大分区：阻断并提示区间回刷。

原因：

> 按业务日物化完整历史快照的 SCD2 存在日期依赖。修改历史中间日期后，如果不继续重建后续日期，后续快照可能仍然继承旧状态。

当前保护脚本是独立工具，尚未自动接入 `run_all_hive.sh`。

---

## 14. 幂等性设计

执行：

```bash
bash run_idempotency_check_hive.sh 2026-04-08
```

流程：

```text
采集重跑前快照
→ 执行完整 20 步主链路
→ 采集重跑后快照
→ diff 比较
```

快照同时比较：

```text
row_count
checksum_1
checksum_2
```

指纹采用两组 CRC32 聚合，第二组使用不同字符串组合方向，降低只比较行数或单指纹的漏检风险。

当前覆盖 8 张核心表：

```text
ods_retail_hive
dwd_retail_clean_hive
dws_customer_value_hive
dws_sales_summary_hive
四张核心 ADS
```

未覆盖：

```text
ODS Raw
ODS Reject
质量日志表
星型模型表
```

质量日志表不参与指纹比较，因为 `check_time` 每次运行都会变化。

CRC32 属于工程验收指纹，不是密码学哈希，不能表述为绝对无碰撞。

---

## 15. 日常运行与性能分析

日常执行脚本：

```bash
bash run_daily_hive_profiled.sh 2026-04-08
```

特点：

- 跳过独立建表步骤；
- 默认跳过详细样例和最终结果报告；
- 记录每个步骤耗时；
- 支持从 ODS、DWD、DWS/ADS、星型模型或报告阶段开始。

局部重跑：

```bash
bash run_daily_hive_profiled.sh 2026-04-08 dwd
bash run_daily_hive_profiled.sh 2026-04-08 mart
bash run_daily_hive_profiled.sh 2026-04-08 star
```

输出：

```text
logs/hive_run_*.log
logs/hive_timing_*.tsv
```

这些属于运行产物，不提交仓库。

一次本地单机虚拟机实测：

```text
TOTAL_PIPELINE：1963 秒
```

主要耗时：

```text
星型模型链路                    758 秒
DWS / ADS 结果质量门禁          237 秒
ODS 入仓完整性门禁              151 秒
DWD 质量门禁                    130 秒
国家销售 DWS                    109 秒
```

该耗时受 Hive 执行引擎、MapReduce 作业启动成本、虚拟机资源和磁盘性能影响，不代表生产 SLA。

当前策略是：

- 保留步骤级耗时监控；
- 开发阶段使用局部重跑；
- 优先保证正确性和可维护性；
- 暂不进行高风险的大规模 SQL 合并或调度重写。

---

## 16. Hive SQL 优化实践

### 16.1 数据倾斜

一次分析中：

```text
United Kingdom 约 217 万行
DWD 总记录约 312 万行
占比约 69.6%
```

说明按国家聚合存在热点 Key 风险。

优化：

```text
销售额：
country + salt 局部聚合
→ country 二次汇总

订单数：
country + invoice 去重
→ 按 country 统计

客户数：
country + customerid 去重
→ 按 country 统计
```

订单数和客户数不能简单汇总 Salt 分组中的 `COUNT(DISTINCT)`，否则同一订单或客户可能跨 Salt 重复计算。

### 16.2 MAPJOIN

高价值客户贡献和商品偏好中存在：

```text
DWD 明细大表
JOIN
DWS 客户价值小表
```

SQL 使用：

```sql
/*+ MAPJOIN(...) */
```

减少大表 Shuffle，并通过 `EXPLAIN` 检查 `Map Join Operator`。

### 16.3 分区裁剪

关联时同时限制：

```text
dwd.dt = bizdate
dws.dt = bizdate
```

作用：

- 避免读取其他日期分区；
- 避免跨日期关联导致结果放大；
- 降低扫描量。

### 16.4 聚合空值兜底

`SUM()` 在没有匹配行时可能返回 `NULL`。高价值客户贡献表使用：

```sql
COALESCE(SUM(...), 0)
```

保证无高价值客户日期输出 0，而不是空值。

---

## 17. DolphinScheduler 调度范围

导入文件：

```text
dolphinscheduler/retail_hive_offline_warehouse_daily_demo.json
```

当前 JSON：

- 已通过标准 JSON 解析；
- 包含 12 个任务节点；
- 使用统一占位参数；
- `schedule = null`；
- 导入后需要先修改环境参数，再手动验证并配置定时计划。

当前 12 节点 DAG 包含：

```text
正常 ODS
DWD
DWD 质量门禁
两张 DWS
四张 ADS
最终 Hive 数据质量检查
```

尚未同步到 DAG：

```text
ODS Raw
ODS Reject
ODS 入仓完整性门禁
DWS / ADS 结果门禁
星型模型
星型模型门禁
```

因此：

```text
当前最完整链路 = run_all_hive.sh
当前已验收调度演示 = DolphinScheduler 12 节点 DAG
```

不能将两者描述成完全一致。

---

## 18. 当前已验证结果

### 18.1 当前完整回归

业务日期：

```text
2026-04-08
```

结果：

```text
源表 retail                 3,202,113
ODS Raw                     3,202,113
正常 ODS                    3,202,113
Reject                              0

DWD                         2,416,593
fact_order                  2,416,593
客户                             5,878
商品                             4,630
国家                                41
总销售额                53,230,287.48
高价值客户销售贡献率             86.68%
```

质量结果：

```text
ODS 三组对账差值：0 / 0 / 0
DWD 与事实表行数一致
DWD 与事实表金额一致
STAR_001 - STAR_012 全部 PASS（历史工程验证，当时为12条规则；当前规则定义为 STAR_001 - STAR_017，共 17 条，Canonical 2010-03-04 质量结果为 17/17/17/0）
```

### 18.2 星型模型结果

```text
dim_user：5,878 个版本，5,878 个当前版本
dim_product：4,630 行
dim_date：1 行
dim_geo：41 行
fact_order：2,416,593 行
order_line_id：唯一
```

### 18.3 历史多日验证

仓库保存了较早版本的 7 天验证截图，包括：

- 连续日期分区；
- 区间回刷；
- T+1；
- 幂等性；
- DWD 内容检查。

历史截图曾显示：

```text
ODS 每天 3,202,113
DWD 每天 3,124,956
国家排行每天 43
```

这组历史结果与当前回归的：

```text
DWD 2,416,593
国家 41
```

不是同一数据或清洗规则基线，不能直接比较。

---

## 19. 当前设计边界

当前项目仍有以下边界：

1. 不是 CDC 或实时数仓，而是离线分区重算。
2. ODS Raw 当前每个批次会读取整个 Hive 源表。
3. 当前 canonical 已验收基线 reject=0；新版 Reject 逻辑已支持 4 种日期格式和 6 类技术 Reject，并完成 10 行功能样本验证，但尚未使用新版逻辑对 1,067,371 行 canonical 数据执行完整重跑。
4. 正常 ODS 表注释仍保留早期"原始订单表"措辞，但当前职责已经是类型转换后的正常业务 ODS。
5. Star 历史已连续回刷并验证至 2010-03-04，覆盖 73 个真实业务日期；其中在 2010-03-04 对 customerid=12431 的 Belgium → Australia 真实属性变化进行了重点 SCD2 验证。完整 DWD 保留 604 个真实业务日期。
6. SCD2 历史回刷保护尚未自动接入主入口。
7. 幂等性检查只覆盖 8 张核心 ODS / DWD / DWS / ADS 表。
8. 商品维度来源于交易明细，不是独立主数据系统。
9. DolphinScheduler JSON 尚未同步完整 20 步链路。
10. 轻量 BI Dashboard 只有截图，没有生成脚本。
11. 单机虚拟机完整链路约 30 分钟，尚未深度重构。
12. 项目没有内置 MySQL 到 Hive 的自动同步。
13. Hive ADS 范围写入采用动态分区，一次范围式 ADS DML 覆盖 604 个真实业务日期；脚本仍保留独立的 DWD 前置检查和 ADS 后置验证查询。
14. Hive → MySQL 同步采用范围式一次 Hive 查询 + 批量 MySQL UPSERT，不是逐日同步。
15. 跨系统 DECIMAL 对账需要按数值类型比较，避免 Hive 输出 341.4 与 MySQL DECIMAL 输出 341.40 的字符串格式差异导致假失败。
16. Spring Boot 环比接口当前使用"同一 source_system 下上一可用业务日"语义，不是固定"前一日（date.minusDays(1)）"，以应对真实业务日期存在缺口的情况。

这些边界应在面试和 README 中如实说明。

---

## 20. 推荐的项目表达

建议表述：

> 我没有直接把 MySQL SQL 原样搬到 Hive，而是按照离线数仓重新设计数据入口和分层。源数据先完整写入 ODS Raw，6 类技术解析异常（日期/数量/价格的空值与解析失败）进入 Reject，满足技术解析条件且属于目标业务日的数据进入业务 ODS，并通过三组对账保证没有静默丢数。
>
> DWD 负责清洗有效订单，DWS 和 ADS 形成复用主题和最终指标，随后构建 SCD2 用户维度、其他维表、事实表和星型汇总。
>
> 工程上使用业务日期分区、覆盖写入、区间回刷、T+1、内容指纹幂等性和多层质量门禁。当前 Shell 20 步链路是最完整实现，DolphinScheduler 是已验收的 12 节点调度演示。
>
> 项目已经验证当前业务日的数据对账、事实表一致性和门禁失败路径，Star Schema 已连续验证 73 个真实业务日期及真实属性变化案例，但实时增量、604 日 Star 全量历史验证和完整调度同步仍是后续扩展方向。

不建议表述：

- “这是生产级实时数仓。”
- “每天只读取真正的新增源数据。”
- “Reject 已覆盖全部脏数据。”
- “SCD2 已经完成真实多天属性变化验收。”
- “DolphinScheduler 已经调度当前全部 20 步。”
- “幂等性检查覆盖了所有表。”
- “所有性能问题都已经解决。”

---

## 21. 总结

本次 Hive 迁移的核心不是数据库替换，而是完成以下工程重构：

```text
直接清洗源表
→ Raw 保真、Reject 隔离、正常 ODS 分流

单次 SQL 输出
→ 分区化 DWD / DWS / ADS / 星型模型

人工查看结果
→ 质量日志、断言和非零退出码

单日运行
→ 单日重跑、区间回刷、T+1 和幂等性

普通客户汇总
→ 按业务日物化完整历史快照的 SCD2 和有效期事实关联

只看总耗时
→ 步骤级性能分析和局部重跑
```

当前项目已经形成一条能够完整执行、失败可阻断、结果可追踪、历史可回刷的学习型 Hive 离线数仓链路，同时保留了明确、真实的工程边界。