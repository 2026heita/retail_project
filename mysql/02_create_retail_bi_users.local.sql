-- ============================================================
-- 文件名：02_create_retail_bi_users.example.sql
-- 功能：创建零售 BI 数据同步账号和 Java 查询账号
-- 注意：本文件只保留密码占位符，可以提交 Git
-- ============================================================

-- 数据同步账号：由 Linux 虚拟机上的同步任务使用
CREATE USER IF NOT EXISTS 'retail_sync_user'@'localhost'
IDENTIFIED WITH caching_sha2_password
BY '__SYNC_PASSWORD__';

ALTER USER 'retail_sync_user'@'localhost'
IDENTIFIED WITH caching_sha2_password
BY '__SYNC_PASSWORD__';

GRANT SELECT, INSERT, UPDATE, DELETE
ON retail_bi.*
TO 'retail_sync_user'@'localhost';


-- Java 查询账号：允许 Windows 主机通过虚拟机网段访问
CREATE USER IF NOT EXISTS 'retail_api_user'@'192.168.85.%'
IDENTIFIED WITH caching_sha2_password
BY '__API_PASSWORD__';

ALTER USER 'retail_api_user'@'192.168.85.%'
IDENTIFIED WITH caching_sha2_password
BY '__API_PASSWORD__';

GRANT SELECT
ON retail_bi.*
TO 'retail_api_user'@'192.168.85.%';

FLUSH PRIVILEGES;