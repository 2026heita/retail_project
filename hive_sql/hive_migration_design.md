# Hive 迁移设计说明（整理版）

## 1. 项目定位

本项目是在原 MySQL 零售数据分析项目基础上，将核心数据处理链路迁移到 Hive，形成一套学习型但工程表达完整的离线数仓项目。

项目分为两条链路：

1. **主链路：ODS -> DWD -> DWS -> ADS**
   - 对应文件：`00` 到 `09`，外加 `10_check_ods_retail_hive.sql` 和 `23-25` 质量日志模块文件。
   - 入口脚本：`run_all_hive.sh`。
   - 这是项目投简历和面试讲解时的主线。

2. **扩展链路：星型模型建模**
   - 对应文件：`11` 到 `22`。
   - 入口脚本：`run_star_schema_hive.sh`。
   - 用于补充展示维度建模能力，包括用户维度、商品维度、日期维度、地理维度、订单事实表和星型模型客户价值汇总表。

---

## 2. 为什么保留 00-09 主链路

`00-09` 是最完整、最稳定的 Hive 离线数仓主链路：

```text
retail 源表
  ↓
ods_retail_hive
  ↓
dwd_retail_clean_hive
  ↓
├── quality_log_hive
├── dws_customer_value_hive
├── dws_sales_summary_hive
  ↓
├── ads_high_value_customer_sales_contribution_hive
├── ads_customer_level_distribution_hive
├── ads_country_sales_rank_hive
└── ads_high_value_customer_preference_hive
```

它体现了离线数仓最核心的工程能力：

- ODS、DWD、DWS、ADS 分层。
- `dt` 业务日期分区。
- ORC 列式存储。
- `INSERT OVERWRITE PARTITION` 分区覆盖写入。
- 使用 `bizdate` 参数复用 SQL。
- 支持单日重跑、区间回刷和 T+1 修正窗口。
- 有 ODS 入仓校验、DWD 质量日志落表和最终结果校验。

因此，`run_all_hive.sh` 继续保留并作为主执行脚本。

---

## 3. 主链路执行顺序

```text
00_ods_retail_hive.sql
00_load_ods_retail_hive.sql
10_check_ods_retail_hive.sql
01_dwd_retail_clean_hive.sql
02_load_dwd_retail_clean_hive.sql
23_quality_log_hive.sql
24_load_quality_log_hive.sql
03_dws_customer_value_hive.sql
04_dws_sales_summary_hive.sql
05_ads_high_value_customer_sales_contribution_hive.sql
06_ads_customer_level_distribution_hive.sql
07_ads_country_sales_rank_hive.sql
08_ads_high_value_customer_preference_hive.sql
09_check_hive_result.sql
```

执行方式：

```bash
sh run_all_hive.sh 2026-04-08
```

`10_check_ods_retail_hive.sql` 放在 ODS 加载之后，用来先确认 ODS 分区有数据、核心字段正常、日期可以解析，再继续进入 DWD 清洗和后续 DWS/ADS 产出。

---

## 4. 伪增量、回刷和 T+1

本项目中的“伪增量”指的是：每天只处理指定 `bizdate` 的数据，并通过 `INSERT OVERWRITE TABLE ... PARTITION(dt='${hiveconf:bizdate}')` 覆盖当天分区。

这样做的好处是：

- 同一天重复执行不会产生重复数据。
- 某天数据异常时可以只重跑当天分区。
- 区间回刷可以按天循环覆盖多个分区。
- T+1 修正窗口可以自动回刷前一天和当天分区。

相关脚本：

```text
run_all_hive.sh        单日主链路
run_backfill_hive.sh   日期区间回刷
run_t1_window_hive.sh  T+1 修正窗口
```

---

## 5. 数据质量日志模块

在主链路中补充了一个最小版本的数据质量日志模块，用于记录核心表的质量检查结果。

相关文件：

```text
23_quality_log_hive.sql        创建质量检查日志表 quality_log_hive
24_load_quality_log_hive.sql   写入 DWD 清洗质量检查结果
25_check_quality_log_hive.sql  查看指定业务日期的质量检查日志
```

当前质量模块不做复杂规则系统，只记录最核心的检查结果，包括被检查表名、检查项、异常数量、检查状态、检查时间和业务日期分区。

主链路在 DWD 清洗完成后写入质量日志。当前主要检查 DWD 层是否仍存在无效数量、无效价格和空客户 ID 等异常数据。`abnormal_cnt = 0` 表示检查通过，状态记为 `PASS`；否则状态记为 `FAIL`。

这个设计的作用是把原来只在控制台输出的质量检查结果沉淀到 Hive 表中，方便后续按业务日期追踪数据质量，也方便调度平台或验收截图查看。

---

## 6. 星型模型扩展链路

`11-22` 是在 DWD 清洗明细基础上补充的星型模型扩展，不替代主链路。

```text
dwd_retail_clean_hive
  ↓
├── dim_user
├── dim_product
├── dim_date
├── dim_geo
  ↓
fact_order
  ↓
dws_customer_value_star_hive
```

入口脚本：

```bash
sh run_star_schema_hive.sh 2026-04-08
```

整理后，星型模型链路做了这些修正：

1. `dim_user` 使用稳定的 `user_id = md5(customerid|country)`，不再拼接 `bizdate`。
2. `dim_user`、`dim_product`、`dim_date`、`dim_geo` 都增加 `dt` 分区，作为每日维度快照，避免覆盖历史分区。
3. `fact_order` 保留订单明细粒度，增加 `order_line_id` 作为订单明细代理键，并在关联维表时使用当前 `bizdate` 分区。
4. 星型模型的客户价值汇总表改名为 `dws_customer_value_star_hive`，避免和主链路 `dws_customer_value_hive` 表名和结构冲突。
5. 星型模型客户价值层级口径与主链路保持一致：`High Value`、`Medium Value`、`Low Value`。

---

## 7. 多天运行能力验证

为避免项目只停留在单日样例，本项目已将源表扩展为 `2026-04-01` 到 `2026-04-07` 共 7 天连续业务日期数据，并完成主链路跨天验证。

验证命令：

```bash
sh run_backfill_hive.sh 2026-04-01 2026-04-07
sh run_all_hive.sh 2026-04-03
sh run_t1_window_hive.sh 2026-04-07
```

验证结果：

```text
ODS 分区：7 天每天 3,202,113 行
DWD 分区：7 天每天 3,124,956 行
ADS 国家排行：7 天每天 43 行
单日幂等性：重复执行 2026-04-03 后结果行数保持一致
T+1 窗口：回刷 2026-04-06 和 2026-04-07 后结果稳定
```

这说明 `bizdate` 参数、`dt` 分区、`INSERT OVERWRITE PARTITION`、区间回刷和 T+1 修正窗口在跨天场景下可以稳定工作。多天验证结果也为后续调度、质量校验和回刷机制提供了运行证据。


---

## 8. 面试时如何说明两条链路

建议这样说：

> 我项目的主链路是 00-09 的 ODS、DWD、DWS、ADS 分层 Hive 离线数仓，支持按 `bizdate` 分区覆盖写入，也就是伪增量处理。基于这个主链路，我实现了单日执行、区间回刷和 T+1 修正窗口。后续我又补充了 11-22 的星型模型扩展，基于 DWD 构建用户、商品、日期、地理维度、订单事实表和星型模型客户价值汇总表，用来展示维度建模能力。两条链路定位不同：00-09 是主链路，11-22 是扩展建模链路。为了验证它不是单日样例，我还构造了 7 天连续业务日期数据，完成区间回刷、单日幂等性、质量日志落表和 T+1 窗口验证。

---

## 9. 不建议的说法

不要说：

- “11-22 是替代 00-09 的新版链路。”
- “这是生产级实时数仓。”
- “用户维度已经实现完整生产级 SCD2。”

更准确的说法是：

- “00-09 是主链路。”
- “11-22 是星型模型扩展。”
- “用户维度保留 SCD2 字段，并用每日快照方式表达简化 SCD2 思路，当前项目没有使用 Hive ACID UPDATE。”
- “本项目是学习型离线数仓项目，但覆盖了分层、分区、幂等重跑、回刷、T+1 修正、结果校验和调度编排等核心工程表达。”
