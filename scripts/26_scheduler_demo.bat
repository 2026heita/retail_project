@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM =====================================================
REM 文件名: 26_scheduler_demo.bat
REM 文件属性: 长期保留，提交代码仓库
REM 功能:
REM   模拟 Windows 下的 MySQL 离线数仓调度流程，
REM   并为当前批次记录 START / SUCCESS / FAILED 日志。
REM
REM 说明:
REM   1. 使用 mysql_config_editor login-path 管理认证信息
REM   2. 不在脚本中保存明文账号和密码
REM   3. 当前属于本地项目演示，不替代生产级调度系统
REM =====================================================

set "SCRIPT_DIR=%~dp0"
set "PROJECT_HOME=%SCRIPT_DIR%.."

set "RUN_SQL=%PROJECT_HOME%\sql\08_run_all.sql"
set "CREATE_LOG_SQL=%PROJECT_HOME%\sql\11_etl_task_log.sql"
set "CHECK_LOG_SQL=%PROJECT_HOME%\sql\12_check_etl_log.sql"
set "DQ_SQL=%PROJECT_HOME%\sql\13_data_quality_check.sql"

if not defined MYSQL_LOGIN_PATH set "MYSQL_LOGIN_PATH=retail_local"
if not defined MYSQL_DB set "MYSQL_DB=retail_project"

for /f %%i in (
    'powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"'
) do set "BATCH_ID=%%i"

set "TASK_NAME=mysql_warehouse_pipeline"
set "FAILED_STEP="

call :CHECK_FILE "%RUN_SQL%"
if errorlevel 1 exit /b 1

call :CHECK_FILE "%CREATE_LOG_SQL%"
if errorlevel 1 exit /b 1

call :CHECK_FILE "%CHECK_LOG_SQL%"
if errorlevel 1 exit /b 1

call :CHECK_FILE "%DQ_SQL%"
if errorlevel 1 exit /b 1

echo =========================================
echo Scheduler demo batch: %BATCH_ID%
echo MySQL login-path: %MYSQL_LOGIN_PATH%
echo MySQL database: %MYSQL_DB%
echo =========================================

echo [0/4] Ensure ETL log table exists...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" < "%CREATE_LOG_SQL%"
if errorlevel 1 (
    echo [FAILED] Unable to create or verify etl_task_log.
    exit /b 1
)

echo [1/4] Write START log...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" ^
  --execute="INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark) VALUES('%BATCH_ID%', '%TASK_NAME%', NOW(), 'START', 'Scheduler demo started');"
if errorlevel 1 (
    echo [FAILED] Unable to write START log.
    exit /b 1
)

echo [2/4] Build DWD/DWS/ADS tables...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" < "%RUN_SQL%"
if errorlevel 1 (
    set "FAILED_STEP=08_run_all.sql"
    goto :FAILED
)

echo [3/4] Run data quality checks...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" < "%DQ_SQL%"
if errorlevel 1 (
    set "FAILED_STEP=13_data_quality_check.sql"
    goto :FAILED
)

echo [4/4] Write SUCCESS log...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" ^
  --execute="INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark) VALUES('%BATCH_ID%', '%TASK_NAME%', NOW(), 'SUCCESS', 'Scheduler demo completed successfully');"
if errorlevel 1 (
    echo [FAILED] Unable to write SUCCESS log.
    exit /b 1
)

echo.
echo Current batch log:
mysql --login-path=%MYSQL_LOGIN_PATH% ^
  --init-command="SET @batch_id='%BATCH_ID%';" ^
  "%MYSQL_DB%" < "%CHECK_LOG_SQL%"
if errorlevel 1 (
    echo [FAILED] Unable to query current batch log.
    exit /b 1
)

echo.
echo Batch %BATCH_ID% SUCCESS
exit /b 0


:FAILED
echo.
echo [FAILED] Step: !FAILED_STEP!

mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" ^
  --execute="INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark) VALUES('%BATCH_ID%', '%TASK_NAME%', NOW(), 'FAILED', 'Failed step: !FAILED_STEP!');"

echo.
echo Current batch log:
mysql --login-path=%MYSQL_LOGIN_PATH% ^
  --init-command="SET @batch_id='%BATCH_ID%';" ^
  "%MYSQL_DB%" < "%CHECK_LOG_SQL%"

echo.
echo Batch %BATCH_ID% FAILED
exit /b 1


:CHECK_FILE
if not exist "%~1" (
    echo [ERROR] File not found: %~1
    exit /b 1
)
exit /b 0
