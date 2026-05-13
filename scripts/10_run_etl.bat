@echo off
chcp 65001 >nul
setlocal

REM =========================================
REM 10_run_etl.bat
REM Purpose: Run the MySQL offline warehouse ETL script on Windows.
REM GitHub public version:
REM   - No server IP, plaintext credential, or database password is stored here.
REM   - MySQL authentication should use mysql_config_editor login-path or local client config.
REM   - Example local setup, do NOT commit real values:
REM       mysql_config_editor set --login-path=retail_local --host=localhost --user=retail_user --port=3306 --password
REM =========================================

set "SCRIPT_DIR=%~dp0"
set "PROJECT_HOME=%SCRIPT_DIR%.."
set "RUN_SQL=%PROJECT_HOME%\sql\08_run_all.sql"

if not defined MYSQL_LOGIN_PATH set "MYSQL_LOGIN_PATH=retail_local"
if not defined MYSQL_DB set "MYSQL_DB=retail_project"

if not exist "%RUN_SQL%" (
    echo [ERROR] SQL file not found: %RUN_SQL%
    exit /b 1
)

echo ========================================
echo Running retail_project ETL...
echo MySQL login-path: %MYSQL_LOGIN_PATH%
echo MySQL database: %MYSQL_DB%
echo ========================================

mysql --login-path=%MYSQL_LOGIN_PATH% "%MYSQL_DB%" < "%RUN_SQL%"
if errorlevel 1 (
    echo [ERROR] ETL failed. Please check SQL errors above.
    exit /b 1
)

echo.
echo ========================================
echo ETL finished successfully.
echo ========================================

endlocal
