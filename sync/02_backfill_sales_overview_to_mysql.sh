#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/01_sync_sales_overview_to_mysql.sh"

BIZ_DATES=(
    "2026-04-01"
    "2026-04-02"
    "2026-04-03"
    "2026-04-04"
    "2026-04-05"
    "2026-04-06"
    "2026-04-07"
    "2026-04-08"
)

read -r -s -p "请输入 retail_sync_user 的 MySQL 密码：" MYSQL_PASSWORD
echo

export MYSQL_PASSWORD

for bizdate in "${BIZ_DATES[@]}"; do
    bash "${SYNC_SCRIPT}" "${bizdate}"
done

unset MYSQL_PASSWORD

echo "8 个业务日期全部同步完成。"