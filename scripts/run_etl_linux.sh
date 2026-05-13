#!/usr/bin/env bash
set -euo pipefail

# =========================================
# run_etl_linux.sh
# Purpose: Run the MySQL offline warehouse ETL script and write ETL status logs.
# GitHub public version:
#   - No server IP, plaintext credential, or database password is stored here.
#   - MySQL authentication should use mysql_config_editor login-path or ~/.my.cnf.
#   - Example local setup, do NOT commit real values:
#       mysql_config_editor set --login-path=retail_local --host=localhost --user=retail_user --port=3306 --password
# =========================================

MYSQL_LOGIN_PATH="${MYSQL_LOGIN_PATH:-retail_local}"
MYSQL_DB="${MYSQL_DB:-retail_project}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_HOME="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${PROJECT_HOME}/logs"
LOG_FILE="${LOG_DIR}/etl_log.txt"
RUN_SQL="${PROJECT_HOME}/sql/08_run_all.sql"
LOG_TABLE_SQL="${PROJECT_HOME}/sql/11_etl_task_log.sql"
BATCH_ID="$(date +"%Y%m%d_%H%M%S")"

mkdir -p "${LOG_DIR}"

log_info() {
  echo "$1" | tee -a "${LOG_FILE}"
}

run_mysql_file() {
  local sql_file="$1"
  mysql --login-path="${MYSQL_LOGIN_PATH}" "${MYSQL_DB}" < "${sql_file}" >> "${LOG_FILE}" 2>&1
}

run_mysql_statement() {
  local sql_stmt="$1"
  mysql --login-path="${MYSQL_LOGIN_PATH}" "${MYSQL_DB}" -e "${sql_stmt}" >> "${LOG_FILE}" 2>&1
}

if [[ ! -f "${RUN_SQL}" ]]; then
  log_info "[ERROR] SQL file not found: ${RUN_SQL}"
  exit 1
fi

if [[ ! -f "${LOG_TABLE_SQL}" ]]; then
  log_info "[ERROR] SQL file not found: ${LOG_TABLE_SQL}"
  exit 1
fi

log_info "========== ETL START =========="
log_info "batch_id=${BATCH_ID}"
log_info "run_time=$(date '+%F %T')"
log_info "mysql_login_path=${MYSQL_LOGIN_PATH}"
log_info "mysql_database=${MYSQL_DB}"

run_mysql_file "${LOG_TABLE_SQL}"

run_mysql_statement "
INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark)
VALUES ('${BATCH_ID}', 'run_all_etl', NOW(), 'START', 'Start running 08_run_all.sql');
"

if run_mysql_file "${RUN_SQL}"; then
  log_info "[INFO] ETL executed successfully"
  run_mysql_statement "
  INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark)
  VALUES ('${BATCH_ID}', 'run_all_etl', NOW(), 'SUCCESS', '08_run_all.sql executed successfully');
  "
  log_info "========== ETL SUCCESS =========="
else
  log_info "[ERROR] ETL execution failed"
  run_mysql_statement "
  INSERT INTO etl_task_log(batch_id, task_name, run_time, status, remark)
  VALUES ('${BATCH_ID}', 'run_all_etl', NOW(), 'FAILED', '08_run_all.sql failed. Please check logs/etl_log.txt');
  " || true
  log_info "========== ETL FAILED =========="
  exit 1
fi
