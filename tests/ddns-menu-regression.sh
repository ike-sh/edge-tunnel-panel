#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export LEIKWAN_STATE_DIR="${TMP_DIR}/state"
export LEIKWAN_BACKUP_DIR="${TMP_DIR}/backups"
export LEIKWAN_RUN_DIR="${TMP_DIR}/run"
export LEIKWAN_LOG_DISABLED=1
export LEIKWAN_NO_CLEAR=1
mkdir -p "$LEIKWAN_RUN_DIR"

# shellcheck source=/dev/null
source "$ROOT_DIR/leikwan-toolkit.sh"

main_out="$(print_main_menu_options)"
grep -q "4. DDNS" <<<"$main_out"
grep -q "6. 高级维护" <<<"$main_out"
grep -q "0. 退出" <<<"$main_out"

ddns_out="$(print_ddns_menu_options)"
grep -q "B 端监控：" <<<"$ddns_out"
grep -q "2. 应用公网入口 DDNS 变化" <<<"$ddns_out"
grep -q "A 端更新：" <<<"$ddns_out"
grep -q "4. 配置 A 端 DDNS" <<<"$ddns_out"
grep -q "7. DDNS 一致性检查" <<<"$ddns_out"
grep -q "0. 返回" <<<"$ddns_out"

echo "[OK] ddns menu regression passed"
