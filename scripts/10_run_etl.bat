@echo off
chcp 65001 >nul

REM =========================================
REM 10_run_etl.bat
REM 作用：执行 MySQL 版本 ETL 主脚本
REM 说明：
REM   1. 默认连接本地 MySQL
REM   2. 不在脚本中写死数据库密码
REM   3. 如需指定密码，请运行前设置环境变量 MYSQL_PASSWORD
REM =========================================

set MYSQL_HOST=127.0.0.1
set MYSQL_PORT=3306
set MYSQL_USER=root
set MYSQL_DB=retail_project

echo ========================================
echo Running retail_project ETL...
echo ========================================

if "%MYSQL_PASSWORD%"=="" (
    mysql -h%MYSQL_HOST% -P%MYSQL_PORT% -u%MYSQL_USER% %MYSQL_DB% < 08_run_all.sql
) else (
    mysql -h%MYSQL_HOST% -P%MYSQL_PORT% -u%MYSQL_USER% -p%MYSQL_PASSWORD% %MYSQL_DB% < 08_run_all.sql
)

echo.
echo ========================================
echo ETL finished.
echo Press any key to exit.
echo ========================================
pause >nul