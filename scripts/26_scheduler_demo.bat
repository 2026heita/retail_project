@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM =========================================
REM 26_scheduler_demo.bat
REM 作用：模拟离线数仓任务调度执行流程
REM 包含：批次号生成、任务执行、日志查看、结果校验
REM 说明：
REM   1. 默认连接本地 MySQL
REM   2. 不在脚本中写死数据库密码
REM   3. 如需指定密码，请运行前设置环境变量 MYSQL_PASSWORD
REM =========================================

set MYSQL_HOST=127.0.0.1
set MYSQL_PORT=3306
set MYSQL_USER=root
set MYSQL_DB=retail_project

set MYSQL_PWD_OPT=
if not "%MYSQL_PASSWORD%"=="" (
    set MYSQL_PWD_OPT=-p%MYSQL_PASSWORD%
)

for /f "tokens=1-4 delims=/ " %%a in ("%date%") do (
    set YYYY=%%a
    set MM=%%b
    set DD=%%c
)

for /f "tokens=1-3 delims=:." %%a in ("%time%") do (
    set HH=%%a
    set MI=%%b
    set SS=%%c
)

set BATCH_ID=%YYYY%%MM%%DD%_%HH%%MI%%SS%

echo =========================================
echo Batch ID: %BATCH_ID%
echo =========================================

echo [1/4] Start DWD/DWS/ADS build...
mysql -h%MYSQL_HOST% -P%MYSQL_PORT% -u%MYSQL_USER% %MYSQL_PWD_OPT% %MYSQL_DB% < 08_run_all.sql
if errorlevel 1 (
    echo [FAILED] 08_run_all.sql
    goto :FAILED
)

echo [2/4] Check ETL log table...
mysql -h%MYSQL_HOST% -P%MYSQL_PORT% -u%MYSQL_USER% %MYSQL_PWD_OPT% %MYSQL_DB% < 12_check_etl_log.sql
if errorlevel 1 (
    echo [FAILED] 12_check_etl_log.sql
    goto :FAILED
)

echo [3/4] Run data quality checks...
mysql -h%MYSQL_HOST% -P%MYSQL_PORT% -u%MYSQL_USER% %MYSQL_PWD_OPT% %MYSQL_DB% < 13_data_quality_check.sql
if errorlevel 1 (
    echo [FAILED] 13_data_quality_check.sql
    goto :FAILED
)

echo [4/4] Scheduler demo finished successfully.
echo Batch %BATCH_ID% SUCCESS
goto :END

:FAILED
echo Batch %BATCH_ID% FAILED
exit /b 1

:END
endlocal
pause