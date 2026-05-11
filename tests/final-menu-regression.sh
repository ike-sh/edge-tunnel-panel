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
grep -q "Leikwan Toolkit 1.4.0 LTS" <<<"$main_out"
grep -q "1. 快速组网" <<<"$main_out"
grep -q "2. 利群主机 B" <<<"$main_out"
grep -q "3. 公网入口 A" <<<"$main_out"
grep -q "4. DDNS" <<<"$main_out"
grep -q "5. 状态 / 诊断" <<<"$main_out"
grep -q "6. 高级维护" <<<"$main_out"
grep -q "0. 退出" <<<"$main_out"
if grep -Eq '7\.|8\.|9\.' <<<"$main_out"; then
  echo "FAIL: main menu should only expose six core entries" >&2
  echo "$main_out" >&2
  exit 1
fi

ddns_out="$(print_ddns_menu_options)"
grep -q "B 端监控：" <<<"$ddns_out"
grep -q "A 端更新：" <<<"$ddns_out"
grep -q "1. 检测全部域名变化" <<<"$ddns_out"
grep -q "2. 应用公网入口 DDNS 变化" <<<"$ddns_out"
grep -q "7. DDNS 一致性检查" <<<"$ddns_out"
grep -q "0. 返回" <<<"$ddns_out"

advanced_out="$(print_advanced_menu_options)"
grep -q "高级维护" <<<"$advanced_out"
grep -q "1. EasyTier 服务管理" <<<"$advanced_out"
grep -q "2. 配置备份 / 快照 / 回滚" <<<"$advanced_out"
grep -q "3. 配置导入 / 导出" <<<"$advanced_out"
grep -q "4. 自更新" <<<"$advanced_out"
grep -q "5. 端点输出" <<<"$advanced_out"
grep -q "6. 调试报告" <<<"$advanced_out"
grep -q "7. 卸载" <<<"$advanced_out"
grep -q "0. 返回" <<<"$advanced_out"

status_out="$(print_status_diagnostics_menu_options)"
grep -q "状态 / 诊断" <<<"$status_out"
grep -q "4. 自动修复常见问题" <<<"$status_out"
grep -q "6. 查看日志" <<<"$status_out"

echo "[OK] final menu regression passed"
