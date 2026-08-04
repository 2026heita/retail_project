-- =====================================================
-- 文件名: 02_load_dwd_retail_clean_hive.sql
-- 功能: 从 ODS 分区表加载零售订单数据到 DWD 清洗表
-- 说明:
--   1. 只处理当前 bizdate 对应的 ODS 分区
--   2. 过滤无效数量、无效价格、空客户ID、退货订单和不可解析时间
--   3. ODS保留原始字段，DWD进行标准化
--   4. 使用INSERT OVERWRITE保证同一日期重复执行结果一致
-- =====================================================

INSERT OVERWRITE TABLE dwd_retail_clean_hive
PARTITION (dt = '${hiveconf:bizdate}')

SELECT
    -- 订单号：仅清理首尾空格，保留原始大小写及业务前缀
    TRIM(invoice) AS invoice,

    -- 商品编码：清理首尾空格并统一为大写
    UPPER(TRIM(stockcode)) AS stockcode,

    -- 商品描述：仅清理首尾空格
    TRIM(description) AS description,

    quantity,

    -- 将可解析的源时间统一输出为 yyyy-MM-dd HH:mm:ss
    FROM_UNIXTIME(
        invoice_ts,
        'yyyy-MM-dd HH:mm:ss'
    ) AS invoicedate,

    CAST(price AS DECIMAL(10,2)) AS price,

    -- 客户ID：
    -- 1. 先清理首尾空格
    -- 2. 仅对“纯数字+.0”形式去除末尾.0
    -- 3. 非纯数字ID保留原值
    CASE
        WHEN TRIM(CAST(customerid AS STRING))
             RLIKE '^[0-9]+[.]0$'
        THEN REGEXP_REPLACE(
            TRIM(CAST(customerid AS STRING)),
            '[.]0$',
            ''
        )
        ELSE TRIM(CAST(customerid AS STRING))
    END AS customerid,

    -- 国家：仅清理首尾空格
    TRIM(country) AS country,

    -- 明细金额
    CAST(
        ROUND(quantity * price, 2)
        AS DECIMAL(12,2)
    ) AS amount

FROM (
    SELECT
        invoice,
        stockcode,
        description,
        quantity,
        invoicedate,
        price,
        customerid,
        country,

        COALESCE(
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'yyyy-MM-dd HH:mm:ss'
            ),
            UNIX_TIMESTAMP(
                TRIM(invoicedate),
                'd/M/yyyy HH:mm:ss'
            )
        ) AS invoice_ts

    FROM ods_retail_hive
    WHERE dt = '${hiveconf:bizdate}'
) ods_parsed

WHERE quantity > 0
  AND price > 0

  AND customerid IS NOT NULL
  AND TRIM(CAST(customerid AS STRING)) <> ''

  AND invoice IS NOT NULL
  AND TRIM(invoice) <> ''
  AND UPPER(TRIM(invoice)) NOT LIKE 'C%'

  AND stockcode IS NOT NULL
  AND TRIM(stockcode) <> ''

  AND country IS NOT NULL
  AND TRIM(country) <> ''

  AND invoicedate IS NOT NULL
  AND TRIM(invoicedate) <> ''

  AND invoice_ts IS NOT NULL;