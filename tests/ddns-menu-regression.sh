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
grep -q "DDNS 自动刷新" <<<"$main_out"
grep -q "9. 卸载全部" <<<"$main_out"
grep -q "0. 退出" <<<"$main_out"

ddns_out="$(print_ddns_menu_options)"
grep -q "B 端监控：检测域名解析变化并应用转发/PBR/relay" <<<"$ddns_out"
grep -q "5. B：应用公网入口 DDNS 变化" <<<"$ddns_out"
grep -q "8. A：配置本机公网入口 DDNS" <<<"$ddns_out"
grep -q "11. A：查看本机 DDNS 状态 / 日志" <<<"$ddns_out"
grep -q "12. DDNS 总览" <<<"$ddns_out"
grep -q "0. 返回" <<<"$ddns_out"

render_out="$(print_operations_center_menu)"
grep -q "DDNS 自动刷新" <<<"$render_out"

echo "[OK] ddns menu regression passed"
