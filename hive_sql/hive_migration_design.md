# Hive 迁移设计说明

## 1. 项目背景

本项目原始版本基于 MySQL 实现零售业务数据分析，主要围绕订单明细清洗、客户价值分层、国家销售汇总、高价值客户贡献分析、客户分层分布、国家销售排行和高价值客户商品偏好等指标展开。

随着数据量增加，单机 MySQL 在大批量明细数据处理、历史分区管理、离线批量重跑和多层数仓组织方面存在一定局限。因此，本项目在保留原有业务指标口径的基础上，将核心数仓链路迁移到 Hive，形成基于 ODS、DWD、DWS、ADS 分层的离线数仓处理流程。

本次迁移不是重新设计业务指标，而是在原有 MySQL 指标逻辑基础上，完成 Hive ODS 原始表设计、DWD 清洗表设计、DWS 汇总表设计、ADS 指标表设计、分区设计、列式存储设计、批量写入方式改造、执行脚本串联和结果校验补充，从而提升项目的工程化程度和离线数仓表达能力。

## 2. 原 MySQL 数仓链路

原 MySQL 版本主要包括以下处理链路：

```text
原始零售订单数据 retail
        ↓
数据清洗表 retail_clean / retail_clean2
        ↓
DWS 汇总层
    - dws_customer_value
    - dws_sales_summary
        ↓
ADS 应用层指标
    - ads_repeat_purchase_summary
    - ads_monthly_sales_trend
    - ads_monthly_sales_growth
    - ads_country_sales_rank
    - ads_high_value_customers
    - ads_top10_products
    - ads_customer_revenue_concentration
    - ads_country_value_analysis
    - ads_customer_level_distribution
    - ads_product_sales_concentration
    - ads_customer_order_frequency
    - ads_high_value_customer_preference
    - ads_high_value_customer_order_frequency
    - ads_high_value_customer_country_distribution
    - ads_high_value_customer_sales_contribution
```

其中，`retail_clean2` 主要负责剔除异常订单和构造销售金额字段；`dws_customer_value` 负责按客户聚合订单数和累计消费金额，并根据消费金额划分 High Value、Medium Value、Low Value；`dws_sales_summary` 负责按国家汇总订单数、客户数、销售额和客单价。

ADS 层则基于 DWD 和 DWS 层结果继续加工，形成面向业务分析的结果表，例如复购率、月度趋势、国家销售排行、客户收入集中度、客户分层分布、高价值客户销售贡献和高价值客户商品偏好分析等。

## 3. Hive 迁移目标

本次 Hive 迁移主要目标如下：

1. 保留原 MySQL 版本的核心业务指标口径，保证迁移前后分析逻辑一致。
2. 将原 MySQL 单库单表处理方式改造为 Hive 离线数仓分层结构。
3. 增加 Hive ODS 原始订单表，保留原始订单数据入口。
4. 使用 `dt` 分区字段管理业务日期，支持指定日期分区重跑。
5. 使用 ORC 列式存储格式，提高离线分析场景下的读取效率。
6. 使用 `INSERT OVERWRITE PARTITION` 写入方式，支持分区级覆盖和任务重跑。
7. 增加统一执行脚本 `run_all_hive.sh`，串联 ODS、DWD、DWS、ADS 和数据质量校验。
8. 增加结果校验脚本，检查分区数据量、清洗质量、客户分层边界和 ADS 指标合理性。

## 4. Hive 分层设计

Hive 迁移后，项目采用 ODS、DWD、DWS、ADS 四层结构组织数据处理链路。

```text
ODS 原始订单表
        ↓
DWD 明细清洗层
        ↓
DWS 主题汇总层
        ↓
ADS 应用指标层
        ↓
数据质量校验与结果检查
```

### 4.1 ODS 原始数据层

ODS 层用于保存原始零售订单数据，对应文件为：

```text
hive_sql/00_ods_retail_hive.sql
```

ODS 层核心表为：

```sql
retail
```

该表主要保存原始订单明细字段，包括：

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

ODS 层的作用是保留原始数据入口，为后续 DWD 清洗层提供数据来源。当前项目不在仓库中上传完整原始数据文件，因此 `00_ods_retail_hive.sql` 主要负责创建 Hive 原始订单表。如果 Hive 中已经提前准备好 `retail` 表，可以重复执行该脚本，不会覆盖已有表结构。

需要注意的是，如果使用普通 CSV 文件直接加载数据，且 `Description` 字段中包含英文逗号，普通逗号分隔方式可能导致字段解析异常。因此在实际运行时，可以先在 MySQL 或其他工具中完成数据准备，再导入 Hive 表。

### 4.2 DWD 明细清洗层

DWD 层用于保存清洗后的订单明细数据，对应文件为：

```text
hive_sql/01_dwd_retail_clean_hive.sql
hive_sql/02_load_dwd_retail_clean_hive.sql
```

DWD 层核心表为：

```sql
dwd_retail_clean_hive
```

该表主要完成以下工作：

1. 保留订单明细粒度数据。
2. 过滤无效数量、无效价格、空客户 ID 和退货订单。
3. 构造销售金额字段 `amount`。
4. 按业务日期 `dt` 进行分区。
5. 为后续 DWS 和 ADS 层提供统一、干净的明细数据来源。

DWD 层是整个 Hive 数仓链路的基础，后续客户价值分层、国家销售汇总、高价值客户分析等指标都基于该层数据生成。

DWD 层清洗规则与 MySQL 版本保持一致：

```sql
Quantity > 0
Price > 0
CustomerID IS NOT NULL
Invoice NOT LIKE 'C%'
```

销售金额字段计算方式为：

```sql
amount = ROUND(Quantity * Price, 2)
```

### 4.3 DWS 主题汇总层

DWS 层用于沉淀可复用的主题汇总结果。本项目保留两张核心 DWS 表：

```text
hive_sql/03_dws_customer_value_hive.sql
hive_sql/04_dws_sales_summary_hive.sql
```

对应 Hive 表为：

```sql
dws_customer_value_hive
dws_sales_summary_hive
```

#### 4.3.1 客户价值分层表

`dws_customer_value_hive` 基于 DWD 明细表按客户聚合，统计每个客户的订单数和累计消费金额，并根据累计消费金额划分客户价值层级：

```text
High Value：total_spent >= 5000
Medium Value：1000 <= total_spent < 5000
Low Value：total_spent < 1000
```

该表是后续高价值客户贡献分析、客户分层分布、高价值客户商品偏好分析的公共上游。

将客户价值分层放在 DWS 层，而不是在每张 ADS 表中重复计算，可以减少重复逻辑，并保证不同 ADS 指标使用同一套客户分层口径。

#### 4.3.2 国家销售汇总表

`dws_sales_summary_hive` 基于 DWD 明细表按国家聚合，统计不同国家的订单数、客户数、销售额和客单价。

该表为 ADS 国家销售排行表提供上游数据，也可以用于后续区域市场分析、国家销售贡献分析和国际市场运营分析。

### 4.4 ADS 应用指标层

ADS 层用于产出面向具体业务问题的最终指标表。本项目 Hive 版本保留四张核心 ADS 表：

```text
hive_sql/05_ads_high_value_customer_sales_contribution_hive.sql
hive_sql/06_ads_customer_level_distribution_hive.sql
hive_sql/07_ads_country_sales_rank_hive.sql
hive_sql/08_ads_high_value_customer_preference_hive.sql
```

对应 Hive 表为：

```sql
ads_high_value_customer_sales_contribution_hive
ads_customer_level_distribution_hive
ads_country_sales_rank_hive
ads_high_value_customer_preference_hive
```

#### 4.4.1 高价值客户销售贡献表

`ads_high_value_customer_sales_contribution_hive` 用于统计高价值客户人数、订单数、销售额、平台总销售额、销售贡献占比、人均销售额和人均订单数。

该表回答的问题是：

```text
高价值客户对平台整体销售额贡献多少？
```

该表复用 DWS 层的客户价值分层结果，避免在 ADS 层重复定义高价值客户口径。

#### 4.4.2 客户价值分层分布表

`ads_customer_level_distribution_hive` 用于统计 High Value、Medium Value、Low Value 三类客户的客户数、销售额、客户数占比和销售额占比。

该表回答的问题是：

```text
不同客户价值层级的客户规模和销售贡献分别是多少？
```

该表可以用于分析客户结构是否健康，以及平台收入是否过度依赖少数高价值客户。

#### 4.4.3 国家销售排行表

`ads_country_sales_rank_hive` 基于 `dws_sales_summary_hive` 生成国家销售排行，按销售额对国家进行排名，同时保留订单数、客户数、销售额和客单价。

该表回答的问题是：

```text
哪些国家或地区销售表现最好？
```

该表适合用于区域市场分析和销售看板展示。

#### 4.4.4 高价值客户商品偏好表

`ads_high_value_customer_preference_hive` 基于客户价值分层结果和 DWD 订单明细，统计高价值客户购买商品的客户数、订单数、购买数量、销售额和销售额排名。

该表回答的问题是：

```text
高价值客户更偏好购买哪些商品？
```

相比普通商品销量排行，该表聚焦核心客户群体，更能体现客户精细化运营分析价值。

### 4.5 分层链路总结

整体 Hive 分层链路如下：

```text
retail
  ↓
dwd_retail_clean_hive
  ↓
  ├── dws_customer_value_hive
  │       ├── ads_high_value_customer_sales_contribution_hive
  │       ├── ads_customer_level_distribution_hive
  │       └── ads_high_value_customer_preference_hive
  │
  └── dws_sales_summary_hive
          └── ads_country_sales_rank_hive
```

通过该分层设计，项目实现了从原始数据接入、明细清洗、主题汇总到业务指标输出的完整离线数仓链路。

## 5. 分区设计

### 5.1 分区字段选择

Hive 迁移后，DWD、DWS、ADS 各层核心结果表统一使用 `dt` 作为分区字段：

```sql
PARTITIONED BY (dt STRING)
```

`dt` 表示业务日期。本项目原始订单时间字段为 `InvoiceDate`，当前示例业务日期为：

```text
2026-04-08
```

在工程化执行脚本中，`dt` 不再写死，而是通过 `bizdate` 参数传入：

```bash
sh run_all_hive.sh 2026-04-08
```

SQL 中统一使用：

```sql
'${hiveconf:bizdate}'
```

示例：

```sql
INSERT OVERWRITE TABLE dws_customer_value_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    customerid,
    COUNT(DISTINCT invoice) AS order_count,
    CAST(ROUND(SUM(amount), 2) AS DECIMAL(12,2)) AS total_spent,
    CASE
        WHEN SUM(amount) >= 5000 THEN 'High Value'
        WHEN SUM(amount) >= 1000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_level
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
GROUP BY customerid;
```

### 5.2 为什么使用 `dt` 分区

使用 `dt` 分区主要有以下原因：

1. 支持按业务日期管理数据。
2. 支持指定日期分区重跑。
3. 避免每次任务扫描全表。
4. 方便 DWD、DWS、ADS 各层按同一业务日期对齐。
5. 方便后续接入调度系统或定时任务。

例如，当需要重跑 `2026-04-08` 的数据时，只需要覆盖该日期分区：

```sql
INSERT OVERWRITE TABLE ads_country_sales_rank_hive
PARTITION (dt = '${hiveconf:bizdate}')
...
WHERE dt = '${hiveconf:bizdate}';
```

这样可以避免 `INSERT INTO` 追加导致重复数据，也避免全表重算带来的额外成本。

### 5.3 分区设计原则

本项目分区设计遵循以下原则：

1. ODS 层保存原始订单表，当前示例中不额外设置 `dt` 分区。
2. DWD、DWS、ADS 统一使用 `dt` 分区，保证上下游日期口径一致。
3. 上游读取和下游写入必须使用同一个 `bizdate`。
4. ADS 表不单独重新定义日期逻辑，而是继承上游 DWD / DWS 的业务日期。
5. 对于单日离线任务，采用静态分区写入。
6. 对于重跑任务，使用 `INSERT OVERWRITE` 覆盖指定分区。

## 6. 存储格式选择

### 6.1 存储格式

Hive 迁移后，DWD、DWS、ADS 各层结果表统一采用 ORC 列式存储：

```sql
STORED AS ORC
```

示例：

```sql
CREATE TABLE IF NOT EXISTS dws_sales_summary_hive (
    country STRING,
    total_orders BIGINT,
    total_customers BIGINT,
    total_sales DECIMAL(14,2),
    avg_order_value DECIMAL(14,2)
)
PARTITIONED BY (dt STRING)
STORED AS ORC;
```

ODS 原始订单表 `retail` 当前使用 TextFile 作为示例存储格式，主要用于保留原始数据入口。DWD、DWS、ADS 结果表则统一使用 ORC，以适配离线聚合分析场景。

### 6.2 为什么选择 ORC

本项目选择 ORC 的原因如下：

1. ORC 是 Hive 场景中常用的列式存储格式。
2. 适合离线分析场景下的大批量聚合查询。
3. 支持列裁剪，查询少量字段时可以减少不必要的读取。
4. 支持压缩，能够减少存储空间。
5. 与 Hive 分区表结合使用，适合 DWD、DWS、ADS 分层数仓结果表。

本项目中的查询以聚合统计为主，例如按客户、国家、商品进行分组统计。相比行式存储，列式存储更适合这类分析场景。

### 6.3 与原 MySQL 存储方式的区别

原 MySQL 版本主要依赖关系型数据库表进行存储和查询，更适合中小规模数据分析和交互式查询。

Hive 迁移后，数据以 Hive 表、分区和 ORC 文件形式存储，更适合离线批处理场景。Hive 版本不追求单条记录的高频更新，而是按业务日期批量写入和覆盖分区。

因此，本项目从 MySQL 迁移到 Hive 后，处理方式从：

```text
单机数据库表查询
```

转变为：

```text
分布式离线数仓批处理
```

## 7. 全量与增量设计

### 7.1 当前项目处理方式

本项目当前 Hive 迁移版本以单日分区处理为主。

实际执行时，通过 `bizdate` 参数指定业务日期：

```bash
sh run_all_hive.sh 2026-04-08
```

DWD、DWS、ADS 表均围绕该业务日期进行处理：

```sql
WHERE dt = '${hiveconf:bizdate}'
```

并写入对应目标分区：

```sql
PARTITION (dt = '${hiveconf:bizdate}')
```

ODS 表 `retail` 作为原始数据入口，当前示例中不按日期分区。DWD 层负责将原始订单数据清洗后写入指定 `dt` 分区。

### 7.2 全量处理设计

全量处理适用于以下场景：

1. 首次初始化 Hive 数仓。
2. 原始数据重新导入。
3. 清洗逻辑或指标口径发生变化。
4. 需要重算全部历史数据。

全量处理可以按历史日期逐个分区重跑，也可以在数据量较小时直接重建目标表。

本项目中，如果需要全量重跑，可以按日期循环调用：

```bash
sh run_all_hive.sh 2026-04-08
```

如果后续有多天数据，可以扩展为：

```bash
sh run_all_hive.sh 2026-04-08
sh run_all_hive.sh 2026-04-09
sh run_all_hive.sh 2026-04-10
```

### 7.3 增量处理设计

增量处理适用于每日新增订单数据的场景。

每日任务只处理当天业务日期的数据，例如：

```bash
sh run_all_hive.sh 2026-04-08
```

任务执行时：

1. ODS 层提供原始订单数据入口。
2. DWD 层读取原始订单数据并写入当天 DWD 分区。
3. DWS 层读取当天 DWD 分区并写入当天 DWS 分区。
4. ADS 层读取当天 DWS / DWD 分区并写入当天 ADS 分区。
5. 校验脚本检查当天各层结果是否正常。

这种方式避免每次扫描全部历史数据，更符合离线数仓按天批处理的方式。

### 7.4 为什么使用 `INSERT OVERWRITE`

本项目统一使用：

```sql
INSERT OVERWRITE TABLE table_name
PARTITION (dt = '${hiveconf:bizdate}')
```

原因如下：

1. 支持指定分区重跑。
2. 避免重复执行时产生重复数据。
3. 适合离线批处理任务的幂等执行。
4. 当某天数据异常时，可以修复上游后重新覆盖该日期分区。
5. 比 `INSERT INTO` 更适合 DWD、DWS、ADS 结果表的每日批量产出。

例如：

```sql
INSERT OVERWRITE TABLE ads_customer_level_distribution_hive
PARTITION (dt = '${hiveconf:bizdate}')
SELECT
    ...
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}';
```

重复执行同一天任务时，目标分区会被覆盖，而不是追加重复数据。

## 8. 执行链路设计

### 8.1 执行脚本

Hive 迁移后，项目增加统一执行脚本：

```text
hive_sql/run_all_hive.sh
```

该脚本用于按顺序执行 ODS、DWD、DWS、ADS 和结果校验脚本。

执行方式：

```bash
sh run_all_hive.sh 2026-04-08
```

其中，`2026-04-08` 为业务日期参数。

### 8.2 执行顺序

脚本执行顺序如下：

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

对应完整链路为：

```text
ODS 原始表建表
  ↓
DWD 清洗表建表
  ↓
DWD 清洗明细写入
  ↓
DWS 客户价值分层
  ↓
DWS 国家销售汇总
  ↓
ADS 高价值客户销售贡献
  ↓
ADS 客户分层分布
  ↓
ADS 国家销售排行
  ↓
ADS 高价值客户商品偏好
  ↓
结果校验
```

### 8.3 参数传递方式

脚本通过 `--hiveconf` 向 Hive SQL 传入业务日期：

```bash
hive --hiveconf bizdate=${BIZDATE} -f 03_dws_customer_value_hive.sql
```

SQL 文件中通过以下方式引用：

```sql
'${hiveconf:bizdate}'
```

例如：

```sql
WHERE dt = '${hiveconf:bizdate}'
```

这样可以避免在每个 SQL 文件中写死日期，提高脚本复用性。

### 8.4 失败处理

`run_all_hive.sh` 中每一步执行完成后都会判断返回状态。如果某一层执行失败，脚本会立即停止，不再继续执行下游任务。

示例逻辑如下：

```bash
if [ $? -ne 0 ]; then
  echo "ERROR: current sql failed"
  exit 1
fi
```

这样可以避免 ODS、DWD 或 DWS 层出错后，ADS 层继续基于错误数据产出结果。

## 9. 数据质量校验设计

### 9.1 校验脚本

本项目增加 Hive 结果校验脚本：

```text
hive_sql/09_check_hive_result.sql
```

该脚本用于检查 DWD、DWS、ADS 各层核心结果是否正常。

### 9.2 分区数据量校验

首先检查各层核心表在指定业务日期下是否有数据：

```sql
SELECT 'dwd_retail_clean_hive' AS table_name, COUNT(*) AS row_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}';
```

需要检查的表包括：

```text
dwd_retail_clean_hive
dws_customer_value_hive
dws_sales_summary_hive
ads_high_value_customer_sales_contribution_hive
ads_customer_level_distribution_hive
ads_country_sales_rank_hive
ads_high_value_customer_preference_hive
```

如果某张表对应分区行数为 0，说明该层可能没有正常产出。

### 9.3 DWD 清洗质量校验

DWD 层主要检查清洗后的明细表中是否仍存在异常数据：

1. `quantity <= 0`
2. `price <= 0`
3. `customerid IS NULL`
4. `invoice LIKE 'C%'`
5. `amount IS NULL OR amount <= 0`

示例：

```sql
SELECT
    'dwd_invalid_quantity_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dwd_retail_clean_hive
WHERE dt = '${hiveconf:bizdate}'
  AND quantity <= 0;
```

正常情况下，异常数量应该为 0。

### 9.4 DWS 客户分层校验

DWS 层主要检查客户价值分层是否完整、合法、符合边界规则。

客户分层规则为：

```text
High Value：total_spent >= 5000
Medium Value：1000 <= total_spent < 5000
Low Value：total_spent < 1000
```

校验内容包括：

1. 是否存在空分层。
2. 是否存在非法分层值。
3. High Value 客户是否满足金额边界。
4. Medium Value 客户是否满足金额边界。
5. Low Value 客户是否满足金额边界。

示例：

```sql
SELECT
    'dws_invalid_customer_level_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM dws_customer_value_hive
WHERE dt = '${hiveconf:bizdate}'
  AND customer_level NOT IN ('High Value', 'Medium Value', 'Low Value');
```

### 9.5 ADS 指标一致性校验

ADS 层主要检查最终指标是否处于合理范围内。

校验内容包括：

1. 高价值客户销售贡献占比是否在 0 到 100 之间。
2. 客户分层分布表的客户数占比求和是否接近 100。
3. 客户分层分布表的销售额占比求和是否接近 100。
4. 国家销售排行是否存在空排名。
5. 国家销售排行是否存在异常销售额。
6. 高价值客户商品偏好表是否存在空排名。
7. 高价值客户商品偏好表是否存在异常销售额或异常购买数量。

示例：

```sql
SELECT
    'ads_high_value_sales_contribution_pct_error_cnt' AS check_item,
    COUNT(*) AS abnormal_cnt
FROM ads_high_value_customer_sales_contribution_hive
WHERE dt = '${hiveconf:bizdate}'
  AND (sales_contribution_pct < 0 OR sales_contribution_pct > 100);
```

通过这些校验，可以避免任务虽然执行成功，但最终 ADS 指标不可用的问题。

## 10. 项目亮点总结

本次 Hive 迁移主要体现以下项目亮点：

### 10.1 保留原业务指标口径

迁移过程中没有随意修改原 MySQL 版本的业务指标逻辑，而是在原有客户价值分层、国家销售汇总、高价值客户贡献分析等指标基础上进行 Hive 化改造，保证迁移前后指标口径一致。

### 10.2 建立离线数仓分层结构

项目从原 MySQL 的单库表分析方式升级为 Hive 数仓分层结构：

```text
ODS 原始数据层
  ↓
DWD 明细清洗层
  ↓
DWS 主题汇总层
  ↓
ADS 应用指标层
```

该结构更符合离线数仓项目的组织方式，也方便后续扩展更多主题指标。

### 10.3 使用 `dt` 分区支持按天重跑

DWD、DWS、ADS 各层表统一使用 `dt` 分区，并通过 `bizdate` 参数控制业务日期。

这样可以支持指定日期重跑，避免每次处理全量历史数据。

### 10.4 使用 ORC 列式存储

Hive DWD、DWS、ADS 结果表统一采用 ORC 存储格式，适合离线分析场景下的聚合查询。

对于按客户、国家、商品进行分组统计的业务场景，ORC 列式存储能够更好地适配 Hive 分析查询。

### 10.5 使用 `INSERT OVERWRITE` 保证幂等性

各层结果表统一采用 `INSERT OVERWRITE PARTITION` 写入方式，支持分区级覆盖。

当某天任务失败或指标逻辑调整时，可以重新执行对应业务日期任务，不会产生重复数据。

### 10.6 增加统一执行链路

通过 `run_all_hive.sh` 串联 ODS、DWD、DWS、ADS 和结果校验脚本，形成完整执行链路。

脚本支持业务日期参数，并且每一步执行失败后会停止后续任务，避免错误数据继续向下游扩散。

### 10.7 增加数据质量校验

项目增加 `09_check_hive_result.sql`，对分区数据量、DWD 清洗质量、DWS 客户分层边界和 ADS 指标合理性进行校验。

这使项目不只是完成 SQL 迁移，而是具备基本的数据质量意识和工程化检查能力。

## 11. 项目说明与答辩要点

本项目可以概括为：

> 我在原 MySQL 零售数据分析项目基础上，完成了一版 Hive 离线数仓迁移。迁移时保留原有业务指标口径，将数据处理链路拆分为 ODS、DWD、DWS、ADS 四层。ODS 层负责保存原始订单表，DWD 层负责订单明细清洗，DWS 层沉淀客户价值分层和国家销售汇总，ADS 层产出高价值客户贡献、客户层级分布、国家销售排行和高价值客户商品偏好等业务指标。  
>  
> 工程化方面，我为 DWD、DWS、ADS 各层表统一增加 `dt` 分区和 ORC 列式存储，通过 `INSERT OVERWRITE PARTITION` 支持指定日期重跑，并使用 `run_all_hive.sh` 串联 ODS、DWD、DWS、ADS 和结果校验流程。最后补充了 Hive 结果校验脚本，检查分区数据量、清洗质量、客户分层边界和 ADS 指标合理性，使项目从基础 SQL 分析升级为具备离线数仓分层和工程化执行能力的 Hive 迁移项目。

如果面试官追问为什么要迁移到 Hive，可以回答：

> 原 MySQL 版本适合中小规模数据分析，但在大批量明细处理、历史分区管理、批量重跑和数仓分层组织方面不够灵活。Hive 更适合离线批处理场景，可以通过分区表、列式存储和覆盖分区写入方式支持按天处理和重跑，因此我将核心指标链路迁移到 Hive。

如果面试官追问为什么使用 `dt` 分区，可以回答：

> 因为订单数据天然具有业务日期，使用 `dt` 分区可以让 DWD、DWS、ADS 各层按同一业务日期对齐。每天任务只处理当天分区，重跑时也只覆盖指定日期分区，避免全表扫描和重复写入。

如果面试官追问为什么使用 ORC，可以回答：

> 本项目主要是离线聚合分析，例如按客户、国家、商品统计订单数和销售额。ORC 是 Hive 常用的列式存储格式，适合这类读取部分字段、进行聚合分析的场景，同时也支持压缩和列裁剪。

如果面试官追问为什么使用 `INSERT OVERWRITE`，可以回答：

> 离线数仓任务经常需要重跑指定日期分区。使用 `INSERT OVERWRITE PARTITION` 可以覆盖目标分区，保证任务幂等，避免重复执行后出现重复数据。

如果面试官追问项目有什么亮点，可以回答：

> 这个项目的亮点不只是把 MySQL SQL 改写成 Hive SQL，而是补充了完整的离线数仓设计：ODS、DWD、DWS、ADS 分层，`dt` 分区，ORC 存储，`bizdate` 参数化，`INSERT OVERWRITE` 分区覆盖，`run_all_hive.sh` 执行链路，以及数据质量校验脚本。这样项目更接近真实离线数仓开发流程。