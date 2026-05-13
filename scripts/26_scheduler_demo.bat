@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM =========================================
REM 26_scheduler_demo.bat
REM Purpose: Simulate an offline warehouse scheduling workflow on Windows.
REM Steps: ETL build -> ETL log check -> data quality check.
REM GitHub public version:
REM   - No server IP, plaintext credential, or database password is stored here.
REM   - MySQL authentication should use mysql_config_editor login-path or local client config.
REM   - This script is for local portfolio demonstration, not production scheduling.
REM =========================================

set "SCRIPT_DIR=%~dp0"
set "PROJECT_HOME=%SCRIPT_DIR%.."
set "RUN_SQL=%PROJECT_HOME%\sql\08_run_all.sql"
set "CHECK_LOG_SQL=%PROJECT_HOME%\sql\12_check_etl_log.sql"
set "DQ_SQL=%PROJECT_HOME%\sql\13_data_quality_check.sql"

if not defined MYSQL_LOGIN_PATH set "MYSQL_LOGIN_PATH=retail_local"
if not defined MYSQL_DB set "MYSQL_DB=retail_project"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "BATCH_ID=%%i"

if not exist "%RUN_SQL%" (
    echo [ERROR] SQL file not found: %RUN_SQL%
    exit /b 1
)
if not exist "%CHECK_LOG_SQL%" (
    echo [ERROR] SQL file not found: %CHECK_LOG_SQL%
    exit /b 1
)
if not exist "%DQ_SQL%" (
    echo [ERROR] SQL file not found: %DQ_SQL%
    exit /b 1
)

echo =========================================
echo Scheduler demo batch: %BATCH_ID%
echo MySQL login-path: %MYSQL_LOGIN_PATH%
echo MySQL database: %MYSQL_DB%
echo =========================================

echo [1/3] Build DWD/DWS/ADS tables...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" < "%RUN_SQL%"
if errorlevel 1 (
    echo [FAILED] 08_run_all.sql
    goto :FAILED
)

echo [2/3] Check ETL log table...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" < "%CHECK_LOG_SQL%"
if errorlevel 1 (
    echo [FAILED] 12_check_etl_log.sql
    goto :FAILED
)

echo [3/3] Run data quality checks...
mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" < "%DQ_SQL%"
if errorlevel 1 (
    echo [FAILED] 13_data_quality_check.sql
    goto :FAILED
)

echo Batch %BATCH_ID% SUCCESS
exit /b 0

:FAILED
echo Batch %BATCH_ID% FAILED
exit /b 1
