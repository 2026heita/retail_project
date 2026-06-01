# 本地 Hive 运行指南

本文档用于说明如何使用仓库中的最小样例数据，验证零售数据仓库项目的 Hive 主链路。

主链路包括：

```text
ODS -> DWD -> 质量日志 -> DWS -> ADS -> 结果校验

适用场景：

面试官查看项目时，可以快速理解项目如何运行。

自己在 FinalShell / Linux 环境中验证 Hive SQL 是否能跑通。

不上传完整大数据集的情况下，仍然保留最小可复现能力。

1. 环境要求

建议环境如下：

Linux 服务器 / 虚拟机 / Hadoop 环境
Hive 3.x
HDFS 可用
MySQL 源表可用
FinalShell 或普通终端可连接服务器

检查 Hive 是否可用：

hive -e "show databases;"

检查 HDFS 是否可用：

hdfs dfs -ls /

如果上面两个命令都能正常返回结果，说明基础环境基本可用。

2. 样例数据位置

仓库提供最小样例数据：

sample_data/retail_sample.csv

该样例数据只用于验证项目链路，不代表完整原始数据集。

完整原始数据量较大，因此不上传到仓库。

3. 源表字段说明

Hive ODS 加载脚本读取的源表名为：

retail

源表字段如下：

字段名	说明
Invoice	订单编号
StockCode	商品编码
Description	商品描述
Quantity	购买数量
InvoiceDate	订单时间
Price	商品单价
CustomerID	客户编号
Country	国家

其中 InvoiceDate 的格式为：

yyyy-MM-dd HH:mm:ss

示例：

2026-04-08 07:45:00
4. 在 MySQL 中创建源表

先进入 MySQL，然后执行以下 SQL：

CREATE TABLE IF NOT EXISTS retail (
    Invoice VARCHAR(255),
    StockCode VARCHAR(255),
    Description VARCHAR(255),
    Quantity INT,
    InvoiceDate DATETIME,
    Price DOUBLE,
    CustomerID DOUBLE,
    Country VARCHAR(255)
);
5. 导入样例数据

将以下文件导入 MySQL 的 retail 表：

sample_data/retail_sample.csv

如果使用 Navicat，可以按下面步骤操作：

1. 右键 retail 表
2. 选择“导入向导”
3. 选择 CSV 文件
4. 字段按列名对应
5. 执行导入

导入完成后，执行检查：

SELECT COUNT(*) FROM retail;

再检查 2026-04-08 当天的数据：

SELECT *
FROM retail
WHERE DATE(InvoiceDate) = '2026-04-08'
LIMIT 10;

如果能查到数据，说明样例数据已经导入成功。

6. 样例数据预览

retail_sample.csv 的字段格式如下：

Invoice,StockCode,Description,Quantity,InvoiceDate,Price,CustomerID,Country
536365,85123A,WHITE HANGING HEART T-LIGHT HOLDER,6,2026-04-08 07:45:00,2.55,17850,United Kingdom
536365,71053,WHITE METAL LANTERN,6,2026-04-08 07:46:00,3.39,17850,United Kingdom
536365,84406B,CREAM CUPID HEARTS COAT HANGER,8,2026-04-08 07:47:00,2.75,17850,United Kingdom

样例数据中包含正常订单和部分异常订单，用于验证 DWD 清洗逻辑。

7. 运行 Hive 主链路

进入项目的 Hive SQL 目录：

cd hive_sql

执行主脚本：

sh run_all_hive.sh 2026-04-08

该脚本会按顺序执行：

1. 创建 ODS 表
2. 加载 ODS 分区
3. 校验 ODS 分区
4. 创建 DWD 表
5. 加载 DWD 分区
6. 创建质量日志表
7. 写入质量日志
8. 构建 DWS 客户价值表
9. 构建 DWS 销售汇总表
10. 构建 ADS 高价值客户贡献表
11. 构建 ADS 客户等级分布表
12. 构建 ADS 国家销售排行表
13. 构建 ADS 高价值客户偏好表
14. 执行结果校验

如果脚本最后输出类似下面内容，说明主链路执行成功：

Hive main warehouse job finished successfully
bizdate: 2026-04-08
8. ODS 层逻辑说明

ODS 层用于保存指定业务日期的原始订单数据。

ODS 加载逻辑会根据 InvoiceDate 过滤业务日期：

只加载 InvoiceDate = 2026-04-08 的数据

并写入 Hive 分区：

dt = 2026-04-08

ODS 层保留原始字段，不做复杂清洗。

9. DWD 层逻辑说明

DWD 层用于清洗异常数据，并计算订单金额。

金额计算逻辑：

amount = quantity * price

DWD 会过滤以下异常记录：

quantity <= 0
price <= 0
customerid 为空
invoice 为空
invoice 以 C 开头的退货订单
stockcode 为空
country 为空
invoicedate 为空

因此，样例数据中故意包含部分异常记录，用于验证 DWD 清洗规则是否生效。

10. 快速验证 ODS 和 DWD

如果只想先验证最核心链路，可以重点检查 ODS 和 DWD。

查询 ODS 分区数据量：

SELECT COUNT(*)
FROM ods_retail_hive
WHERE dt = '2026-04-08';

查询 DWD 清洗后数据量：

SELECT COUNT(*)
FROM dwd_retail_clean_hive
WHERE dt = '2026-04-08';

正常情况下，DWD 数据量应该小于或等于 ODS 数据量。

原因是 DWD 会过滤无效数量、无效价格、空客户、退货订单等异常记录。

11. 查询 DWD 清洗结果

进入 Hive 后执行：

SELECT *
FROM dwd_retail_clean_hive
WHERE dt = '2026-04-08'
LIMIT 20;

也可以检查清洗后的金额字段：

SELECT
    invoice,
    stockcode,
    quantity,
    price,
    amount,
    customerid,
    country
FROM dwd_retail_clean_hive
WHERE dt = '2026-04-08'
LIMIT 20;
12. 查询 DWS 结果

查询客户价值汇总：

SELECT *
FROM dws_customer_value_hive
WHERE dt = '2026-04-08'
LIMIT 20;

查询销售汇总：

SELECT *
FROM dws_sales_summary_hive
WHERE dt = '2026-04-08'
LIMIT 20;
13. 查询 ADS 结果

查询高价值客户贡献：

SELECT *
FROM ads_high_value_customer_sales_contribution_hive
WHERE dt = '2026-04-08'
LIMIT 20;

查询客户等级分布：

SELECT *
FROM ads_customer_level_distribution_hive
WHERE dt = '2026-04-08'
LIMIT 20;

查询国家销售排行：

SELECT *
FROM ads_country_sales_rank_hive
WHERE dt = '2026-04-08'
LIMIT 20;

查询高价值客户商品偏好：

SELECT *
FROM ads_high_value_customer_preference_hive
WHERE dt = '2026-04-08'
LIMIT 20;
14. 常见问题
14.1 找不到 SQL 文件

如果出现类似错误：

ERROR: SQL file not found

说明当前执行目录不对。

请确认你是在项目的 hive_sql 目录下执行：

cd hive_sql
sh run_all_hive.sh 2026-04-08
14.2 Hive 命令不存在

如果出现：

hive: command not found

说明当前环境没有配置 Hive 命令。

需要检查 Hive 是否安装，或者 Hive 的 bin 目录是否加入了环境变量。

14.3 HDFS 不可用

如果出现 HDFS 相关错误，先检查：

hdfs dfs -ls /

如果该命令失败，需要先启动 Hadoop / HDFS 服务。

14.4 MySQL 源表没有数据

如果 ODS 加载结果为空，先检查 MySQL 源表：

SELECT COUNT(*) FROM retail;

SELECT *
FROM retail
WHERE DATE(InvoiceDate) = '2026-04-08'
LIMIT 10;

如果这里查不到数据，说明样例数据没有正确导入。

14.5 业务日期格式错误

脚本日期格式为：

yyyy-MM-dd

正确示例：

sh run_all_hive.sh 2026-04-08

错误示例：

sh run_all_hive.sh 20260408
15. 提交到 GitHub

新增或修改文件后，可以执行：

git add sample_data/retail_sample.csv docs/setup_local_hive.md README.md
git commit -m "Add sample data and local Hive setup guide"
git push
16. 说明

本项目提供的 sample_data/retail_sample.csv 仅用于验证 Hive SQL 主链路。

完整原始数据集不上传到仓库，避免仓库体积过大。

通过该样例数据，可以验证以下能力：

ODS 按日期入仓
DWD 数据清洗
amount 金额计算
DWS 汇总建模
ADS 指标输出
主脚本按业务日期串联执行