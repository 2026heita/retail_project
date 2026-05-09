# Hive 迁移项目面试讲解要点

## 1. 项目一句话介绍

本项目是在原 MySQL 零售数据分析项目基础上，将核心数据处理链路迁移到 Hive，构建 ODS、DWD、DWS、ADS 分层离线数仓结构，并补充分区设计、ORC 列式存储、参数化执行脚本和数据质量校验，使项目从基础 SQL 分析升级为具备工程化执行能力的 Hive 离线数仓迁移项目。

## 2. 项目完整介绍

原项目基于 MySQL 完成零售订单数据分析，主要包括订单明细清洗、客户价值分层、国家销售汇总、高价值客户贡献分析、客户层级分布、国家销售排行和高价值客户商品偏好等指标。

在 Hive 迁移过程中，我保留了原 MySQL 版本的业务指标口径，没有重新设计指标逻辑，而是将原有处理链路改造成 Hive 离线数仓分层结构。

迁移后的链路分为四层：

```text
ODS 原始数据层
  ↓
DWD 明细清洗层
  ↓
DWS 主题汇总层
  ↓
ADS 应用指标层
```

其中，ODS 层用于创建并保存原始订单表 `retail`；DWD 层负责清洗订单明细数据；DWS 层沉淀客户价值分层和国家销售汇总等可复用主题结果；ADS 层产出高价值客户贡献、客户分层分布、国家销售排行和高价值客户商品偏好等最终业务指标。

工程化方面，我为 DWD、DWS、ADS 各层 Hive 表统一增加 `dt` 分区，使用 ORC 列式存储，通过 `INSERT OVERWRITE PARTITION` 支持指定日期分区重跑，并通过 `run_all_hive.sh` 串联 ODS、DWD、DWS、ADS 和结果校验完整执行链路。最后补充 `09_check_hive_result.sql`，对分区数据量、DWD 清洗质量、DWS 客户分层边界和 ADS 指标合理性进行校验。

## 3. 项目为什么从 MySQL 迁移到 Hive？

可以这样回答：

> 原 MySQL 版本适合中小规模数据分析和验证业务逻辑，但如果数据量增加，MySQL 在大批量明细数据处理、历史数据分区管理、离线批量重跑和数仓分层组织方面会比较受限。
>
> Hive 更适合离线数仓场景，可以通过分区表管理历史数据，通过 ORC 列式存储提升分析查询效率，并通过 `INSERT OVERWRITE PARTITION` 支持按业务日期覆盖重跑。因此我在保留原业务指标口径的基础上，将核心链路迁移到 Hive。

关键词：

```text
数据量增长
离线批处理
历史分区管理
按天重跑
数仓分层
ORC 列式存储
```

## 4. 为什么要做 ODS、DWD、DWS、ADS 分层？

可以这样回答：

> 分层的目的是让数据处理链路更清楚，减少重复逻辑，提高指标复用性和口径一致性。
>
> ODS 层保留原始订单数据入口；DWD 层保存清洗后的明细数据，保证后续统计基于干净数据；DWS 层沉淀可复用的主题汇总结果，比如客户价值分层、国家销售汇总；ADS 层面向具体业务问题产出最终指标，比如高价值客户销售贡献、客户分层分布、国家销售排行和高价值客户商品偏好。
>
> 如果没有 DWS 层，每个 ADS 表都要重复计算客户价值分层，容易导致口径不一致；如果没有 ODS 层，Hive 版本会默认原始表已经存在，项目链路不够完整。

项目中的分层对应关系：

```text
ODS：
- retail

DWD：
- dwd_retail_clean_hive

DWS：
- dws_customer_value_hive
- dws_sales_summary_hive

ADS：
- ads_high_value_customer_sales_contribution_hive
- ads_customer_level_distribution_hive
- ads_country_sales_rank_hive
- ads_high_value_customer_preference_hive
```

## 5. ODS 层做了什么？

可以这样回答：

> ODS 层主要用于创建并保存原始零售订单表 `retail`，字段结构和 MySQL 原始表保持一致，包括订单编号、商品编码、商品描述、数量、订单时间、价格、客户编号和国家等字段。
>
> 这个表不做复杂清洗，主要作为 Hive 版本的数据入口。后续 DWD 层会基于 ODS 原始表进行过滤和标准化处理。

ODS 表字段：

```text
Invoice
StockCode
Description
Quantity
InvoiceDate
Price
CustomerID
Country
```

补充说明：

> 当前项目没有在 GitHub 仓库中上传完整原始数据集，所以 `00_ods_retail_hive.sql` 主要负责建表。实际运行前需要提前准备好同字段结构的原始订单数据，并导入 Hive 的 `retail` 表。

## 6. DWD 层做了什么？

可以这样回答：

> DWD 层主要负责订单明细数据清洗，保留订单商品明细粒度，同时过滤无效数量、无效价格、空客户 ID 和退货订单，并构造销售金额字段 `amount`。后续 DWS 和 ADS 都基于 DWD 层数据加工，避免直接基于原始脏数据做统计。

核心清洗规则：

```text
quantity > 0
price > 0
customerid IS NOT NULL
invoice NOT LIKE 'C%'
amount = quantity * price
```

面试补充：

> DWD 层没有改变业务粒度，仍然保留订单商品明细粒度，只是完成字段标准化、异常数据过滤和金额字段补充。

## 7. DWS 层做了什么？

可以这样回答：

> DWS 层主要沉淀两个可复用主题汇总结果：客户价值分层和国家销售汇总。
>
> `dws_customer_value_hive` 按客户聚合订单数和累计消费金额，并根据消费金额划分 High Value、Medium Value、Low Value。
>
> `dws_sales_summary_hive` 按国家聚合订单数、客户数、销售额和客单价，为国家销售排行等 ADS 指标提供上游数据。

客户价值分层规则：

```text
High Value：total_spent >= 5000
Medium Value：1000 <= total_spent < 5000
Low Value：total_spent < 1000
```

为什么放在 DWS：

> 因为客户价值分层会被多个 ADS 指标复用，例如高价值客户销售贡献、客户层级分布、高价值客户商品偏好。如果每个 ADS 表都重复计算，会造成重复逻辑和口径不一致。

## 8. ADS 层做了什么？

可以这样回答：

> ADS 层主要面向具体业务分析问题产出结果表。本项目 Hive 版本保留了四张核心 ADS 表，分别分析高价值客户贡献、客户层级分布、国家销售排行和高价值客户商品偏好。

四张 ADS 表：

```text
1. ads_high_value_customer_sales_contribution_hive
   分析高价值客户对平台整体销售额的贡献。

2. ads_customer_level_distribution_hive
   分析不同客户价值层级的客户规模和销售贡献。

3. ads_country_sales_rank_hive
   分析不同国家的销售额排名、订单数、客户数和客单价。

4. ads_high_value_customer_preference_hive
   分析高价值客户更偏好购买哪些商品。
```

业务价值表达：

> 这些 ADS 表不是简单统计总销售额，而是从客户价值、区域市场和核心客户偏好三个角度支撑业务分析。

## 9. 为什么 Hive 版本没有迁移所有 MySQL ADS 指标？

可以这样回答：

> MySQL 版本中 ADS 指标比较多，包括复购率、月度趋势、商品集中度、客户下单频次、高价值客户国家分布等。Hive 迁移阶段我优先迁移了最能体现主线的核心指标，也就是高价值客户销售贡献、客户分层分布、国家销售排行和高价值客户商品偏好。
>
> 这样做的目的是先保证核心链路完整：ODS 原始数据、DWD 清洗、DWS 主题汇总、ADS 核心指标和结果校验都能跑通。后续如果继续扩展，可以按照同样方式把 MySQL 版本中其他 ADS 指标继续迁移到 Hive。

关键词：

```text
核心链路优先
保留主线指标
先保证 ODS-DWD-DWS-ADS 跑通
后续可继续扩展更多 ADS 表
```

## 10. 为什么使用 `dt` 分区？

可以这样回答：

> 零售订单数据天然有业务日期，Hive 迁移后我统一使用 `dt` 作为 DWD、DWS、ADS 各层结果表的分区字段，用来管理不同业务日期的数据。
>
> 这样做有三个好处：第一，每天任务只处理当天分区，避免扫描全量历史数据；第二，如果某天任务失败，可以只重跑指定日期分区；第三，DWD、DWS、ADS 各层都用同一个 `dt`，可以保证上下游业务日期口径一致。

项目中使用：

```sql
PARTITIONED BY (dt STRING)
```

执行时使用：

```bash
sh run_all_hive.sh 2026-04-08
```

SQL 中使用：

```sql
WHERE dt = '${hiveconf:bizdate}'
```

注意点：

> `InvoiceDate` 是订单发生时间，`dt` 是 Hive 分区字段。本项目示例业务日期是 `2026-04-08`，所以对应分区是 `dt='2026-04-08'`。

## 11. 为什么 ODS 表没有设置 `dt` 分区？

可以这样回答：

> 当前项目的 ODS 表主要用于保留原始订单数据入口，重点是补齐 Hive 版本的数据接入层。示例数据本身主要围绕一个业务日期处理，所以当前 ODS 表没有额外设置 `dt` 分区。
>
> 真正用于按业务日期处理和重跑的是 DWD、DWS、ADS 层，这几层都统一使用 `dt` 分区。后续如果扩展为多日期原始数据接入，也可以继续把 ODS 表改造成按 `dt` 分区的原始数据表。

这个回答比较稳，不要硬说 ODS 必须分区。

## 12. 为什么使用 ORC？

可以这样回答：

> 本项目主要是离线分析场景，查询以分组聚合为主，比如按客户、国家、商品统计订单数和销售额。ORC 是 Hive 常用的列式存储格式，适合这类分析查询。
>
> 使用 ORC 可以支持列裁剪和压缩，减少不必要的字段读取和存储开销，所以我在 Hive 的 DWD、DWS、ADS 结果表中统一使用 ORC 存储。

SQL 示例：

```sql
STORED AS ORC
```

注意：

> ORC 不是项目的唯一亮点，真正关键的是它和 Hive 分区、离线聚合查询场景是匹配的。

## 13. 为什么 ODS 表使用 TextFile？

可以这样回答：

> 当前 ODS 表主要作为原始数据入口，用于承接原始 CSV 类订单数据，所以示例中使用 TextFile 建表。DWD、DWS、ADS 层属于清洗后和加工后的结果表，更适合使用 ORC 列式存储。
>
> 也就是说，ODS 更偏原始接入，DWD 之后才是标准化分析数据。如果后续做得更完整，也可以根据数据接入方式把 ODS 改成 ORC 或按日期分区管理。

补充说明：

> 由于原始商品描述字段可能包含英文逗号，实际导入 CSV 时需要注意分隔符解析问题。项目中也提示可以先在 MySQL 或其他工具中清洗后再导入 Hive。

## 14. 为什么使用 `INSERT OVERWRITE`？

可以这样回答：

> 离线数仓任务经常需要重跑指定业务日期分区。如果使用 `INSERT INTO`，重复执行可能产生重复数据。
>
> 所以本项目统一使用 `INSERT OVERWRITE TABLE ... PARTITION`，每次覆盖指定 `dt` 分区，保证任务可重跑和幂等。

SQL 示例：

```sql
INSERT OVERWRITE TABLE dws_customer_value_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT ...
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';
```

关键词：

```text
分区覆盖
指定日期重跑
避免重复数据
任务幂等
```

## 15. 为什么要做 `run_all_hive.sh`？

可以这样回答：

> 单独执行 SQL 文件容易漏步骤，也不方便按日期重跑。因此我增加了 `run_all_hive.sh`，用来串联 ODS、DWD、DWS、ADS 和数据质量校验脚本。
>
> 脚本通过 `bizdate` 参数控制业务日期，每一步执行前会检查 SQL 文件是否存在，每一步执行后会判断返回状态。如果某一步失败，就停止后续任务，避免下游基于错误数据继续产出。

执行方式：

```bash
sh run_all_hive.sh 2026-04-08
```

执行顺序：

```text
00_ods_retail_hive.sql
  ↓
01_dwd_retail_clean_hive.sql
  ↓
02_load_dwd_retail_clean_hive.sql
  ↓
03_dws_customer_value_hive.sql
  ↓
04_dws_sales_summary_hive.sql
  ↓
05_ads_high_value_customer_sales_contribution_hive.sql
  ↓
06_ads_customer_level_distribution_hive.sql
  ↓
07_ads_country_sales_rank_hive.sql
  ↓
08_ads_high_value_customer_preference_hive.sql
  ↓
09_check_hive_result.sql
```

工程化表达：

> 这个脚本体现了完整执行链路、参数化运行、文件存在性检查和失败中断处理。

## 16. 为什么要做数据质量校验？

可以这样回答：

> Hive 任务执行成功不代表数据一定正确，所以我补充了 `09_check_hive_result.sql`。
>
> 校验内容包括分区数据量、DWD 清洗质量、DWS 客户分层边界和 ADS 指标合理性。这样可以避免空分区、清洗逻辑失效、客户分层错误或最终指标异常。

校验内容：

```text
1. 分区数据量校验
   检查各层核心表指定 dt 分区是否有数据。

2. DWD 清洗质量校验
   检查是否仍存在无效数量、无效价格、空客户 ID、退货订单、异常金额。

3. DWS 客户分层校验
   检查客户层级是否为空、是否合法、金额边界是否正确。

4. ADS 指标一致性校验
   检查贡献占比是否在 0 到 100 之间，客户分层占比求和是否接近 100，排行和销售额是否异常。
```

面试加分表达：

> 我没有只看 SQL 是否执行成功，还补充了结果层面的校验，保证下游指标可用。

## 17. 这个项目的核心亮点是什么？

可以这样回答：

> 这个项目的亮点不是简单把 MySQL SQL 改成 Hive SQL，而是做了一次完整的离线数仓迁移设计。
>
> 迁移后项目具备 ODS、DWD、DWS、ADS 分层，`dt` 分区，ORC 存储，`bizdate` 参数化，`INSERT OVERWRITE` 分区覆盖，`run_all_hive.sh` 执行链路和数据质量校验。
>
> 这些设计让项目从基础 SQL 分析升级为具备工程化执行能力的 Hive 离线数仓项目。

可以压缩成一句：

> 保留原业务指标口径的同时，补充分层建模、原始数据入口、分区管理、列式存储、参数化执行、分区重跑和质量校验。

## 18. 如果面试官问：你这个算真实数仓项目吗？

可以这样回答：

> 这个项目是学习型离线数仓迁移项目，不是生产级数仓，但它覆盖了真实数仓开发中的核心思想，包括 ODS、DWD、DWS、ADS 分层，分区表设计，按业务日期重跑，列式存储，任务串联和数据质量校验。
>
> 如果进一步生产化，还可以接入调度系统，比如 DolphinScheduler 或 Airflow，并增加元数据管理、权限控制、任务监控、告警和数据血缘。

这个回答比较稳，不要硬吹生产级。

## 19. 如果面试官问：为什么不继续用 MySQL？

可以这样回答：

> MySQL 更适合事务型存储和中小规模分析，原项目用 MySQL 可以快速验证业务逻辑。
>
> 但当数据量增加后，历史数据管理、按天重跑、批量聚合和分层数仓组织会更适合 Hive。Hive 可以基于 HDFS 存储大规模数据，并通过分区和列式存储优化离线分析任务。

不要说 MySQL 不行，要说场景不同。

## 20. 如果面试官问：为什么 ADS 不直接查 DWD？

可以这样回答：

> 部分 ADS 可以直接查 DWD，但如果所有 ADS 都直接查 DWD，会造成重复计算和口径不统一。
>
> 比如高价值客户定义如果每张 ADS 表都重新计算一次，后期修改规则时容易遗漏。所以我把客户价值分层沉淀到 DWS 层，ADS 层复用这个结果，保证指标口径一致。

关键词：

```text
复用
统一口径
减少重复计算
方便维护
```

## 21. 如果面试官问：高价值客户是怎么定义的？

可以这样回答：

> 本项目根据客户累计消费金额 `total_spent` 定义客户价值层级。累计消费金额大于等于 5000 的客户定义为 High Value，1000 到 5000 之间定义为 Medium Value，低于 1000 定义为 Low Value。
>
> 这个规则沉淀在 `dws_customer_value_hive` 中，后续所有高价值客户相关 ADS 指标都复用该表，避免口径不一致。

规则：

```text
High Value：total_spent >= 5000
Medium Value：1000 <= total_spent < 5000
Low Value：total_spent < 1000
```

## 22. 如果面试官问：国家销售排行为什么用 `RANK()`？

可以这样回答：

> 国家销售排行是按 `total_sales` 降序排序。使用 `RANK()` 可以在销售额相同的情况下给相同名次，比较符合排行榜语义。
>
> 当前任务每次只处理一个 `dt` 分区，所以窗口函数中不需要 `PARTITION BY dt`。如果后续一次处理多天数据，可以改成 `RANK() OVER (PARTITION BY dt ORDER BY total_sales DESC)`，实现每天内部单独排名。

当前写法：

```sql
RANK() OVER (ORDER BY total_sales DESC)
```

多天处理写法：

```sql
RANK() OVER (PARTITION BY dt ORDER BY total_sales DESC)
```

## 23. 如果面试官问：你实际跑过吗？

建议如实回答。

如果你已经跑过：

> 我跑过核心链路，先单独执行 ODS 建表和 DWD 写入，再执行 DWS 和 ADS，最后执行校验脚本。运行过程中重点检查了分区数据量、客户分层结果和 ADS 指标是否正常。

如果你还没完整跑过，不要硬编，可以说：

> 目前 SQL 和执行链路已经整理完成，我会先按单文件分段验证，再执行 `run_all_hive.sh` 跑完整链路。验证重点是 ODS 表是否存在、DWD 分区行数、DWS 客户分层分布、ADS 指标结果和校验脚本输出。

但简历投递前，建议至少跑一遍核心链路。

## 24. 如果面试官问：项目还有哪些可以优化？

可以这样回答：

> 目前项目已经完成 Hive 离线数仓迁移的核心链路。如果继续优化，可以从几个方向做：
>
> 第一，接入调度系统，例如 DolphinScheduler 或 Airflow，实现定时调度和任务依赖管理。
>
> 第二，完善 ODS 层的数据加载方式，比如按业务日期分区接入原始数据，支持多日期批量补数。
>
> 第三，增加数据质量告警，把校验结果异常时输出到日志或通知。
>
> 第四，把 MySQL 版本中更多 ADS 指标继续迁移到 Hive，例如复购率、月度销售趋势、商品销售集中度和客户下单频次分布。
>
> 第五，增加可视化看板，例如使用 Superset 展示核心业务指标。

不要一上来就说“我能做实时数仓”，那样容易被追问爆。

## 25. 简历项目描述版本

可以写成：

```text
零售数据分析项目 MySQL 到 Hive 离线数仓迁移

- 基于零售订单数据，完成订单明细清洗、客户价值分层、国家销售汇总、高价值客户贡献、客户层级分布、国家销售排行和高价值客户商品偏好等指标建设。
- 在原 MySQL 分析项目基础上，将核心处理链路迁移到 Hive，构建 ODS、DWD、DWS、ADS 分层离线数仓结构。
- 设计 `dt` 分区和 ORC 列式存储，使用 `INSERT OVERWRITE PARTITION` 支持指定业务日期分区重跑，避免重复写入。
- 编写 `run_all_hive.sh` 脚本串联 ODS、DWD、DWS、ADS 和数据质量校验流程，通过 `bizdate` 参数实现 SQL 复用。
- 补充 Hive 结果校验脚本，检查分区数据量、DWD 清洗质量、DWS 客户分层边界和 ADS 指标合理性。
```

## 26. 面试时最推荐的 60 秒讲法

可以这样说：

> 我这个项目原来是基于 MySQL 做零售订单数据分析，主要包括订单清洗、客户价值分层、国家销售汇总、高价值客户贡献、客户分层分布、国家销售排行和高价值客户商品偏好等指标。
>
> 后来我把核心链路迁移到了 Hive，按照 ODS、DWD、DWS、ADS 分层重新组织。ODS 层保留原始订单表，DWD 层负责清洗订单明细，DWS 层沉淀客户价值分层和国家销售汇总，ADS 层产出高价值客户贡献、客户分层分布、国家销售排行和商品偏好等最终指标。
>
> 工程化方面，我统一使用 `dt` 分区和 ORC 存储，通过 `INSERT OVERWRITE PARTITION` 支持指定日期重跑，并用 `bizdate` 参数和 `run_all_hive.sh` 串联完整执行链路。最后我还补了数据质量校验脚本，检查分区数据量、清洗质量、客户分层边界和 ADS 指标合理性。
>
> 所以这个项目不是简单写 SQL，而是从 MySQL 分析升级成了一个具备离线数仓分层、分区重跑和结果校验能力的 Hive 迁移项目。

## 27. 面试时不要这么说

避免这些说法：

```text
1. “这个项目就是把 MySQL 改成 Hive。”
   太弱，听起来像 SQL 翻译。

2. “这是生产级数仓项目。”
   容易被追问调度、监控、权限、血缘、元数据，扛不住。

3. “Hive 比 MySQL 更高级。”
   不准确。应该说适用场景不同。

4. “我用了 ORC 所以查询一定很快。”
   太绝对。应该说 ORC 更适合 Hive 离线分析场景。

5. “所有表都必须分区。”
   太绝对。应该说本项目按业务日期处理，DWD、DWS、ADS 核心结果表统一使用 dt 分区。

6. “我没有跑过，但是应该能跑。”
   很危险。至少跑核心链路，或者如实说正在分阶段验证。
```

## 28. 面试前自查清单

面试前检查：

```text
1. 是否能说清楚 ODS、DWD、DWS、ADS 各自作用？
2. 是否能说清楚为什么用 dt 分区？
3. 是否能说清楚为什么 ODS 表当前没有设置 dt 分区？
4. 是否能说清楚为什么用 ORC？
5. 是否能说清楚为什么用 INSERT OVERWRITE？
6. 是否能说清楚 run_all_hive.sh 的作用？
7. 是否能说清楚数据质量校验查了什么？
8. 是否能说清楚高价值客户的定义？
9. 是否能说清楚 ADS 四张表各自回答什么业务问题？
10. 是否能说清楚 MySQL 和 Hive 在本项目中的区别？
11. 是否至少跑过核心 SQL，或者准备好运行验证计划？
```

## 29. 最终记忆版

最短记忆：

```text
MySQL 原项目负责零售数据分析。
Hive 迁移后分为 ODS、DWD、DWS、ADS 四层。
ODS 保留原始订单表 retail。
DWD 清洗订单明细。
DWS 沉淀客户价值分层和国家销售汇总。
ADS 产出高价值客户贡献、客户分层分布、国家排行、商品偏好。
DWD、DWS、ADS 统一 dt 分区、ORC 存储、INSERT OVERWRITE 分区覆盖。
run_all_hive.sh 负责按 bizdate 串联执行。
09_check_hive_result.sql 负责结果校验。
项目亮点是从基础 SQL 分析升级为离线数仓工程化迁移。
```