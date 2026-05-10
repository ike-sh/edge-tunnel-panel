#!/usr/bin/env bash
set -Eeuo pipefail

TOOL_VERSION="1.2.0"
PROJECT_NAME="leikwan-toolkit"
PROJECT_TITLE="利群快速组网工具"
PROJECT_GITHUB="https://github.com/ike-sh/leikwan-toolkit"

DRY_RUN=0
VERBOSE_DOCTOR=0
DEPS_APT_UPDATED=0
DEPS_INSTALLED_THIS_RUN=""
LOG_DISABLED=0
MENU_ACTION_PAUSE_DONE=0
DOCTOR_INTERACTIVE_FIX=0
APPLY_NFT_LAST_STATUS=""
REPORT_WARN_COUNT=0
REPORT_FAIL_COUNT=0
PORT_CHECK_RESULT="ok"
STATUS_OVERVIEW_RESULT="ok"
LEIKWAN_GLOBAL_LOCK_TOKEN=""

LOG_FILE="/var/log/leikwan-toolkit.log"
STATE_DIR="/etc/leikwan-toolkit"
BACKUP_DIR="/var/backups/leikwan-toolkit"
OLD_LOG_FILE="/var/log/leikwan-wg-toolkit.log"
OLD_STATE_DIR="/etc/leikwan-wg-toolkit"
OLD_BACKUP_DIR="/var/backups/leikwan-wg-toolkit"
OLD_ROOT_SCRIPT="/root/wg-${PROJECT_NAME#leikwan-}.sh"
OUTPUT_DIR="${STATE_DIR}/outputs"
NFT_DIR="${STATE_DIR}/nft"
ENTRY_DIR="${STATE_DIR}/entry"
ENTRIES_DIR="${STATE_DIR}/entries"
FORWARDS_DIR="${STATE_DIR}/forwards"
PBR_DIR="${STATE_DIR}/pbr"
EASYTIER_DIR="${STATE_DIR}/easytier"
STATUS_DIR="${STATE_DIR}/status"
SNAPSHOT_DIR="${STATE_DIR}/snapshots"
AUTO_SNAPSHOT_DIR="${SNAPSHOT_DIR}/auto"
REPORT_FILE="/root/leikwan-debug-report.txt"
APPLY_RELAY_LOG="/root/lq-apply-relay.log"
DDNS_CONFIG="${STATE_DIR}/ddns.env"
DDNS_LOG_FILE="/var/log/leikwan-ddns-refresh.log"
DDNS_STATUS_FILE="${STATUS_DIR}/last-ddns.env"
DDNS_SERVICE_NAME="leikwan-ddns-refresh"
DDNS_SERVICE="/etc/systemd/system/${DDNS_SERVICE_NAME}.service"
DDNS_TIMER="/etc/systemd/system/${DDNS_SERVICE_NAME}.timer"
LEIKWAN_LOCK_PATH="/run/leikwan-toolkit.lock"
DDNS_LOCK_PATH="/run/leikwan-ddns-refresh.lock"
UPDATE_LOCK_PATH="/run/leikwan-update.lock"
CONFIG_LOCK_PATH="/run/leikwan-config.lock"
UPDATE_STATUS_FILE="${STATUS_DIR}/last-update.env"
UPDATE_TARGET_SCRIPT="/root/leikwan-toolkit.sh"
UPDATE_REPO="ike-sh/leikwan-toolkit"

ENTRIES_TSV="${ENTRIES_DIR}/entries.tsv"
PENDING_ENTRIES_TSV="${ENTRIES_DIR}/pending-entries.tsv"
RESOLVED_ENTRIES_TSV="${ENTRIES_DIR}/resolved-entries.tsv"
FORWARDS_TSV="${FORWARDS_DIR}/forwards.tsv"
RESOLVED_TSV="${FORWARDS_DIR}/resolved.tsv"
FORWARD_TXT="${OUTPUT_DIR}/forward-endpoints.txt"
FORWARD_TSV="${OUTPUT_DIR}/forward-endpoints.tsv"
FORWARD_JSON="${OUTPUT_DIR}/forward-endpoints.json"
FORWARD_HTML="${OUTPUT_DIR}/forward-endpoints.html"
FORWARD_QR_DIR="${OUTPUT_DIR}/qr"
ENTRY_EXPOSE_ENV="${ENTRY_DIR}/expose.env"
NETWORK_ENV="${EASYTIER_DIR}/network.env"
NETWORK_PAIRING_FILE="${OUTPUT_DIR}/easytier-network-code.env"
ENTRY_PAIRING_FILE="${OUTPUT_DIR}/easytier-entry-code.env"
DEPS_MARKER="${STATE_DIR}/.deps-installed"

ET_NET="10.198.1.0/24"
RELAY_ET_IP="10.198.1.1"
ENTRY_ET_IP_DEFAULT="10.198.1.2"
ENTRY_EXPOSE_START_DEFAULT="10000"
ENTRY_EXPOSE_END_DEFAULT="19999"
FORWARD_ENTRY_PORT_FALLBACK_START="10001"
FORWARD_ENTRY_PORT_FALLBACK_END="19999"
DEFAULT_TCP_MSS_CLAMP="1320"
ENABLE_MSS_CLAMP="true"
EASYTIER_VERSION="${EASYTIER_VERSION:-v2.4.5}"
EASYTIER_CORE_BIN="/usr/local/bin/easytier-core"
EASYTIER_CLI_BIN="/usr/local/bin/easytier-cli"
DEFAULT_GITHUB_MIRRORS=(
  "https://gh.llkk.cc/"
  "https://gh.ddlc.top/"
  "https://gh-proxy.com/"
  "https://ghproxy.net/"
)
FAST_PORT_RANGE_START="8000"
FAST_PORT_RANGE_END="9000"
DEFAULT_EASYTIER_PORT="8301"
EASYTIER_PORT_DEFAULT="$DEFAULT_EASYTIER_PORT"
EASYTIER_PROTOCOL_DEFAULT="tcp"
EASYTIER_PROTOCOLS_DEFAULT="tcp,udp"
EASYTIER_RELAY_SERVICE_NAME="easytier-relay"
EASYTIER_RELAY_SERVICE="/etc/systemd/system/${EASYTIER_RELAY_SERVICE_NAME}.service"

NFT_RULE_FILE="${NFT_DIR}/leikwan-forward.nft"
MSS_CONFIG="${NFT_DIR}/mss.env"
NFT_SERVICE_NAME="leikwan-nft-forward"
NFT_SERVICE="/etc/systemd/system/${NFT_SERVICE_NAME}.service"
FORWARD_SYSCTL="/etc/sysctl.d/99-leikwan-forward.conf"

PBR_STATIC_CONF="${PBR_DIR}/static-routes.conf"
PBR_DOMAIN_TSV="${PBR_DIR}/domain-routes.tsv"
PBR_RESOLVED_DOMAIN_TSV="${PBR_DIR}/resolved-pbr-domains.tsv"
PBR_RT_TABLES="/etc/iproute2/rt_tables"
PBR_PRIORITY="15000"
DDNS_REFRESH_INTERVAL_DEFAULT="5min"
DDNS_REFRESH_FORWARDS_DEFAULT="true"
DDNS_REFRESH_ENTRIES_DEFAULT="true"
DDNS_REFRESH_PBR_DEFAULT="true"
DDNS_AUTO_APPLY_DEFAULT="true"
DDNS_AUTO_FIX_ROUTE_DEFAULT="false"
DDNS_AUTO_SYNC_FORWARD_PBR_DEFAULT="true"
DDNS_AUTO_SYNC_DOMAIN_PBR_DEFAULT="true"
DDNS_ENTRY_AUTO_RESTART_RELAY_DEFAULT="false"
DDNS_KEEP_OLD_ON_FAIL_DEFAULT="true"

BBR_SYSCTL_CONF="/etc/sysctl.d/99-leikwan-bbr.conf"
DNS_RESOLVED_CONF="/etc/systemd/resolved.conf.d/99-leikwan-dns.conf"
SHORTCUT_LQ="/usr/local/bin/lq"
SHORTCUT_LQ_UPPER="/usr/local/bin/LQ"

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

on_error() {
  local rc=$?
  echo "${RED}错误：脚本在第 ${1:-unknown} 行退出，状态 ${rc}${RESET}" >&2
  exit "$rc"
}
trap 'on_error "$LINENO"' ERR

log() {
  (( LOG_DISABLED == 1 )) && return 0
  [[ ${EUID:-$(id -u)} -eq 0 ]] || return 0
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

ok() { echo "${GREEN}[OK]${RESET} $*"; log "OK $*"; }
info() { echo "${BLUE}[INFO]${RESET} $*"; log "INFO $*"; }
warn() { echo "${YELLOW}[WARN]${RESET} $*"; log "WARN $*"; }
fail() { echo "${RED}[FAIL]${RESET} $*" >&2; log "FAIL $*"; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "请使用 root 运行，例如：sudo bash leikwan-toolkit.sh"
    exit 1
  fi
}

need_root_unless_dry_run() {
  (( DRY_RUN == 1 )) && return 0
  need_root
}

normalize_menu_choice() {
  local s="$1"
  s="${s//$'\r'/}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

prompt_menu_choice() {
  local prompt="$1" value
  if ! read -r -p "$prompt" value; then
    info "检测到非交互输入结束，已退出菜单。"
    exit 0
  fi
  normalize_menu_choice "$value"
}

prompt_value() {
  local prompt="$1" default="${2:-}" value
  if [[ -n "$default" ]]; then
    read -r -p "${prompt} [${default}]: " value || value=""
    value="$(normalize_menu_choice "$value")"
    printf '%s' "${value:-$default}"
  else
    read -r -p "${prompt}: " value || value=""
    normalize_menu_choice "$value"
  fi
}

prompt_yes_no() {
  local prompt="$1" default="${2:-N}" answer suffix
  [[ "$default" =~ ^[Yy]$ ]] && suffix="[Y/n]" || suffix="[y/N]"
  while true; do
    read -r -p "${prompt} ${suffix} " answer || answer=""
    answer="$(normalize_menu_choice "$answer")"
    answer="${answer:-$default}"
    answer="${answer,,}"
    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "请输入 y 或 n。" ;;
    esac
  done
}

is_interactive() {
  [[ -t 0 && -t 1 ]]
}

clear_screen_if_interactive() {
  [[ "${LEIKWAN_NO_CLEAR:-0}" == "1" ]] && return 0
  [[ -t 1 ]] || return 0
  if command -v tput >/dev/null 2>&1 && [[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    tput clear || printf '\033[H\033[2J'
  else
    printf '\033[H\033[2J'
  fi
}

wait_enter_to_return() {
  is_interactive || return 0
  printf '\n按回车继续...'
  local _answer
  IFS= read -r _answer || true
}

terminal_cols() {
  if [[ -n "${LEIKWAN_COLUMNS:-}" && "${LEIKWAN_COLUMNS}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$LEIKWAN_COLUMNS"
    return 0
  fi
  if is_interactive && command -v tput >/dev/null 2>&1 && [[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    tput cols 2>/dev/null || printf '80\n'
  else
    printf '120\n'
  fi
}

display_width() {
  local value="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, unicodedata; s=sys.argv[1]; print(sum(0 if unicodedata.combining(ch) else 2 if unicodedata.east_asian_width(ch) in ("F", "W") else 1 for ch in s))' "$value" 2>/dev/null && return 0
  fi
  printf '%s' "$value" | awk '{print length($0)}'
}

pad_display_width() {
  local value="$1" width="$2" current
  current="$(display_width "$value")"
  printf '%s' "$value"
  if [[ "$current" =~ ^[0-9]+$ ]] && (( current < width )); then
    printf '%*s' "$((width - current))" ''
  fi
}

should_render_table() {
  local min_cols="$1" cols
  [[ "${LEIKWAN_COMPACT:-0}" == "1" ]] && return 1
  cols="$(terminal_cols)"
  if [[ "${LEIKWAN_TABLE:-0}" == "1" ]]; then
    (( cols >= min_cols )) && return 0
    return 1
  fi
  (( cols >= min_cols ))
}

render_tsv_compact() {
  local labels="$1"
  awk -F'\t' -v labels="$labels" '
    BEGIN { split(labels, label, "\t") }
    NF {
      print $1 " " $2
      for (i = 3; i <= NF; i++) {
        value = ($i == "" ? "-" : $i)
        print "   " label[i] ": " value
      }
      print ""
    }
  '
}

render_tsv_table() {
  local min_cols="$1" labels="$2" rows cols tmp
  rows="$(cat || true)"
  [[ -n "$rows" ]] || return 0
  cols="$(terminal_cols)"
  if should_render_table "$min_cols" && command -v python3 >/dev/null 2>&1; then
    tmp="$(mktemp)"
    printf '%s\n' "$rows" >"$tmp"
    if python3 - "$labels" "$cols" "$tmp" <<'PY'
import sys
import unicodedata

labels = sys.argv[1].split("\t")
cols = int(sys.argv[2])
path = sys.argv[3]

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    rows = [line.rstrip("\n").split("\t") for line in fh if line.strip()]

if not rows:
    sys.exit(0)

columns = len(labels)
for row in rows:
    if len(row) < columns:
        row.extend([""] * (columns - len(row)))

def cell_width(value):
    total = 0
    for ch in value:
        if unicodedata.combining(ch):
            continue
        total += 2 if unicodedata.east_asian_width(ch) in ("F", "W") else 1
    return total

def pad(value, width):
    return value + " " * max(width - cell_width(value), 0)

widths = []
for idx, label in enumerate(labels):
    widths.append(max([cell_width(label)] + [cell_width(row[idx]) for row in rows]))

total_width = sum(widths) + (2 * (columns - 1))
if total_width > cols:
    sys.exit(2)

print("  ".join(pad(labels[idx], widths[idx]) for idx in range(columns)))
for row in rows:
    print("  ".join(pad(row[idx], widths[idx]) for idx in range(columns)))
PY
    then
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
  fi
  render_tsv_compact "$labels" <<<"$rows"
}

print_compact_header() {
  local title="$1"
  echo
  echo "${BOLD}${title}${RESET}"
  echo "----------------------------------------"
}

print_menu_header() {
  local title="$1"
  clear_screen_if_interactive
  print_compact_header "$title"
}

menu_input_required() {
  warn "请输入选项编号。"
  wait_enter_to_return
}

menu_invalid_choice() {
  warn "无效选择。"
  wait_enter_to_return
}

warn_and_pause() {
  warn "$1"
  pause_after_action
}

pause_after_action() {
  if (( MENU_ACTION_PAUSE_DONE == 1 )); then
    MENU_ACTION_PAUSE_DONE=0
    return 0
  fi
  wait_enter_to_return
}

run_menu_action_pause() {
  local rc
  set +e
  "$@"
  rc=$?
  set -e
  pause_after_action
  return "$rc"
}

run_menu_action() {
  run_menu_action_pause "$@"
}

is_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

is_easytier_protocol() {
  case "$1" in
    tcp|udp|ws|wss) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_easytier_protocols() {
  local value="$1"
  value="$(normalize_menu_choice "$value")"
  value="${value,,}"
  value="${value//[[:space:]]/}"
  value="${value//+/,}"
  case "$value" in
    tcp,udp|udp,tcp|dual|both) printf '%s' "tcp,udp" ;;
    tcp|udp) printf '%s' "$value" ;;
    *) return 1 ;;
  esac
}

easytier_protocols_display() {
  local protocols
  protocols="$(normalize_easytier_protocols "$1" 2>/dev/null || printf '%s' "$1")"
  case "$protocols" in
    tcp,udp) printf '%s' "tcp+udp" ;;
    *) printf '%s' "$protocols" ;;
  esac
}

easytier_legacy_protocol() {
  local protocols
  protocols="$(normalize_easytier_protocols "$1")" || return 1
  case ",${protocols}," in
    *,tcp,*) printf '%s' "tcp" ;;
    *,udp,*) printf '%s' "udp" ;;
    *) return 1 ;;
  esac
}

easytier_protocols_has() {
  local protocols="$1" proto="$2"
  protocols="$(normalize_easytier_protocols "$protocols")" || return 1
  [[ ",${protocols}," == *",${proto},"* ]]
}

easytier_urls() {
  local host="$1" protocols="$2" port="$3"
  protocols="$(normalize_easytier_protocols "$protocols")" || return 1
  if easytier_protocols_has "$protocols" tcp; then
    printf 'tcp://%s:%s\n' "$host" "$port"
  fi
  if easytier_protocols_has "$protocols" udp; then
    printf 'udp://%s:%s\n' "$host" "$port"
  fi
}

looks_like_domain() {
  local value="$1"
  [[ "$value" =~ [A-Za-z] && "$value" == *.* ]]
}

is_domain_name() {
  local value="$1"
  [[ -n "$value" && ! "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && "$value" =~ [A-Za-z] ]]
}

prompt_port() {
  local prompt="$1" default="$2" value
  while true; do
    value="$(prompt_value "$prompt" "$default")"
    is_port "$value" && printf '%s' "$value" && return 0
    echo "端口必须是 1-65535。"
  done
}

prompt_required_port() {
  local prompt="$1" value
  while true; do
    if ! read -r -p "${prompt}: " value; then
      info "检测到非交互输入结束，已退出。"
      exit 0
    fi
    value="$(normalize_menu_choice "$value")"
    if [[ -z "$value" ]]; then
      echo "[WARN] 后端目标端口不能为空，请输入 1-65535。" >&2
      continue
    fi
    is_port "$value" && printf '%s' "$value" && return 0
    echo "[WARN] 端口必须是 1-65535。" >&2
  done
}

prompt_easytier_ip() {
  local prompt="$1" default="$2" value
  while true; do
    value="$(prompt_value "$prompt" "$default")"
    if is_ipv4 "$value"; then
      printf '%s' "$value"
      return 0
    fi
    if looks_like_domain "$value"; then
      warn "你输入的是域名，不是 EasyTier 虚拟 IP。请填写 10.198.1.x 这类虚拟 IP。"
      warn "这里必须填写 EasyTier 虚拟 IP，例如 ${default}；DDNS 域名请在后面的 本机公网 IP / 域名 填写。"
    else
      warn "EasyTier IP 必须是 IPv4：${value}"
      warn "这里必须填写 EasyTier 虚拟 IP，例如 ${default}；DDNS 域名请在后面的 本机公网 IP / 域名 填写。"
    fi
  done
}

prompt_easytier_protocols() {
  local prompt="$1" default="$2" value
  while true; do
    value="$(prompt_value "$prompt" "$(easytier_protocols_display "$default")")"
    if value="$(normalize_easytier_protocols "$value")"; then
      printf '%s' "$value"
      return 0
    fi
    warn "EasyTier 传输模式无效。请输入 tcp、udp 或 tcp+udp。"
  done
}

prompt_easytier_protocol() {
  prompt_easytier_protocols "$@"
}

is_ipv4() {
  local ip="$1" a b c d
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<<"$ip"
  for x in "$a" "$b" "$c" "$d"; do (( x >= 0 && x <= 255 )) || return 1; done
}

normalize_ipv4_cidr() {
  local value="$1" ip prefix
  value="$(normalize_menu_choice "$value")"
  [[ -n "$value" ]] || return 1
  if [[ "$value" == */* ]]; then
    ip="${value%/*}"
    prefix="${value#*/}"
    is_ipv4 "$ip" || return 1
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 )) || return 1
    printf '%s/%s' "$ip" "$prefix"
  else
    is_ipv4 "$value" || return 1
    printf '%s/32' "$value"
  fi
}

prompt_host() {
  local prompt="$1" default="${2:-}" value
  while true; do
    value="$(prompt_value "$prompt" "$default")"
    [[ -n "$value" && ! "$value" =~ [[:space:]/] ]] && printf '%s' "$value" && return 0
    echo "请输入 IP 或域名，不要包含协议、端口或空格。"
  done
}

safe_name() {
  local name="$1"
  name="$(normalize_menu_choice "$name")"
  if [[ "$name" =~ ^公网([0-9]+)$ ]]; then
    printf 'public%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  name="${name// /-}"
  name="$(printf '%s' "$name" | sed -E 's/[^A-Za-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$name" ]] || name="default"
  printf '%s' "$name"
}

entry_display_name() {
  local name="$1"
  if [[ "$name" =~ ^public([0-9]+)$ ]]; then
    printf '公网%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$name"
  fi
}

entry_label() {
  local name="$1" display
  display="$(entry_display_name "$name")"
  if [[ "$display" != "$name" ]]; then
    printf '%s(%s)' "$display" "$name"
  else
    printf '%s' "$name"
  fi
}

normalize_entry_selector() {
  local value="$1"
  value="$(normalize_menu_choice "$value")"
  if [[ "$value" =~ ^公网([0-9]+)$ ]]; then
    printf 'public%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$value"
  fi
}

backup_file() {
  local path="$1" safe dest
  [[ -e "$path" ]] || return 0
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 备份 ${path}"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  safe="${path#/}"; safe="${safe//\//__}"
  dest="${BACKUP_DIR}/${safe}.$(date '+%Y%m%d-%H%M%S').bak"
  cp -a "$path" "$dest"
  ok "已备份 ${path} -> ${dest}"
}

write_file() {
  local path="$1" content="$2" mode="${3:-600}" tmp
  if (( DRY_RUN == 1 )); then
    echo
    echo "${BOLD}[DRY-RUN] ${path}${RESET}"
    printf '%s\n' "$content"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp)"
  printf '%s\n' "$content" >"$tmp"
  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    return 0
  fi
  backup_file "$path"
  install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
  ok "已写入 ${path}"
}

confirm_summary() {
  local title="$1" summary="$2"
  echo
  echo "${BOLD}${title}${RESET}"
  echo "----------------------------------------"
  printf '%b\n' "$summary"
  echo "----------------------------------------"
  if (( DRY_RUN == 1 )); then
    prompt_yes_no "确认生成以上预览吗？" "Y"
  else
    prompt_yes_no "确认写入 / 执行吗？" "N"
  fi
}

print_banner() {
  cat <<EOF
Leikwan Toolkit ${TOOL_VERSION}
${PROJECT_TITLE}
GitHub: ${PROJECT_GITHUB}
-------------------------------------------------
EOF
}

print_help() {
  cat <<EOF
${PROJECT_NAME} ${TOOL_VERSION}

用法：
  sudo bash leikwan-toolkit.sh
  sudo bash leikwan-toolkit.sh status
  sudo bash leikwan-toolkit.sh --status
  sudo bash leikwan-toolkit.sh --doctor
  sudo bash leikwan-toolkit.sh --doctor --verbose
  sudo bash leikwan-toolkit.sh port check
  sudo bash leikwan-toolkit.sh --port-check
  sudo bash leikwan-toolkit.sh config export [--full|--redacted]
  sudo bash leikwan-toolkit.sh config inspect /path/to/leikwan-config.tar.gz
  sudo bash leikwan-toolkit.sh config import /path/to/leikwan-config.tar.gz [--mode config-only|apply|full] [--yes]
  sudo bash leikwan-toolkit.sh config list
  sudo bash leikwan-toolkit.sh output generate|show|json|html|qr
  sudo bash leikwan-toolkit.sh pair relay-init
  sudo bash leikwan-toolkit.sh pair entry-join [pairing-file|-]
  sudo bash leikwan-toolkit.sh pair relay-join [pairing-file|-]
  sudo bash leikwan-toolkit.sh pair status
  sudo bash leikwan-toolkit.sh entry expose-range [--range 10000-19999] [--relay-ip 10.198.1.1]
  sudo bash leikwan-toolkit.sh forward add
  sudo bash leikwan-toolkit.sh forward edit [name]
  sudo bash leikwan-toolkit.sh forward delete [name]
  sudo bash leikwan-toolkit.sh forward list
  sudo bash leikwan-toolkit.sh forward apply-relay
  sudo bash leikwan-toolkit.sh forward apply-relay --auto-fix-route
  sudo bash leikwan-toolkit.sh pbr delete 203.0.113.10/32
  sudo bash leikwan-toolkit.sh pbr sync-from-forwards
  sudo bash leikwan-toolkit.sh pbr domain add|list|delete|sync
  sudo bash leikwan-toolkit.sh update check
  sudo bash leikwan-toolkit.sh update run
  sudo bash leikwan-toolkit.sh update status
  sudo bash leikwan-toolkit.sh update rollback
  sudo bash leikwan-toolkit.sh ddns run
  sudo bash leikwan-toolkit.sh ddns run --scope forwards|entries|pbr|all
  sudo bash leikwan-toolkit.sh ddns status
  sudo bash leikwan-toolkit.sh ddns enable
  sudo bash leikwan-toolkit.sh ddns disable
  sudo bash leikwan-toolkit.sh ddns logs
  sudo bash leikwan-toolkit.sh --self-update
  sudo bash leikwan-toolkit.sh --update-check
  sudo bash leikwan-toolkit.sh --ddns-run
  sudo bash leikwan-toolkit.sh --pbr-apply
  sudo bash leikwan-toolkit.sh --pbr-delete 203.0.113.10/32
  sudo bash leikwan-toolkit.sh --uninstall
  bash leikwan-toolkit.sh --help
  bash leikwan-toolkit.sh --version

定位：
  公网入口 + 利群主机 + 后端目标的三段 TCP/UDP 转发组网工具。
  传输层使用 EasyTier，转发层使用 nftables。
  默认 EasyTier 虚拟网段：${ET_NET}，relay：${RELAY_ET_IP}。
  默认 EasyTier 传输：TCP+UDP / ${DEFAULT_EASYTIER_PORT}，位于利群推荐白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}。
  DDNS 自动刷新可监控域名后端 IP 变化，并安全重应用转发规则。
  自更新只从 GitHub Release 包更新，并校验 sha256。
  不部署后端协议，不生成代理客户端链接。

一键安装：
  curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
  # 管道方式只安装，不自动进入菜单：
  curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh | bash
  lq

如果 GitHub 下载慢，可设置：
  export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
EOF
}

migrate_legacy_paths() {
  (( DRY_RUN == 1 )) && return 0
  if [[ -d "$OLD_STATE_DIR" ]]; then
    if [[ ! -e "$STATE_DIR" ]]; then
      mkdir -p "$(dirname "$STATE_DIR")"
      mv "$OLD_STATE_DIR" "$STATE_DIR"
      ok "已迁移状态目录：${OLD_STATE_DIR} -> ${STATE_DIR}"
    else
      warn "检测到旧状态目录 ${OLD_STATE_DIR}；当前优先使用 ${STATE_DIR}，确认无用后可清理旧目录。"
    fi
  fi
  if [[ -d "$OLD_BACKUP_DIR" ]]; then
    if [[ ! -e "$BACKUP_DIR" ]]; then
      mkdir -p "$(dirname "$BACKUP_DIR")"
      mv "$OLD_BACKUP_DIR" "$BACKUP_DIR"
      ok "已迁移备份目录：${OLD_BACKUP_DIR} -> ${BACKUP_DIR}"
    else
      warn "检测到旧备份目录 ${OLD_BACKUP_DIR}；当前优先使用 ${BACKUP_DIR}。"
    fi
  fi
  if [[ -f "$OLD_LOG_FILE" ]]; then
    if [[ ! -e "$LOG_FILE" ]]; then
      mkdir -p "$(dirname "$LOG_FILE")"
      mv "$OLD_LOG_FILE" "$LOG_FILE"
      ok "已迁移日志文件：${OLD_LOG_FILE} -> ${LOG_FILE}"
    else
      warn "检测到旧日志文件 ${OLD_LOG_FILE}；当前优先使用 ${LOG_FILE}。"
    fi
  fi
}

ensure_base_dirs() {
  if (( DRY_RUN == 0 )); then
    migrate_legacy_paths
    install -d -m 700 "$STATE_DIR" "$ENTRY_DIR" "$ENTRIES_DIR" "$FORWARDS_DIR" "$OUTPUT_DIR" "$NFT_DIR" "$PBR_DIR" "$EASYTIER_DIR" "$STATUS_DIR" "$SNAPSHOT_DIR" "$AUTO_SNAPSHOT_DIR"
  fi
}

package_command() {
  case "$1" in
    iproute2) printf '%s' ip ;;
    curl) printf '%s' curl ;;
    jq) printf '%s' jq ;;
    tar) printf '%s' tar ;;
    unzip) printf '%s' unzip ;;
    nftables) printf '%s' nft ;;
    netcat-openbsd) printf '%s' nc ;;
    iptables-persistent) printf '%s' ip6tables-save ;;
    ca-certificates) printf '%s' "" ;;
    coreutils) printf '%s' base64 ;;
    openssl) printf '%s' openssl ;;
    *) printf '%s' "$1" ;;
  esac
}

install_packages() {
  local packages=("$@") missing=() pkg cmd
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] apt-get install ${packages[*]}"
    return 0
  fi
  for pkg in "${packages[@]}"; do
    case " ${DEPS_INSTALLED_THIS_RUN} " in *" ${pkg} "*) continue ;; esac
    cmd="$(package_command "$pkg")"
    if [[ -n "$cmd" ]] && command -v "$cmd" >/dev/null 2>&1; then
      continue
    fi
    if [[ -z "$cmd" && -f "$DEPS_MARKER" ]]; then
      continue
    fi
    missing+=("$pkg")
  done
  ((${#missing[@]} > 0)) || return 0
  ensure_base_dirs
  export DEBIAN_FRONTEND=noninteractive
  if (( DEPS_APT_UPDATED == 0 )); then
    if ! apt-get update; then
      warn "apt-get update 失败，依赖无法自动安装：${missing[*]}"
      warn "如果 apt 源返回 403 或 mirror sync in progress，请换源、稍后重试，或手动安装对应 deb 包后重试。"
      return 1
    fi
    DEPS_APT_UPDATED=1
  fi
  if ! apt-get install -y "${missing[@]}"; then
    warn "apt 安装依赖失败：${missing[*]}"
    warn "如果 apt 源返回 403 或 mirror sync in progress，请换源、稍后重试，或手动安装对应 deb 包后重试。"
    return 1
  fi
  for pkg in "${missing[@]}"; do
    cmd="$(package_command "$pkg")"
    [[ -z "$cmd" ]] && continue
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "依赖 ${pkg} 安装后仍未找到命令：${cmd}"
      return 1
    fi
  done
  for pkg in "${missing[@]}"; do
    DEPS_INSTALLED_THIS_RUN="${DEPS_INSTALLED_THIS_RUN} ${pkg}"
  done
  date '+%F %T' >"$DEPS_MARKER"
}

detect_public_ipv4() {
  curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null ||
    curl -4 -fsS --max-time 8 https://ifconfig.me 2>/dev/null ||
    hostname -I 2>/dev/null | awk '{print $1}'
}

env_file_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  awk -F= -v k="$key" '
    $1 == k {
      sub(/^[^=]*=/, "")
      gsub(/\r$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
}

status_now() {
  date '+%F %T'
}

write_status_cache() {
  local kind="$1" result="$2" action="${3:-}" file prefix
  (( DRY_RUN == 1 )) && return 0
  [[ ${EUID:-$(id -u)} -eq 0 ]] || return 0
  mkdir -p "$STATUS_DIR" 2>/dev/null || return 0
  case "$kind" in
    apply) file="${STATUS_DIR}/last-apply.env"; prefix="LAST_APPLY" ;;
    doctor) file="${STATUS_DIR}/last-doctor.env"; prefix="LAST_DOCTOR" ;;
    status) file="${STATUS_DIR}/last-status.env"; prefix="LAST_STATUS" ;;
    *) return 0 ;;
  esac
  {
    printf '%s_TIME=%s\n' "$prefix" "$(status_now)"
    [[ -n "$action" ]] && printf '%s_ACTION=%s\n' "$prefix" "$action"
    printf '%s_RESULT=%s\n' "$prefix" "$result"
    printf '%s_VERSION=%s\n' "$prefix" "$TOOL_VERSION"
  } >"$file"
  chmod 600 "$file" 2>/dev/null || true
}

write_named_status() {
  local file="$1" prefix="$2" result="$3" mode="${4:-}" path="${5:-}"
  (( DRY_RUN == 1 )) && return 0
  [[ ${EUID:-$(id -u)} -eq 0 ]] || return 0
  mkdir -p "$STATUS_DIR" 2>/dev/null || return 0
  {
    printf '%s_TIME=%s\n' "$prefix" "$(status_now)"
    [[ -n "$mode" ]] && printf '%s_MODE=%s\n' "$prefix" "$mode"
    [[ -n "$path" ]] && printf '%s_PATH=%s\n' "$prefix" "$path"
    printf '%s_RESULT=%s\n' "$prefix" "$result"
    printf '%s_VERSION=%s\n' "$prefix" "$TOOL_VERSION"
  } >"$file"
  chmod 600 "$file" 2>/dev/null || true
}

status_result_from_counts() {
  if (( REPORT_FAIL_COUNT > 0 )); then
    printf 'fail'
  elif (( REPORT_WARN_COUNT > 0 )); then
    printf 'warn'
  else
    printf 'ok'
  fi
}

status_result_display() {
  case "${1,,}" in
    ok) printf 'OK' ;;
    warn) printf 'WARN' ;;
    fail) printf 'FAIL' ;;
    *) printf '%s' "${1:-unknown}" ;;
  esac
}

lock_acquire() {
  local lock_path="$1" label="$2" out_var="$3" fd token lock_dir
  if command -v flock >/dev/null 2>&1; then
    exec {fd}>"$lock_path"
    if flock -n "$fd"; then
      printf -v "$out_var" 'flock:%s:%s' "$fd" "$lock_path"
      return 0
    fi
    eval "exec ${fd}>&-"
  else
    lock_dir="${lock_path}.d"
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" >"${lock_dir}/pid" 2>/dev/null || true
      printf -v "$out_var" 'mkdir:%s' "$lock_dir"
      return 0
    fi
  fi
  warn "已有 Leikwan 任务运行中，跳过本次 ${label}。"
  return 1
}

lock_release() {
  local token="$1" rest fd lock_dir
  [[ -n "$token" ]] || return 0
  case "$token" in
    flock:*)
      rest="${token#flock:}"
      fd="${rest%%:*}"
      eval "exec ${fd}>&-" 2>/dev/null || true
      ;;
    mkdir:*)
      lock_dir="${token#mkdir:}"
      rm -rf "$lock_dir"
      ;;
  esac
}

global_lock_acquire() {
  if [[ -n "$LEIKWAN_GLOBAL_LOCK_TOKEN" ]]; then
    return 0
  fi
  lock_acquire "$LEIKWAN_LOCK_PATH" "任务" LEIKWAN_GLOBAL_LOCK_TOKEN
}

global_lock_release() {
  [[ -n "$LEIKWAN_GLOBAL_LOCK_TOKEN" ]] || return 0
  lock_release "$LEIKWAN_GLOBAL_LOCK_TOKEN"
  LEIKWAN_GLOBAL_LOCK_TOKEN=""
}

ensure_nc_for_test() {
  command -v nc >/dev/null 2>&1 && return 0
  if is_interactive; then
    warn "未找到 nc，链路测试需要 netcat-openbsd。"
    if prompt_yes_no "是否现在安装 netcat-openbsd？" "Y"; then
      install_packages netcat-openbsd || true
      command -v nc >/dev/null 2>&1 && return 0
    fi
  else
    warn "未找到 nc，请执行：apt-get install -y netcat-openbsd"
  fi
  return 1
}

tcp_reachable() {
  local host="$1" port="$2"
  command -v nc >/dev/null 2>&1 || return 2
  nc -vz -w 3 "$host" "$port" >/dev/null 2>&1
}

tcp_reachable_status() {
  local rc=0
  tcp_reachable "$@" || rc=$?
  printf '%s' "$rc"
}

udp_probe() {
  local host="$1" port="$2"
  command -v nc >/dev/null 2>&1 || return 2
  nc -uvz -w 3 "$host" "$port" >/dev/null 2>&1
}

udp_probe_status() {
  local rc=0
  udp_probe "$@" || rc=$?
  printf '%s' "$rc"
}

is_fast_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= FAST_PORT_RANGE_START && port <= FAST_PORT_RANGE_END ))
}

warn_if_slow_easytier_port() {
  local port="$1"
  if ! is_fast_port "$port"; then
    warn "当前 EasyTier 端口 ${port} 不在利群推荐白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}，可能导致高延迟。"
    return 1
  fi
  return 0
}

confirm_easytier_port() {
  local port="$1"
  warn_if_slow_easytier_port "$port" && return 0
  prompt_yes_no "是否继续使用该端口？" "N"
}

normalize_easytier_port() {
  local port="$1"
  if [[ "$port" == "11010" ]]; then
    warn "检测到旧配对码使用 11010，不在利群推荐白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}。"
    if prompt_yes_no "是否自动改为推荐白名单端口 ${DEFAULT_EASYTIER_PORT}？" "Y"; then
      port="$DEFAULT_EASYTIER_PORT"
    fi
  fi
  confirm_easytier_port "$port" || return 1
  printf '%s' "$port"
}

easytier_protocols_from_env() {
  local file="$1" protocols_key="$2" protocol_key="$3" default="${4:-$EASYTIER_PROTOCOLS_DEFAULT}" value
  value="$(env_file_get "$file" "$protocols_key")"
  if [[ -n "$value" ]]; then
    normalize_easytier_protocols "$value"
    return
  fi
  value="$(env_file_get "$file" "$protocol_key")"
  if [[ -n "$value" ]]; then
    normalize_easytier_protocols "$value"
    return
  fi
  normalize_easytier_protocols "$default"
}

easytier_port_from_env() {
  local file="$1" protocols="$2" tcp_key="$3" udp_key="$4" legacy_key="$5"
  local tcp_port udp_port port
  tcp_port="$(env_file_get "$file" "$tcp_key")"
  udp_port="$(env_file_get "$file" "$udp_key")"
  port="$(env_file_get "$file" "$legacy_key")"
  if easytier_protocols_has "$protocols" tcp && [[ -n "$tcp_port" ]]; then
    port="$tcp_port"
  elif easytier_protocols_has "$protocols" udp && [[ -n "$udp_port" ]]; then
    port="$udp_port"
  fi
  [[ -n "$port" ]] || port="$EASYTIER_PORT_DEFAULT"
  if easytier_protocols_has "$protocols" tcp && easytier_protocols_has "$protocols" udp &&
     [[ -n "$tcp_port" && -n "$udp_port" && "$tcp_port" != "$udp_port" ]]; then
    fail "当前 entries.tsv 只支持 TCP/UDP 使用同一个 EasyTier 端口：tcp=${tcp_port} udp=${udp_port}"
    return 1
  fi
  normalize_easytier_port "$port"
}

random_hex() {
  local bytes="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
  else
    od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
  fi
}

ensure_tsv_files() {
  ensure_base_dirs
  [[ -f "$ENTRIES_TSV" ]] || write_file "$ENTRIES_TSV" $'# entry_name\tpublic_host\tet_ip\teasytier_protocol\teasytier_port\tweight\tenabled' 600
  [[ -f "$RESOLVED_ENTRIES_TSV" ]] || write_file "$RESOLVED_ENTRIES_TSV" $'# name\tpublic_host\tresolved_ip\tlast_checked\tlast_changed' 600
  [[ -f "$FORWARDS_TSV" ]] || write_file "$FORWARDS_TSV" $'# name\tentry_port\ttarget_host\ttarget_port\tout_iface\troute_table\tenabled\tcomment' 600
  [[ -f "$PBR_DOMAIN_TSV" ]] || write_file "$PBR_DOMAIN_TSV" $'# name\thost\troute_table\tenabled\tcomment' 600
  [[ -f "$PBR_RESOLVED_DOMAIN_TSV" ]] || write_file "$PBR_RESOLVED_DOMAIN_TSV" $'# name\thost\tresolved_ip\troute_table\tlast_checked\tlast_changed' 600
}

resolve_ipv4_first() {
  local host="$1"
  if is_ipv4 "$host"; then printf '%s' "$host"; return 0; fi
  getent ahostsv4 "$host" 2>/dev/null | awk '$1 ~ /^[0-9]+\./ {print $1; exit}' ||
    getent ahosts "$host" 2>/dev/null | awk '$1 ~ /^[0-9]+\./ {print $1; exit}'
}

easytier_validate_help() {
  "$EASYTIER_CORE_BIN" --help >/dev/null 2>&1 || return 1
  "$EASYTIER_CLI_BIN" --help >/dev/null 2>&1 || return 1
}

easytier_help_has() {
  "$EASYTIER_CORE_BIN" --help 2>&1 | grep -q -- "$1"
}

easytier_help_text() {
  "$EASYTIER_CORE_BIN" --help 2>&1 || true
}

easytier_disable_listener_arg() {
  local help opt
  help="$(easytier_help_text)"
  for opt in --no-listener --no-listeners --disable-listener --disable-listeners; do
    if grep -Fq -- "$opt" <<<"$help"; then
      printf '%q ' "$opt"
      return 0
    fi
  done
  return 1
}

easytier_arch_family() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s' 'x86_64' ;;
    aarch64|arm64) printf '%s' 'aarch64' ;;
    *) fail "暂不支持自动安装 EasyTier 的架构：$(uname -m)"; return 1 ;;
  esac
}

easytier_asset_names() {
  local version="$1" no_v="${1#v}" arch="$2"
  case "$arch" in
    x86_64)
      printf '%s\n' \
        "easytier-linux-x86_64-${version}.zip" \
        "easytier-linux-amd64-${version}.zip" \
        "easytier_${no_v}_linux_amd64.tar.gz" \
        "easytier-${version}-linux-amd64.tar.gz"
      ;;
    aarch64)
      printf '%s\n' \
        "easytier-linux-aarch64-${version}.zip" \
        "easytier-linux-arm64-${version}.zip" \
        "easytier_${no_v}_linux_arm64.tar.gz" \
        "easytier-${version}-linux-arm64.tar.gz"
      ;;
  esac
}

dl_info() { printf '[INFO] %s\n' "$*" >&2; }
dl_warn() { printf '[WARN] %s\n' "$*" >&2; }
dl_ok() { printf '[OK] %s\n' "$*" >&2; }
dl_fail() { printf '[FAIL] %s\n' "$*" >&2; }

easytier_api_asset_url() {
  local version="$1" arch="$2" api re tmp result
  if ! command -v curl >/dev/null 2>&1; then
    dl_warn "未安装 curl，无法获取 GitHub release metadata。"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    dl_warn "未安装 jq，跳过 GitHub release metadata，将使用内置候选 URL。"
    return 1
  fi
  api="https://api.github.com/repos/EasyTier/EasyTier/releases/tags/${version}"
  case "$arch" in
    x86_64) re='linux.*(x86_64|amd64).*\.(zip|tar\.gz|tgz)$' ;;
    aarch64) re='linux.*(aarch64|arm64).*\.(zip|tar\.gz|tgz)$' ;;
    *) return 1 ;;
  esac
  tmp="$(mktemp)"
  dl_info "正在获取 EasyTier release 信息：${api}"
  if ! curl -fsSL --connect-timeout 10 --max-time 30 -H 'Accept: application/vnd.github+json' -o "$tmp" "$api"; then
    dl_warn "无法获取 GitHub release metadata，将使用内置候选 URL。"
    rm -f "$tmp"
    return 1
  fi
  dl_ok "已获取 release 信息。"
  if ! result="$(jq -r --arg re "$re" '.assets[]? | select(.name | test($re; "i")) | .browser_download_url' "$tmp" | head -n 1)"; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  [[ -n "$result" && "$result" != "null" ]] || return 1
  printf '%s\n' "$result"
}

trim_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

github_raw_to_github_url() {
  local url="$1"
  if [[ "$url" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.*)$ ]]; then
    printf 'https://github.com/%s/%s/raw/%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
    return 0
  fi
  return 1
}

mirror_url_for() {
  local mirror="$1" raw_url="$2" github_url
  mirror="${mirror%/}"
  if [[ "$mirror" == *"{url}"* ]]; then
    printf '%s\n' "${mirror//\{url\}/$raw_url}"
    return 0
  fi
  if [[ "$mirror" == */https://github.com ]]; then
    if [[ "$raw_url" == https://github.com/* ]]; then
      printf '%s/%s\n' "$mirror" "${raw_url#https://github.com/}"
      return 0
    fi
    if github_url="$(github_raw_to_github_url "$raw_url")"; then
      printf '%s/%s\n' "$mirror" "${github_url#https://github.com/}"
      return 0
    fi
  fi
  printf '%s/%s\n' "$mirror" "$raw_url"
}

github_url_candidates() {
  local raw_url="$1" mirrors mirror candidate seen_line
  local -a mirror_list=() seen=()
  mirrors="${LEIKWAN_GITHUB_MIRRORS:-${LEIKWAN_GITHUB_MIRROR:-}}"
  mirrors="${mirrors//;/,}"
  if [[ -n "$mirrors" ]]; then
    IFS=',' read -r -a mirror_list <<<"$mirrors"
  else
    mirror_list=("${DEFAULT_GITHUB_MIRRORS[@]}")
  fi
  for mirror in "${mirror_list[@]}"; do
    mirror="$(trim_spaces "$mirror")"
    [[ -n "$mirror" ]] || continue
    candidate="$(mirror_url_for "$mirror" "$raw_url")"
    for seen_line in "${seen[@]}"; do
      [[ "$seen_line" == "$candidate" ]] && continue 2
    done
    seen+=("$candidate")
    printf '%s\n' "$candidate"
  done
  for seen_line in "${seen[@]}"; do
    [[ "$seen_line" == "$raw_url" ]] && return 0
  done
  printf '%s\n' "$raw_url"
}

download_with_fallback() {
  local raw_url="$1" dest_file="$2" candidate tmp timeout
  timeout="${LEIKWAN_DOWNLOAD_TIMEOUT:-15}"
  tmp="${dest_file}.tmp.$$"
  rm -f "$tmp"
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    dl_info "正在尝试下载：${candidate}"
    if curl -fL --retry 1 --connect-timeout "$timeout" --max-time "$timeout" -o "$tmp" "$candidate"; then
      mv -f "$tmp" "$dest_file"
      dl_ok "下载成功：${candidate}"
      return 0
    fi
    dl_warn "下载失败，尝试下一个地址。"
  done < <(github_url_candidates "$raw_url")
  rm -f "$tmp"
  dl_warn "全部下载地址均失败：${raw_url}"
  return 1
}

download_github_asset() {
  local raw_url="$1" dest_file="$2"
  download_with_fallback "$raw_url" "$dest_file"
}

normalize_version() {
  local version="$1"
  version="${version#v}"
  version="${version#V}"
  if [[ "$version" =~ ^([0-9]+)(\.([0-9]+))?(\.([0-9]+))?$ ]]; then
    printf '%s.%s.%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-0}" "${BASH_REMATCH[5]:-0}"
    return 0
  fi
  return 1
}

version_eq() {
  local left right
  left="$(normalize_version "$1" 2>/dev/null)" || return 1
  right="$(normalize_version "$2" 2>/dev/null)" || return 1
  [[ "$left" == "$right" ]]
}

version_gt() {
  local left right l1 l2 l3 r1 r2 r3
  left="$(normalize_version "$1" 2>/dev/null)" || return 1
  right="$(normalize_version "$2" 2>/dev/null)" || return 1
  IFS=. read -r l1 l2 l3 <<<"$left"
  IFS=. read -r r1 r2 r3 <<<"$right"
  (( l1 > r1 )) && return 0
  (( l1 < r1 )) && return 1
  (( l2 > r2 )) && return 0
  (( l2 < r2 )) && return 1
  (( l3 > r3 ))
}

update_latest_release() {
  local api tmp tag version effective
  command -v curl >/dev/null 2>&1 || { fail "缺少 curl，无法检查 GitHub Release。"; return 1; }
  api="https://api.github.com/repos/${UPDATE_REPO}/releases/latest"
  tmp="$(mktemp)"
  if curl -fsSL --connect-timeout 10 --max-time 30 -H 'Accept: application/vnd.github+json' -o "$tmp" "$api"; then
    if command -v jq >/dev/null 2>&1; then
      tag="$(jq -r '.tag_name // empty' "$tmp" 2>/dev/null || true)"
    else
      tag="$(sed -n 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp" | head -n 1)"
    fi
  fi
  rm -f "$tmp"
  if [[ -z "${tag:-}" ]]; then
    effective="$(curl -fsSLI --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/${UPDATE_REPO}/releases/latest" 2>/dev/null || true)"
    tag="${effective##*/}"
  fi
  version="$(normalize_version "${tag:-}" 2>/dev/null || true)"
  [[ -n "$version" ]] || { fail "无法解析 latest release 版本：${tag:-unknown}"; return 1; }
  printf '%s\t%s\n' "${tag:-v${version}}" "$version"
}

update_release_asset_url() {
  local tag="$1" version="$2" suffix="$3"
  printf 'https://github.com/%s/releases/download/%s/leikwan-toolkit-%s.tar.gz%s\n' "$UPDATE_REPO" "$tag" "$version" "$suffix"
}

update_download_asset() {
  local raw_url="$1" dest_file="$2" candidate tmp mirror seen_line
  local -a seen=()
  tmp="${dest_file}.tmp.$$"
  rm -f "$tmp"
  info "正在下载：${raw_url}"
  if curl -fL --retry 1 --connect-timeout 15 --max-time 120 -o "$tmp" "$raw_url"; then
    mv -f "$tmp" "$dest_file"
    ok "下载成功：${raw_url}"
    return 0
  fi
  warn "GitHub Release 下载失败，正在尝试镜像。"
  while IFS= read -r candidate; do
    [[ -n "$candidate" && "$candidate" != "$raw_url" ]] || continue
    for seen_line in "${seen[@]}"; do
      [[ "$seen_line" == "$candidate" ]] && continue 2
    done
    seen+=("$candidate")
    info "正在尝试镜像：${candidate}"
    if curl -fL --retry 1 --connect-timeout 15 --max-time 120 -o "$tmp" "$candidate"; then
      mv -f "$tmp" "$dest_file"
      ok "下载成功：${candidate}"
      return 0
    fi
    warn "镜像下载失败，尝试下一个地址。"
  done < <(github_url_candidates "$raw_url")
  rm -f "$tmp"
  fail "无法下载最新 release，请检查网络或设置 LEIKWAN_GITHUB_MIRRORS。"
  return 1
}

file_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    fail "缺少 sha256sum 或 shasum，无法校验 release 包。"
    return 1
  fi
}

update_verify_sha256() {
  local archive="$1" sha_file="$2" expected actual
  expected="$(awk 'NF {print $1; exit}' "$sha_file" 2>/dev/null || true)"
  [[ "$expected" =~ ^[A-Fa-f0-9]{64}$ ]] || { fail "sha256 文件格式无效。"; return 1; }
  actual="$(file_sha256 "$archive")" || return 1
  if [[ "${actual,,}" == "${expected,,}" ]]; then
    ok "sha256 校验通过。"
    return 0
  fi
  fail "sha256 校验失败，已取消更新。"
  return 1
}

update_write_status() {
  local result="$1" from="$2" to="$3" backup="$4" source="$5"
  (( DRY_RUN == 1 )) && return 0
  mkdir -p "$STATUS_DIR"
  {
    printf 'LAST_UPDATE_TIME=%s\n' "$(status_now)"
    printf 'LAST_UPDATE_FROM=%s\n' "$from"
    printf 'LAST_UPDATE_TO=%s\n' "$to"
    printf 'LAST_UPDATE_RESULT=%s\n' "$result"
    printf 'LAST_UPDATE_BACKUP=%s\n' "$backup"
    printf 'LAST_UPDATE_SOURCE=%s\n' "$source"
    printf 'LAST_UPDATE_VERSION=%s\n' "$TOOL_VERSION"
  } >"$UPDATE_STATUS_FILE"
  chmod 600 "$UPDATE_STATUS_FILE" 2>/dev/null || true
}

update_status_line() {
  local time from to result
  time="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_TIME)"
  from="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_FROM)"
  to="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_TO)"
  result="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_RESULT)"
  if [[ -z "$time" ]]; then
    printf '无记录'
  else
    printf '%s / %s -> %s / %s' "$time" "${from:-?}" "${to:-?}" "$(status_result_display "$result")"
  fi
}

update_check() {
  local latest tag latest_version current_norm
  latest="$(update_latest_release)" || return 1
  IFS=$'\t' read -r tag latest_version <<<"$latest"
  current_norm="$(normalize_version "$TOOL_VERSION" 2>/dev/null || true)"
  if [[ -z "$current_norm" ]]; then
    warn "本地版本无法解析：${TOOL_VERSION}"
    info "最新版本：${latest_version} (${tag})"
    return 0
  fi
  if version_gt "$latest_version" "$TOOL_VERSION"; then
    info "当前版本：${TOOL_VERSION}"
    info "最新版本：${latest_version}"
    info "可执行：lq update run"
  else
    ok "当前已是最新版本：${TOOL_VERSION}"
  fi
}

update_status() {
  local time from to result backup source
  time="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_TIME)"
  from="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_FROM)"
  to="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_TO)"
  result="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_RESULT)"
  backup="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_BACKUP)"
  source="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_SOURCE)"
  echo "脚本更新状态"
  echo "----------------------------------------"
  echo "current: ${TOOL_VERSION}"
  if [[ -z "$time" ]]; then
    echo "last update: 无记录"
    return 0
  fi
  echo "last update: ${time}"
  echo "from: ${from:-"-"}"
  echo "to: ${to:-"-"}"
  echo "result: ${result:-"-"}"
  echo "backup: ${backup:-"-"}"
  echo "source: ${source%%\?*}"
}

update_prepare_script_from_archive() {
  local archive="$1" dest="$2" extract script
  extract="$(mktemp -d)"
  tar -xzf "$archive" -C "$extract"
  script="$(find "$extract" -type f -name 'leikwan-toolkit.sh' | head -n 1)"
  if [[ -z "$script" ]]; then
    rm -rf "$extract"
    fail "release 包中未找到 leikwan-toolkit.sh。"
    return 1
  fi
  cp -a "$script" "$dest"
  rm -rf "$extract"
}

update_backup_current_script() {
  local dest
  mkdir -p "$BACKUP_DIR"
  dest="${BACKUP_DIR}/root__leikwan-toolkit.sh.$(date '+%Y%m%d-%H%M%S').bak"
  if [[ -f "$UPDATE_TARGET_SCRIPT" ]]; then
    cp -a "$UPDATE_TARGET_SCRIPT" "$dest"
  else
    cp -a "$0" "$dest"
  fi
  printf '%s' "$dest"
}

update_restore_backup() {
  local backup="$1"
  [[ -f "$backup" ]] || { fail "备份脚本不存在：${backup}"; return 1; }
  bash -n "$backup" || { fail "备份脚本 bash -n 校验失败，拒绝回滚。"; return 1; }
  install -m 755 "$backup" "$UPDATE_TARGET_SCRIPT"
  install_shortcuts || true
}

update_run() {
  local force="${1:-0}" update_lock="" tmp="" latest tag latest_version package_url sha_url archive sha_file new_script
  local new_version backup="" old_version="$TOOL_VERSION" installed_version lq_version rc
  local release_global_lock=0
  need_root_unless_dry_run
  command -v curl >/dev/null 2>&1 || { fail "缺少 curl，无法执行自更新。"; return 1; }
  command -v tar >/dev/null 2>&1 || { fail "缺少 tar，无法解压 release 包。"; return 1; }
  if ! lock_acquire "$UPDATE_LOCK_PATH" "更新任务" update_lock; then
    warn "已有更新任务运行中，请稍后再试。"
    return 1
  fi
  if [[ -z "$LEIKWAN_GLOBAL_LOCK_TOKEN" ]]; then
    if ! global_lock_acquire; then
      lock_release "$update_lock"
      return 1
    fi
    release_global_lock=1
  fi
  tmp="$(mktemp -d /tmp/leikwan-update.XXXXXX)"
  set +e
  (
    latest="$(update_latest_release)" || exit 1
    IFS=$'\t' read -r tag latest_version <<<"$latest"
    if normalize_version "$TOOL_VERSION" >/dev/null 2>&1; then
      if ! version_gt "$latest_version" "$TOOL_VERSION"; then
        ok "当前已是最新版本：${TOOL_VERSION}"
        exit 0
      fi
    else
      warn "本地版本无法解析：${TOOL_VERSION}"
      if is_interactive && [[ "$force" != "1" ]]; then
        prompt_yes_no "是否继续更新到 ${latest_version}？" "N" || exit 0
      fi
    fi
    warn "即将替换 ${UPDATE_TARGET_SCRIPT}。"
    info "当前配置目录 ${STATE_DIR} 不会被删除。"
    if is_interactive && [[ "$force" != "1" ]]; then
      prompt_yes_no "是否继续更新？" "N" || exit 0
    fi
    package_url="$(update_release_asset_url "$tag" "$latest_version" "")"
    sha_url="$(update_release_asset_url "$tag" "$latest_version" ".sha256")"
    archive="${tmp}/leikwan-toolkit-${latest_version}.tar.gz"
    sha_file="${archive}.sha256"
    new_script="${tmp}/leikwan-toolkit.sh"
    update_download_asset "$package_url" "$archive" || exit 1
    update_download_asset "$sha_url" "$sha_file" || exit 1
    update_verify_sha256 "$archive" "$sha_file" || exit 1
    update_prepare_script_from_archive "$archive" "$new_script" || exit 1
    bash -n "$new_script" || { fail "新脚本 bash -n 校验失败，已取消更新。"; exit 1; }
    new_version="$(bash "$new_script" --version 2>/dev/null | awk '{print $2; exit}')"
    if ! version_eq "$new_version" "$latest_version"; then
      fail "新脚本版本不符合预期：${new_version:-unknown}，期望 ${latest_version}。"
      exit 1
    fi
    backup="$(update_backup_current_script)" || exit 1
    install -m 755 "$new_script" "$UPDATE_TARGET_SCRIPT" || exit 1
    install_shortcuts || true
    installed_version="$(bash "$UPDATE_TARGET_SCRIPT" --version 2>/dev/null | awk '{print $2; exit}')"
    if ! version_eq "$installed_version" "$latest_version"; then
      warn "替换后版本不符合预期，正在自动恢复备份。"
      update_restore_backup "$backup" || true
      update_write_status "fail" "$old_version" "$latest_version" "$backup" "$package_url"
      exit 1
    fi
    if command -v lq >/dev/null 2>&1; then
      lq_version="$(lq --version 2>/dev/null | awk '{print $2; exit}')"
      if ! version_eq "$lq_version" "$latest_version"; then
        warn "lq --version 未返回新版本，正在自动恢复备份。"
        update_restore_backup "$backup" || true
        update_write_status "fail" "$old_version" "$latest_version" "$backup" "$package_url"
        exit 1
      fi
    fi
    update_write_status "ok" "$old_version" "$latest_version" "$backup" "$package_url"
    ok "已更新到版本：${latest_version}"
    bash "$UPDATE_TARGET_SCRIPT" --version || true
  )
  rc=$?
  set -e
  rm -rf "$tmp"
  (( release_global_lock == 1 )) && global_lock_release
  lock_release "$update_lock"
  return "$rc"
}

update_rollback() {
  local backup from to current_version
  need_root_unless_dry_run
  backup="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_BACKUP)"
  from="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_FROM)"
  to="$(env_file_get "$UPDATE_STATUS_FILE" LAST_UPDATE_TO)"
  [[ -n "$backup" ]] || { warn "没有可回滚的更新备份记录。"; return 0; }
  [[ -f "$backup" ]] || { fail "备份脚本不存在：${backup}"; return 1; }
  warn "即将用备份脚本恢复 ${UPDATE_TARGET_SCRIPT}。"
  warn "备份：${backup}"
  prompt_yes_no "第一次确认：继续回滚？" "N" || return 0
  prompt_yes_no "第二次确认：确实恢复上一个脚本版本？" "N" || return 0
  update_restore_backup "$backup"
  current_version="$(bash "$UPDATE_TARGET_SCRIPT" --version 2>/dev/null | awk '{print $2; exit}')"
  update_write_status "rollback" "${to:-$TOOL_VERSION}" "${current_version:-$from}" "$backup" "rollback"
  ok "已回滚脚本版本：${current_version:-unknown}"
  command -v lq >/dev/null 2>&1 && lq --version || true
}

update_menu() {
  local choice
  while true; do
    print_menu_header "脚本更新"
    echo "1. 检查最新版本"
    echo "2. 更新到最新版本"
    echo "3. 查看最近更新状态"
    echo "4. 回滚到上一个脚本版本"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause update_check ;;
      2) run_menu_action_pause update_run ;;
      3) run_menu_action_pause update_status ;;
      4) run_menu_action_pause update_rollback ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

archive_integrity_ok() {
  local archive="$1" source="${2:-$1}"
  case "$source" in
    *.zip)
      if ! command -v unzip >/dev/null 2>&1; then
        dl_warn "未安装 unzip，无法校验 zip 包。请先安装 unzip，或使用 tar.gz 包 / 本地二进制。"
        return 2
      fi
      unzip -tqq "$archive" >/dev/null 2>&1
      ;;
    *.tar.gz|*.tgz)
      if ! command -v tar >/dev/null 2>&1; then
        dl_warn "未安装 tar，无法校验 tar.gz 包。请先安装 tar，或上传本地 EasyTier 二进制。"
        return 2
      fi
      tar -tzf "$archive" >/dev/null 2>&1
      ;;
    *)
      if command -v tar >/dev/null 2>&1 && tar -tzf "$archive" >/dev/null 2>&1; then
        return 0
      fi
      if command -v unzip >/dev/null 2>&1 && unzip -tqq "$archive" >/dev/null 2>&1; then
        return 0
      fi
      if ! command -v unzip >/dev/null 2>&1; then
        dl_warn "未安装 unzip，无法校验 zip 包。请先安装 unzip，或使用 tar.gz 包 / 本地二进制。"
        return 2
      fi
      return 1
      ;;
  esac
}

download_large_archive_checked() {
  local raw_url="$1" dest_file="$2" candidate part size_mb integrity_rc
  part="${dest_file}.part"
  rm -f "$part"
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == *.zip ]] && ! command -v unzip >/dev/null 2>&1; then
      dl_warn "当前系统缺少 unzip，暂不尝试 zip 包：${candidate}"
      continue
    fi
    if [[ "$candidate" == *.tar.gz || "$candidate" == *.tgz ]] && ! command -v tar >/dev/null 2>&1; then
      dl_warn "当前系统缺少 tar，暂不尝试 tar.gz 包：${candidate}"
      continue
    fi
    EASYTIER_DOWNLOAD_ATTEMPTS+=("$candidate")
    dl_info "正在下载 EasyTier：${candidate}"
    if curl -fL --connect-timeout 15 --max-time 600 --retry 3 --retry-delay 3 --retry-connrefused -C - -o "$part" "$candidate"; then
      if [[ ! -s "$part" ]]; then
        dl_warn "下载结果为空，继续尝试下一个地址。"
        rm -f "$part"
        continue
      fi
      if (( $(wc -c <"$part") < 10485760 )); then
        dl_warn "下载文件小于 10MB，判定为坏包，继续尝试下一个地址。"
        rm -f "$part"
        continue
      fi
      if archive_integrity_ok "$part" "$candidate"; then
        :
      else
        integrity_rc=$?
        if (( integrity_rc == 2 )); then
          dl_warn "缺少校验工具，继续尝试其它格式或本地安装方式。"
        else
          dl_warn "压缩包完整性校验失败，继续尝试下一个地址。"
        fi
        rm -f "$part"
        continue
      fi
      mv -f "$part" "$dest_file"
      size_mb="$(du -m "$dest_file" | awk '{print $1}')"
      dl_ok "EasyTier 下载成功：${dest_file}，大小 ${size_mb} MB"
      return 0
    fi
    dl_warn "下载失败，尝试下一个地址。"
  done < <(github_url_candidates "$raw_url")
  rm -f "$part"
  return 1
}

choose_local_easytier_archive() {
  local dest="$1" choice path i=0
  local files=()
  is_interactive || return 1
  while IFS= read -r path; do
    [[ -f "$path" ]] && files+=("$path")
  done < <(find /root . -maxdepth 1 -type f \( -name 'easytier*.tar.gz' -o -name 'easytier*.tgz' -o -name 'easytier*.zip' \) 2>/dev/null | sort -u)
  if ((${#files[@]} > 0)); then
    echo "发现本地 EasyTier 包："
    for path in "${files[@]}"; do
      i=$((i + 1))
      echo "${i}. ${path}"
    done
    echo "0. 手动输入其它路径 / 取消"
    choice="$(prompt_menu_choice "请选择：")"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
      path="${files[$((choice - 1))]}"
      if (( $(wc -c <"$path") < 10485760 )); then
        fail "本地 EasyTier 包小于 10MB，疑似半截文件：${path}"
        return 1
      fi
      if ! archive_integrity_ok "$path" "$path"; then
        fail "本地 EasyTier 包完整性校验失败：${path}"
        return 1
      fi
      cp -a "$path" "$dest"
      return 0
    fi
  fi
  path="$(prompt_value "请输入本地 EasyTier zip/tar.gz/tgz 路径，留空取消" "")"
  [[ -n "$path" && -f "$path" ]] || return 1
  if (( $(wc -c <"$path") < 10485760 )); then
    fail "本地 EasyTier 包小于 10MB，疑似半截文件：${path}"
    return 1
  fi
  if ! archive_integrity_ok "$path" "$path"; then
    fail "本地 EasyTier 包完整性校验失败：${path}"
    return 1
  fi
  cp -a "$path" "$dest"
}

download_easytier_archive() {
  local dest="$1" version="$EASYTIER_VERSION" arch api_url release_base name url seen_url
  local urls=()
  EASYTIER_DOWNLOAD_ATTEMPTS=()
  arch="$(easytier_arch_family)" || return 1
  release_base="https://github.com/EasyTier/EasyTier/releases/download/${version}"
  api_url="$(easytier_api_asset_url "$version" "$arch" || true)"
  [[ -n "$api_url" && "$api_url" != "null" ]] && urls+=("$api_url")
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    url="${release_base}/${name}"
    for seen_url in "${urls[@]}"; do
      [[ "$seen_url" == "$url" ]] && continue 2
    done
    urls+=("$url")
  done < <(easytier_asset_names "$version" "$arch")
  for url in "${urls[@]}"; do
    if download_large_archive_checked "$url" "$dest"; then
      dl_ok "EasyTier 下载和校验完成。"
      return 0
    fi
  done
  dl_fail "EasyTier 自动下载失败。"
  if ((${#EASYTIER_DOWNLOAD_ATTEMPTS[@]} > 0)); then
    printf '已尝试：\n' >&2
    printf '  %s\n' "${EASYTIER_DOWNLOAD_ATTEMPTS[@]}" >&2
  fi
  printf '%s\n' "解决方式：" >&2
  printf '%s\n' "- 先执行 DNS / IPv4 优先修复" >&2
  printf '%s\n' "- 设置 LEIKWAN_GITHUB_MIRRORS" >&2
  printf '%s\n' "- 手动下载 EasyTier tar.gz/tgz/zip 后输入本地路径" >&2
  printf '%s\n' "- 如果无法安装 unzip，请优先使用 tar.gz/tgz，或上传本地 easytier-core / easytier-cli 二进制" >&2
  choose_local_easytier_archive "$dest" || { fail "未提供可用 EasyTier 安装包。"; return 1; }
}

extract_archive() {
  local archive="$1" dest="$2"
  case "$archive" in
    *.zip)
      command -v unzip >/dev/null 2>&1 || { warn "未安装 unzip，无法解压 zip 包。请使用 tar.gz 包或本地二进制。"; return 1; }
      unzip -q "$archive" -d "$dest"
      ;;
    *.tar.gz|*.tgz)
      command -v tar >/dev/null 2>&1 || { warn "未安装 tar，无法解压 tar.gz 包。"; return 1; }
      tar -xzf "$archive" -C "$dest"
      ;;
    *)
      if command -v tar >/dev/null 2>&1 && tar -xzf "$archive" -C "$dest" 2>/dev/null; then
        return 0
      fi
      command -v unzip >/dev/null 2>&1 || { warn "未安装 unzip，无法尝试解压 zip 包。请使用 tar.gz 包或本地二进制。"; return 1; }
      unzip -q "$archive" -d "$dest"
      ;;
  esac
}

archive_listing() {
  local archive="$1"
  case "$archive" in
    *.zip) command -v unzip >/dev/null 2>&1 && unzip -l "$archive" 2>/dev/null | sed -n '1,50p' ;;
    *) tar -tzf "$archive" 2>/dev/null | sed -n '1,50p' || { command -v unzip >/dev/null 2>&1 && unzip -l "$archive" 2>/dev/null | sed -n '1,50p'; } ;;
  esac
}

install_local_easytier_binaries() {
  local core cli
  is_interactive || return 1
  warn "可以改用本地 EasyTier 二进制继续安装。"
  core="$(prompt_value "请输入本地 easytier-core 路径，输入 0 取消" "/root/easytier-core")"
  [[ "$core" == "0" ]] && return 1
  cli="$(prompt_value "请输入本地 easytier-cli 路径，输入 0 取消" "/root/easytier-cli")"
  [[ "$cli" == "0" ]] && return 1
  [[ -f "$core" && -f "$cli" ]] || { warn "未找到 easytier-core / easytier-cli 本地文件。"; return 1; }
  backup_file "$EASYTIER_CORE_BIN"; backup_file "$EASYTIER_CLI_BIN"
  install -m 755 "$core" "$EASYTIER_CORE_BIN"
  install -m 755 "$cli" "$EASYTIER_CLI_BIN"
  easytier_validate_help || { fail "本地 EasyTier 二进制校验失败。"; return 1; }
  ok "已安装本地 EasyTier 二进制。"
}

install_easytier_binary() {
  local mode="${1:-auto}"
  if [[ -x "$EASYTIER_CORE_BIN" && -x "$EASYTIER_CLI_BIN" ]] && easytier_validate_help; then
    if ! command -v jq >/dev/null 2>&1; then
      info "jq 缺失只影响 GitHub release metadata 获取，不影响当前已安装 EasyTier 运行。"
    fi
    if [[ "$mode" == "repair" ]]; then
      if ! prompt_yes_no "检测到可用 EasyTier 二进制，是否重新安装 / 修复？" "N"; then
        ok "复用已安装 EasyTier：${EASYTIER_CORE_BIN}"
        return 0
      fi
    else
      ok "复用已安装 EasyTier：${EASYTIER_CORE_BIN}"
      return 0
    fi
  fi
  if ! install_packages curl jq ca-certificates tar unzip; then
    warn "依赖安装未完成，将在已有工具条件下继续尝试。"
    warn "如果 apt 源返回 403 或 mirror sync in progress，请换源、稍后重试，或手动安装 curl/jq/tar/unzip/ca-certificates。"
  fi
  if ! command -v curl >/dev/null 2>&1; then
    fail "缺少 curl，无法自动下载 EasyTier。请先安装 curl 或上传本地二进制。"
    install_local_easytier_binaries
    return $?
  fi
  if ! command -v tar >/dev/null 2>&1 && ! command -v unzip >/dev/null 2>&1; then
    warn "系统缺少 tar 和 unzip，无法解压 EasyTier 安装包。"
    install_local_easytier_binaries
    return $?
  fi
  local tmpdir archive core cli list
  confirm_summary "EasyTier 安装摘要" "版本：${EASYTIER_VERSION}\n目标：${EASYTIER_CORE_BIN} / ${EASYTIER_CLI_BIN}\n下载：LEIKWAN_GITHUB_MIRRORS / 内置镜像 / 官方 GitHub 轮询 + 本地包 fallback" || return 0
  (( DRY_RUN == 1 )) && return 0
  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/easytier.pkg"
  if ! download_easytier_archive "$archive"; then
    install_local_easytier_binaries && { rm -rf "$tmpdir"; return 0; }
    rm -rf "$tmpdir"
    return 1
  fi
  if ! extract_archive "$archive" "$tmpdir"; then
    fail "EasyTier 安装包解压失败。"
    archive_listing "$archive" >&2 || true
    rm -rf "$tmpdir"
    return 1
  fi
  core="$(find "$tmpdir" -type f -name easytier-core -perm -111 | head -n 1)"
  cli="$(find "$tmpdir" -type f -name easytier-cli -perm -111 | head -n 1)"
  if [[ -z "$core" || -z "$cli" ]]; then
    fail "安装包中未找到 easytier-core / easytier-cli。"
    list="$(archive_listing "$archive" || find "$tmpdir" -maxdepth 4 -type f)"
    printf '%s\n' "$list" >&2
    rm -rf "$tmpdir"
    return 1
  fi
  backup_file "$EASYTIER_CORE_BIN"; backup_file "$EASYTIER_CLI_BIN"
  install -m 755 "$core" "$EASYTIER_CORE_BIN"
  install -m 755 "$cli" "$EASYTIER_CLI_BIN"
  rm -rf "$tmpdir"
  easytier_validate_help || { fail "easytier --help 校验失败。"; return 1; }
  ok "EasyTier 安装完成。"
}

core_common_args() {
  local ip="$1" peers="${2:-}" args=()
  local network_name network_secret
  network_name="$(env_file_get "$NETWORK_ENV" EASYTIER_NETWORK_NAME)"
  network_secret="$(env_file_get "$NETWORK_ENV" EASYTIER_NETWORK_SECRET)"
  [[ -n "$network_name" && -n "$network_secret" ]] || { fail "缺少 EasyTier network.env，请先生成网络码。"; return 1; }
  easytier_help_has '--network-name' || { fail "当前 easytier-core 不支持 --network-name"; return 1; }
  easytier_help_has '--network-secret' || { fail "当前 easytier-core 不支持 --network-secret"; return 1; }
  easytier_help_has '--ipv4' || { fail "当前 easytier-core 不支持 --ipv4"; return 1; }
  args+=("--network-name" "$network_name" "--network-secret" "$network_secret" "--ipv4" "$ip")
  if [[ -n "$peers" ]]; then
    while read -r peer; do
      [[ -n "$peer" ]] && args+=("-p" "$peer")
    done <<<"$peers"
  fi
  printf '%q ' "${args[@]}"
}

entry_service_name() {
  printf 'easytier-entry-%s' "$(safe_name "$1")"
}

entry_service_path() {
  printf '/etc/systemd/system/%s.service' "$(entry_service_name "$1")"
}

render_entry_service() {
  local name="$1" et_ip="$2" proto="$3" port="$4" args listener_args listener
  args="$(core_common_args "$et_ip")" || return 1
  confirm_easytier_port "$port" || return 1
  easytier_help_has '--listeners' || { fail "当前 easytier-core 不支持 --listeners"; return 1; }
  proto="$(normalize_easytier_protocols "$proto")" || { fail "EasyTier 传输模式无效：${proto}"; return 1; }
  listener_args=""
  while IFS= read -r listener; do
    [[ -n "$listener" ]] && listener_args="${listener_args}$(printf '%q ' --listeners "$listener")"
  done < <(easytier_urls "0.0.0.0" "$proto" "$port")
  cat <<EOF
# Managed by leikwan-toolkit ${TOOL_VERSION}
[Unit]
Description=Leikwan EasyTier Entry ${name}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EASYTIER_CORE_BIN} ${args}${listener_args}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

enabled_entry_peers() {
  local name public_host et_ip proto port weight enabled
  while IFS=$'\t' read -r name public_host et_ip proto port weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    easytier_urls "$public_host" "$proto" "$port"
  done < <(entries_rows)
}

render_relay_service() {
  local args peers listener_args listener
  peers="$(enabled_entry_peers)"
  args="$(core_common_args "$RELAY_ET_IP" "$peers")" || return 1
  if listener_args="$(easytier_disable_listener_arg)"; then
    :
  else
    easytier_help_has '--listeners' || { fail "当前 easytier-core 不支持禁用 listener，也不支持 --listeners，无法避免默认 11010/11011/11012。"; return 1; }
    listener_args=""
    while IFS= read -r listener; do
      [[ -n "$listener" ]] && listener_args="${listener_args}$(printf '%q ' --listeners "$listener")"
    done < <(easytier_urls "0.0.0.0" "$EASYTIER_PROTOCOLS_DEFAULT" "$DEFAULT_EASYTIER_PORT")
  fi
  cat <<EOF
# Managed by leikwan-toolkit ${TOOL_VERSION}
[Unit]
Description=Leikwan EasyTier Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EASYTIER_CORE_BIN} ${args}${listener_args}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

start_service_file() {
  local service_name="$1"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] systemctl enable --now ${service_name}.service"
    return 0
  fi
  systemctl daemon-reload
  systemctl enable "${service_name}.service"
  systemctl restart "${service_name}.service"
}

et_iface_by_ip() {
  local ip="$1"
  ip -o -4 addr show 2>/dev/null | awk -v ip="$ip" '$4 ~ "^"ip"/" {print $2; exit}'
}

et_ip_present() {
  local ip="$1"
  [[ -n "$(et_iface_by_ip "$ip")" ]]
}

wait_et_ip() {
  local ip="$1" timeout="${2:-15}" i
  for i in $(seq 1 "$timeout"); do
    if et_ip_present "$ip"; then return 0; fi
    sleep 1
  done
  return 1
}

wait_systemd_active() {
  local service_name="$1" timeout="${2:-15}" i
  (( DRY_RUN == 1 )) && return 0
  command -v systemctl >/dev/null 2>&1 || return 0
  for i in $(seq 1 "$timeout"); do
    if systemctl is-active --quiet "${service_name}.service"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

easytier_cli_peer_text() {
  "$EASYTIER_CLI_BIN" peer 2>/dev/null || "$EASYTIER_CLI_BIN" node 2>/dev/null || true
}

pairing_base64() {
  base64 "$1" | tr -d '\n'
}

decode_pairing_base64() {
  local payload="$1" dest="$2" decoded
  decoded="$(mktemp)"
  if printf '%s' "$payload" | base64 -d >"$decoded" 2>/dev/null &&
    grep -qx 'PAIRING_VERSION=0.4' "$decoded" &&
    grep -q '^ROLE=' "$decoded"; then
    cp -a "$decoded" "$dest"
    rm -f "$decoded"
    return 0
  fi
  rm -f "$decoded"
  return 1
}

decode_env_base64() {
  local payload="$1" dest="$2" required_key="$3" decoded
  decoded="$(mktemp)"
  if printf '%s' "$payload" | base64 -d >"$decoded" 2>/dev/null &&
    grep -q "^${required_key}=" "$decoded"; then
    cp -a "$decoded" "$dest"
    rm -f "$decoded"
    return 0
  fi
  rm -f "$decoded"
  return 1
}

print_pairing_code() {
  local title="$1" begin="$2" end="$3" file="$4" one_line_key="$5" next_step="${6:-}"
  echo
  echo "${BOLD}${title}${RESET}"
  echo "----------------------------------------"
  echo "$begin"
  cat "$file"
  echo "$end"
  if [[ -n "$next_step" ]]; then
    echo
    echo "下一步：${next_step}"
  fi
  echo
  echo "单行码（复制这一行也可以）："
  printf '%s=%s\n' "$one_line_key" "$(pairing_base64 "$file")"
}

wait_pairing_code_confirm() {
  local ans
  is_interactive || return 0
  echo
  echo "请确认已经复制上面的单行码。"
  echo "直接回车不会返回菜单。"
  echo "输入 y 后回车：返回菜单"
  echo "输入 r 后回车：重新显示单行码"
  echo "输入 p 后回车：显示保存路径"
  while true; do
    read -r -p "请选择 [y/r/p]: " ans || ans=""
    ans="$(normalize_menu_choice "$ans")"
    ans="${ans,,}"
    case "$ans" in
      y|yes) return 0 ;;
      r|redisplay) return 2 ;;
      p|path) return 3 ;;
      "") echo "为避免手滑，直接回车不会返回菜单。请输入 y 返回，或 r 重显。" ;;
      *) echo "请输入 y / r / p。" ;;
    esac
  done
}

show_pairing_code_and_confirm() {
  local title="$1" begin="$2" end="$3" file="$4" one_line_key="$5" next_step="${6:-}"
  local rc
  while true; do
    print_pairing_code "$title" "$begin" "$end" "$file" "$one_line_key" "$next_step"
    is_interactive || return 0
    set +e
    wait_pairing_code_confirm
    rc=$?
    set -e
    case "$rc" in
      0) MENU_ACTION_PAUSE_DONE=1; return 0 ;;
      2) continue ;;
      3) echo "保存路径：${file}" ;;
    esac
  done
}

wait_file_output_confirm() {
  local label="$1" path="$2" ans
  is_interactive || return 0
  echo
  echo "${label} 已输出。"
  echo "输入 y 后回车：返回菜单"
  echo "输入 p 后回车：显示保存路径"
  while true; do
    read -r -p "请选择 [y/p]: " ans || ans=""
    ans="$(normalize_menu_choice "$ans")"
    ans="${ans,,}"
    case "$ans" in
      y|yes) MENU_ACTION_PAUSE_DONE=1; return 0 ;;
      p|path) echo "保存路径：${path}" ;;
      "") echo "为避免手滑，直接回车不会返回菜单。请输入 y 返回。" ;;
      *) echo "请输入 y / p。" ;;
    esac
  done
}

parse_pairing_raw() {
  local raw="$1" dest="$2" base64_key="$3" line payload
  : >"$dest"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(normalize_menu_choice "$line")"
    [[ -n "$line" ]] || continue
    case "$line" in
      "-----BEGIN LEIKWAN "*|"-----END LEIKWAN "*) continue ;;
    esac
    if [[ "$line" == "${base64_key}="* || "$line" == LEIKWAN_EASYTIER_*_BASE64=* ]]; then
      payload="${line#*=}"
      if ! decode_pairing_base64 "$payload" "$dest"; then
        fail "一行配对码解码失败，请重新复制完整内容。"
        return 1
      fi
      return 0
    fi
    if [[ "$line" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && ((${#line} >= 40)); then
      if decode_pairing_base64 "$line" "$dest"; then
        return 0
      fi
    fi
    if [[ "$line" == *=* ]]; then
      printf '%s\n' "$line" >>"$dest"
    fi
  done <"$raw"
  [[ -s "$dest" ]] || { fail "没有读到有效 KEY=VALUE 配对内容。"; return 1; }
}

read_pairing_code() {
  local dest="$1" label="$2" end_marker="$3" base64_key="$4" source="${5:-}"
  local raw line has_content=0
  raw="$(mktemp)"
  if [[ -n "$source" ]]; then
    if [[ "$source" == "-" ]]; then
      cat >"$raw"
    elif [[ -f "$source" ]]; then
      cp -a "$source" "$raw"
    else
      printf '%s\n' "$source" >"$raw"
    fi
  else
    echo "请粘贴从 ${label} 复制的整段配对码，包含 BEGIN/END 行。"
    echo "粘贴完成后按回车，遇到 END 行会自动继续。"
    echo "如果只粘贴 KEY=VALUE 内容，请用空行结束。"
    while IFS= read -r line; do
      line="$(normalize_menu_choice "$line")"
      if [[ -z "$line" ]]; then
        (( has_content == 1 )) && break
        continue
      fi
      has_content=1
      printf '%s\n' "$line" >>"$raw"
      [[ "$line" == "$end_marker" ]] && break
      [[ "$line" == "${base64_key}="* || "$line" == LEIKWAN_EASYTIER_*_BASE64=* ]] && break
      [[ "$line" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && ((${#line} >= 40)) && break
    done
  fi
  parse_pairing_raw "$raw" "$dest" "$base64_key"
  rm -f "$raw"
}

require_pairing_fields() {
  local file="$1" missing=() key value
  shift
  for key in "$@"; do
    value="$(env_file_get "$file" "$key")"
    [[ -n "$value" ]] || missing+=("$key")
  done
  if ((${#missing[@]} > 0)); then
    fail "配对码缺少 ${missing[*]}，请重新复制完整内容。"
    return 1
  fi
}

require_env_fields() {
  local file="$1" missing=() key value
  shift
  for key in "$@"; do
    value="$(env_file_get "$file" "$key")"
    [[ -n "$value" ]] || missing+=("$key")
  done
  if ((${#missing[@]} > 0)); then
    fail "配置码缺少 ${missing[*]}，请重新复制完整内容。"
    return 1
  fi
}

machine_has_relay_network() {
  local role
  role="$(env_file_get "$NETWORK_ENV" ROLE)"
  [[ "$role" == "leikwan-relay" ]] && return 0
  role="$(env_file_get "$NETWORK_PAIRING_FILE" ROLE)"
  [[ "$role" == "leikwan-relay" ]]
}

machine_looks_like_relay() {
  machine_has_relay_network && return 0
  systemctl list-unit-files --type=service --no-legend "${EASYTIER_RELAY_SERVICE_NAME}.service" 2>/dev/null | grep -q . && return 0
  et_ip_present "$RELAY_ET_IP"
}

machine_has_entry_service() {
  if compgen -G "/etc/systemd/system/easytier-entry-*.service" >/dev/null; then
    return 0
  fi
  systemctl list-unit-files --type=service --no-legend 'easytier-entry-*.service' 2>/dev/null | grep -q .
}

machine_looks_like_entry() {
  local role
  role="$(env_file_get "$NETWORK_ENV" ROLE)"
  [[ "$role" == "cloud-entry" ]] && return 0
  machine_has_entry_service && return 0
  [[ -f "$ENTRY_PAIRING_FILE" ]]
}

guard_entry_join_role() {
  if machine_has_relay_network; then
    warn "当前机器看起来是 B 利群主机，不应该执行 A 公网入口部署。"
    warn "正确操作是选择：4. B 利群主机：粘贴入口码，完成组网。"
    prompt_yes_no "是否仍然继续？" "N" || return 1
  fi
}

guard_relay_join_role() {
  if machine_has_entry_service; then
    warn "当前机器看起来是 A 公网入口，不应该执行 B 接入。"
    warn "正确操作是在 B 利群主机执行该步骤。"
    prompt_yes_no "是否仍然继续？" "N" || return 1
  fi
}

entries_rows() {
  [[ -f "$ENTRIES_TSV" ]] || return 0
  awk -F'\t' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function norm_proto(s) {
      s=tolower(trim(s))
      gsub(/[[:space:]]+/, "", s)
      gsub(/\+/, ",", s)
      if (s=="dual" || s=="both" || s=="udp,tcp") s="tcp,udp"
      return s
    }
    { gsub(/\r/, "") }
    NF == 0 { next }
    $1 ~ /^#/ { next }
    {
      name=trim($1)
      public_host=trim($2)
      et_ip=trim($3)
      proto=norm_proto($4)
      port=trim($5)
      weight=trim($6)
      enabled=trim($7)
      if (name=="" || public_host=="" || et_ip=="" || proto=="" || port=="" || enabled=="") next
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name, public_host, et_ip, proto, port, weight, enabled
    }
  ' "$ENTRIES_TSV"
}

pending_entries_rows() {
  [[ -f "$PENDING_ENTRIES_TSV" ]] || return 0
  awk -F'\t' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function norm_proto(s) {
      s=tolower(trim(s))
      gsub(/[[:space:]]+/, "", s)
      gsub(/\+/, ",", s)
      if (s=="dual" || s=="both" || s=="udp,tcp") s="tcp,udp"
      return s
    }
    { gsub(/\r/, "") }
    NF == 0 { next }
    $1 ~ /^#/ { next }
    {
      name=trim($1)
      et_ip=trim($2)
      proto=norm_proto($3)
      port=trim($4)
      created_at=trim($5)
      if (name=="" || et_ip=="" || proto=="" || port=="") next
      printf "%s\t%s\t%s\t%s\t%s\n", name, et_ip, proto, port, created_at
    }
  ' "$PENDING_ENTRIES_TSV"
}

resolved_entries_rows() {
  [[ -f "$RESOLVED_ENTRIES_TSV" ]] || return 0
  awk -F'\t' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    { gsub(/\r/, "") }
    NF == 0 { next }
    $1 ~ /^#/ { next }
    {
      name=trim($1)
      public_host=trim($2)
      resolved_ip=trim($3)
      last_checked=trim($4)
      last_changed=trim($5)
      if (name=="" || public_host=="") next
      printf "%s\t%s\t%s\t%s\t%s\n", name, public_host, resolved_ip, last_checked, last_changed
    }
  ' "$RESOLVED_ENTRIES_TSV"
}

entries_rows_sorted() {
  entries_rows | sort -t$'\t' -k6,6nr -k1,1
}

enabled_entries_sorted() {
  entries_rows | awk -F'\t' '$7=="true"' | sort -t$'\t' -k6,6nr -k1,1
}

forwards_rows() {
  [[ -f "$FORWARDS_TSV" ]] || return 0
  # Normalize forwards.tsv rows:
  # - tolerate CRLF / trailing spaces
  # - tolerate missing comment (NF>=7)
  # - tolerate extra columns (NF>8)
  # - always output 8 tab-separated fields
  awk -F'\t' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    { gsub(/\r/, "") }
    NF == 0 { next }
    $1 ~ /^#/ { next }
    {
      name=trim($1)
      entry_port=trim($2)
      target_host=trim($3)
      target_port=trim($4)
      out_iface=trim($5)
      route_table=trim($6)
      enabled=trim($7)
      comment=""
      if (NF >= 8) comment=$8
      comment=trim(comment)
      if (name=="" || entry_port=="" || target_host=="" || target_port=="" || enabled=="") next
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name, entry_port, target_host, target_port, out_iface, route_table, enabled, comment
    }
  ' "$FORWARDS_TSV"
}

forwards_rows_usv() {
  forwards_rows | awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} NF>=7 {print $1,$2,$3,$4,$5,$6,$7,$8}'
}

last_resolved_ip_for_forward() {
  local name="$1"
  resolved_rows | awk -F'\t' -v n="$name" '$1==n && $4!="" {print $4; exit}'
}

display_entries() {
  ensure_tsv_files
  local only_enabled="${1:-all}" labels
  labels=$'编号\t名称\t公网地址\tEasyTier IP\t协议\t端口\t权重\t启用'
  entries_rows_sorted | awk -F'\t' -v only="$only_enabled" '
    function proto_display(s) { return s=="tcp,udp" ? "tcp+udp" : s }
    function display_name(n) {
      if (n ~ /^public[0-9]+$/) return "公网" substr(n, 7) "(" n ")"
      return n
    }
    only=="enabled" && $7!="true" {next}
    {
      printf "%d)\t%s\t%s\t%s\t%s\t%s\tweight=%s\t%s\n", ++i, display_name($1), $2, $3, proto_display($4), $5, $6, ($7=="true" ? "enabled" : "disabled")
    }
  ' | render_tsv_table 112 "$labels"
}

select_entry_name() {
  local only_enabled="${1:-all}" prompt="${2:-请输入编号或名称，直接回车返回}" choice query name count
  ensure_tsv_files
  count="$(entries_rows | awk -F'\t' -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {c++} END{print c+0}')"
  if (( count == 0 )); then
    warn "当前没有公网入口。" >&2
    return 1
  fi
  display_entries "$only_enabled" >&2
  while true; do
    choice="$(prompt_value "$prompt")"
    [[ -z "$choice" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      name="$(entries_rows_sorted | awk -F'\t' -v idx="$choice" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {i++} i==idx {print $1; exit}')"
    else
      query="$(normalize_entry_selector "$choice")"
      name="$(entries_rows | awk -F'\t' -v n="$query" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} $1==n {print $1; exit}')"
    fi
    if [[ -n "$name" ]]; then
      printf '%s' "$name"
      return 0
    fi
    warn "入口不存在或编号无效：${choice}" >&2
  done
}

display_forwards() {
  local only_enabled="${1:-all}" resolved_source="/dev/null" labels
  ensure_tsv_files >/dev/null
  resolve_forwards >/dev/null 2>&1 || true
  [[ -f "$RESOLVED_TSV" ]] && resolved_source="$RESOLVED_TSV"
  labels=$'编号\t名称\t入口端口\t后端目标\t当前解析 IP\t出口接口\t路由表\t启用\t备注'
  awk -F'\t' -v only="$only_enabled" '
    NR==FNR {
      if ($1 !~ /^#/ && NF >= 4) ip[$1]=$4
      next
    }
    $1 ~ /^#/ || NF < 7 {next}
    only=="enabled" && $7!="true" {next}
    {
      resolved=(ip[$1] != "" ? ip[$1] : "-")
      comment=(NF>=8 && $8!="" ? $8 : "-")
      printf "%d)\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ++i, $1, $2, $3 ":" $4, resolved, ($5!="" ? $5 : "-"), ($6!="" ? $6 : "-"), ($7=="true" ? "enabled" : "disabled"), comment
    }
  ' "$resolved_source" "$FORWARDS_TSV" | render_tsv_table 112 "$labels"
}

display_forward_selection_list() {
  local only_enabled="${1:-all}" title="${2:-当前转发目标：}"
  echo
  echo "$title"
  display_forwards "$only_enabled"
  echo
}

select_forward_name() {
  local only_enabled="${1:-all}" title="${2:-当前转发目标：}" choice name count
  ensure_tsv_files >/dev/null
  count="$(forwards_rows | awk -F'\t' -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {c++} END{print c+0}')"
  if (( count == 0 )); then
    if [[ "$only_enabled" == "enabled" ]]; then
      warn "当前没有启用的转发目标，请先添加或启用转发目标。" >&2
    else
      warn "当前没有转发目标。" >&2
    fi
    return 1
  fi
  display_forward_selection_list "$only_enabled" "$title" >&2
  while true; do
    choice="$(prompt_value "请输入编号或名称，直接回车返回")"
    [[ -z "$choice" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      name="$(forwards_rows | awk -F'\t' -v idx="$choice" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {i++} i==idx {print $1; exit}')"
      if [[ -z "$name" ]]; then
        warn "编号无效，请重新选择。" >&2
        continue
      fi
    else
      name="$(forwards_rows | awk -F'\t' -v n="$choice" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} $1==n {print $1; exit}')"
    fi
    if [[ -n "$name" ]]; then
      printf '%s' "$name"
      return 0
    fi
    warn "转发不存在：${choice}" >&2
  done
}

entry_pool_for_prompt() {
  local start end
  if [[ -f "$ENTRY_EXPOSE_ENV" ]]; then
    start="$(entry_expose_start)"
    end="$(entry_expose_end)"
    if is_port "$start" && is_port "$end" && (( start <= end )); then
      printf 'pool\t%s\t%s\n' "$start" "$end"
      return 0
    fi
  fi
  printf 'fallback\t%s\t%s\n' "$FORWARD_ENTRY_PORT_FALLBACK_START" "$FORWARD_ENTRY_PORT_FALLBACK_END"
}

next_available_forward_entry_port() {
  local start="$1" end="$2" port
  for ((port=start; port<=end; port++)); do
    if forward_entry_port_available_for_recommend "$port"; then
      printf '%s' "$port"
      return 0
    fi
  done
  return 1
}

prompt_forward_entry_port() {
  local current_name="${1:-}" current_port="${2:-}" kind start end recommended default prompt value conflict
  IFS=$'\t' read -r kind start end <<<"$(entry_pool_for_prompt)"
  recommended="$(next_available_forward_entry_port "$start" "$end" 2>/dev/null || true)"
  if [[ -z "$recommended" ]]; then
    if [[ -n "$current_port" ]] && port_in_range "$current_port" "$start" "$end"; then
      recommended="$current_port"
    else
      fail "业务入口端口池已无可推荐端口，请调整端口池或清理旧转发目标。"
      return 1
    fi
  fi
  default="${current_port:-$recommended}"
  if [[ "$kind" == "pool" ]]; then
    prompt="公网入口端口，入口端口池 ${start}-${end}，推荐 ${recommended}"
  else
    prompt="公网入口端口，常见范围 ${start}-${end}，推荐 ${recommended}"
  fi
  while true; do
    value="$(prompt_value "$prompt" "$default")"
    if ! is_port "$value"; then
      warn "公网入口端口必须是 1-65535。"
      continue
    fi
    if ! port_in_range "$value" "$start" "$end"; then
      warn "公网入口端口 ${value} 不在 ${start}-${end} 范围内。"
      continue
    fi
    conflict="$(forward_entry_port_conflict_message "$value" "$current_name" "$current_port" || true)"
    if [[ -n "$conflict" ]]; then
      warn "端口 ${value} ${conflict}。"
      prompt_yes_no "是否重新输入？" "Y" || return 1
      default="$recommended"
      continue
    fi
    printf '%s' "$value"
    return 0
  done
}

validate_forwards_tsv() {
  local file="${1:-$FORWARDS_TSV}"
  [[ "$file" == "$FORWARDS_TSV" ]] && ensure_tsv_files
  [[ -f "$file" ]] || { fail "forwards.tsv 不存在：${file}"; return 1; }
  local line_no=0 bad=0 line nf name entry_port target_host target_port _out_iface _route_table enabled _comment
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    nf="$(awk -F'\t' '{print NF}' <<<"$line")"
    if (( nf < 7 )); then
      fail "第 ${line_no} 行字段数错误：至少 7 列（备注可为空），实际 ${nf} 列。"
      echo "当前行内容：${line}" >&2
      echo "请使用 TAB 分隔字段；建议通过菜单 添加转发目标 生成，不要用空格对齐。" >&2
      bad=1
      continue
    fi
    name="$(awk -F'\t' '{print $1}' <<<"$line")"
    entry_port="$(awk -F'\t' '{print $2}' <<<"$line")"
    target_host="$(awk -F'\t' '{print $3}' <<<"$line")"
    target_port="$(awk -F'\t' '{print $4}' <<<"$line")"
    enabled="$(awk -F'\t' '{print $7}' <<<"$line")"
    name="$(normalize_menu_choice "$name")"
    enabled="$(normalize_menu_choice "$enabled")"
    if [[ -z "$name" || -z "$entry_port" || -z "$target_host" || -z "$target_port" || -z "$enabled" ]]; then
      fail "第 ${line_no} 行存在必填字段为空。"
      echo "当前行内容：${line}" >&2
      bad=1
      continue
    fi
    if ! is_port "$entry_port"; then
      fail "第 ${line_no} 行 entry_port 非法：${entry_port}"
      bad=1
    fi
    if ! is_port "$target_port"; then
      fail "第 ${line_no} 行 target_port 非法：${target_port}"
      bad=1
    fi
    case "$enabled" in
      true|false) ;;
      *) fail "第 ${line_no} 行 enabled 必须是 true 或 false：${enabled}"; bad=1 ;;
    esac
  done <"$file"
  (( bad == 0 ))
}

enabled_forwards_count() {
  validate_forwards_tsv >/dev/null || return 1
  forwards_rows | awk -F'\t' '$7=="true"{c++} END{print c+0}'
}

nft_project_table_text() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list table inet leikwan_forward 2>/dev/null || true
}

nft_has_dnat_rules() {
  nft_project_table_text | awk '
    {
      line = " " $0 " "
      gsub(/[[:space:]]+/, " ", line)
      if (line ~ / dnat( |$)/) found = 1
    }
    END { exit !found }
  '
}

nft_has_cloud_dnat() {
  local proto="$1" relay_ip="$2" entry_port="$3"
  nft_project_table_text | awk -v proto="$proto" -v dport="$entry_port" -v target="$relay_ip" '
    {
      line = " " $0 " "
      gsub(/[[:space:]]+/, " ", line)
      if (index(line, " " proto " dport " dport) && index(line, " dnat ") && index(line, target)) found = 1
    }
    END { exit !found }
  '
}

nft_has_relay_dnat() {
  local proto="$1" entry_port="$2" target_ip="$3" target_port="$4"
  local target="${target_ip}:${target_port}"
  nft_project_table_text | awk -v proto="$proto" -v dport="$entry_port" -v target="$target" '
    {
      line = " " $0 " "
      gsub(/[[:space:]]+/, " ", line)
      if (index(line, " " proto " dport " dport) && index(line, " dnat ") && index(line, target)) found = 1
    }
    END { exit !found }
  '
}

nft_existing_project_chains() {
  nft_project_table_text | awk '
    /^[[:space:]]*chain[[:space:]]+/ && $2 != "" && !seen[$2]++ { print $2 }
  '
}

is_mss_value() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 500 && value <= 1460 ))
}

mss_clamp_enabled() {
  local config_value value
  config_value="$(env_file_get "$MSS_CONFIG" ENABLE_MSS_CLAMP)"
  value="${LEIKWAN_ENABLE_MSS_CLAMP:-${config_value:-$ENABLE_MSS_CLAMP}}"
  case "$value" in
    true|TRUE|yes|YES|1|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

tcp_mss_clamp_value() {
  local config_value value
  config_value="$(env_file_get "$MSS_CONFIG" TCP_MSS_CLAMP)"
  [[ -n "$config_value" ]] || config_value="$(env_file_get "$MSS_CONFIG" DEFAULT_TCP_MSS_CLAMP)"
  value="${LEIKWAN_TCP_MSS_CLAMP:-${TCP_MSS_CLAMP:-${config_value:-$DEFAULT_TCP_MSS_CLAMP}}}"
  if is_mss_value "$value"; then
    printf '%s' "$value"
  else
    printf '%s' "$DEFAULT_TCP_MSS_CLAMP"
  fi
}

nft_has_mss_clamp() {
  local mss
  mss="$(tcp_mss_clamp_value)"
  nft_project_table_text | awk -v mss="$mss" '
    {
      line = " " $0 " "
      gsub(/[[:space:]]+/, " ", line)
      if (index(line, " tcp ") && index(line, " maxseg ") && index(line, " size set ")) {
        if (index(line, " " mss " ") || line ~ / maxseg size set( |$)/) found = 1
      }
    }
    END { exit !found }
  '
}

ss_port_listening() {
  local proto="$1" port="$2" opt
  command -v ss >/dev/null 2>&1 || return 1
  case "$proto" in
    tcp) opt="-lntH" ;;
    udp) opt="-lunH" ;;
    *) return 1 ;;
  esac
  ss "$opt" 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}'
}

port_listening_any() {
  local port="$1"
  ss_port_listening tcp "$port" || ss_port_listening udp "$port"
}

nft_ruleset_text() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list ruleset 2>/dev/null || true
}

nft_text_has_dport() {
  local port="$1" proto="${2:-}" source="${3:-project}" text
  if [[ "$source" == "ruleset" ]]; then
    text="$(nft_ruleset_text)"
  else
    text="$(nft_project_table_text)"
  fi
  awk -v p="$port" -v proto="$proto" '
    function token_match(t, r) {
      gsub(/[,{};]/, " ", t)
      if (t ~ /^[0-9]+$/) return t == p
      if (t ~ /^[0-9]+-[0-9]+$/) {
        split(t, r, "-")
        return p >= r[1] && p <= r[2]
      }
      return 0
    }
    {
      if (proto != "" && $0 !~ proto "[[:space:]]+dport") next
      n = split($0, parts, /dport[[:space:]]+/)
      for (i = 2; i <= n; i++) {
        rest = parts[i]
        gsub(/[{};,]/, " ", rest)
        split(rest, tokens, /[[:space:]]+/)
        for (j in tokens) {
          if (token_match(tokens[j])) found = 1
        }
      }
    }
    END { exit !found }
  ' <<<"$text"
}

nft_project_has_dport() {
  nft_text_has_dport "$1" "${2:-}" project
}

nft_ruleset_has_dport() {
  nft_text_has_dport "$1" "${2:-}" ruleset
}

easytier_port_conflict_message() {
  local port="$1" current_name="${2:-}" name _public_host _et_ip _proto _port _weight _enabled
  local pending_name _pending_ip _pending_proto _pending_port _pending_created_at
  if [[ -n "$current_name" ]] && entries_rows | awk -F'\t' -v n="$current_name" -v p="$port" '$1==n && $5==p {found=1} END{exit !found}'; then
    return 1
  fi
  while IFS=$'\t' read -r name _public_host _et_ip _proto _port _weight _enabled; do
    [[ "$_port" == "$port" && "$name" != "$current_name" ]] || continue
    printf '已被公网入口 %s 使用' "$(entry_label "$name")"
    return 0
  done < <(entries_rows)
  while IFS=$'\t' read -r pending_name _pending_ip _pending_proto _pending_port _pending_created_at; do
    [[ "$_pending_port" == "$port" && "$pending_name" != "$current_name" ]] || continue
    printf '已被 pending 公网入口 %s 预占' "$(entry_label "$pending_name")"
    return 0
  done < <(pending_entries_rows)
  if port_listening_any "$port"; then
    printf '已被本机监听进程占用'
    return 0
  fi
  if nft_ruleset_has_dport "$port"; then
    printf '已出现在 nftables dport 规则中'
    return 0
  fi
  return 1
}

easytier_port_available_for_recommend() {
  local port="$1" conflict
  is_fast_port "$port" || return 1
  conflict="$(easytier_port_conflict_message "$port" "" || true)"
  [[ -z "$conflict" ]]
}

forward_entry_port_conflict_message() {
  local port="$1" current_name="${2:-}" current_port="${3:-}"
  local name _port _target_host _target_port _out_iface _route_table _enabled _comment
  while IFS=$'\t' read -r name _port _target_host _target_port _out_iface _route_table _enabled _comment; do
    [[ "$_port" == "$port" && "$name" != "$current_name" ]] || continue
    printf '已被转发目标 %s 使用' "$name"
    return 0
  done < <(forwards_rows)
  if [[ "$port" == "$current_port" ]]; then
    return 1
  fi
  if port_listening_any "$port"; then
    printf '已被本机监听进程占用'
    return 0
  fi
  if nft_ruleset_has_dport "$port"; then
    printf '已出现在 nftables dport 规则中'
    return 0
  fi
  return 1
}

forward_entry_port_available_for_recommend() {
  local port="$1" conflict
  conflict="$(forward_entry_port_conflict_message "$port" "" "" || true)"
  [[ -z "$conflict" ]]
}

entry_exists() {
  local name="$1"
  entries_rows | awk -F'\t' -v n="$name" '$1==n {found=1} END{exit !found}'
}

pending_entries_count() {
  pending_entries_rows | awk 'END{print NR+0}'
}

display_pending_entries() {
  local labels
  labels=$'编号\t名称\tEasyTier IP\t协议\t端口\tcreated_at'
  pending_entries_rows | awk -F'\t' '
    function display_name(n) {
      if (n ~ /^public[0-9]+$/) return "公网" substr(n, 7) "(" n ")"
      return n
    }
    {
      proto=($3=="tcp,udp" ? "tcp+udp" : $3)
      printf "%d)\t%s\t%s\t%s\t%s\t%s\n", ++i, display_name($1), $2, proto, $4, ($5!="" ? $5 : "-")
    }
  ' | render_tsv_table 88 "$labels"
}

entry_reserved_count() {
  { entries_rows; pending_entries_rows; } | awk 'END{print NR+0}'
}

entry_name_reserved() {
  local name="$1"
  entries_rows | awk -F'\t' -v n="$name" '$1==n {found=1} END{exit !found}' && return 0
  pending_entries_rows | awk -F'\t' -v n="$name" '$1==n {found=1} END{exit !found}'
}

entry_et_ip_reserved() {
  local et_ip="$1"
  entries_rows | awk -F'\t' -v ip="$et_ip" '$3==ip {found=1} END{exit !found}' && return 0
  pending_entries_rows | awk -F'\t' -v ip="$et_ip" '$2==ip {found=1} END{exit !found}'
}

entry_easytier_port_reserved() {
  local port="$1"
  entries_rows | awk -F'\t' -v p="$port" '$5==p {found=1} END{exit !found}' && return 0
  pending_entries_rows | awk -F'\t' -v p="$port" '$4==p {found=1} END{exit !found}'
}

pending_entry_is_stale() {
  local created_at="$1" now created_epoch
  [[ -n "$created_at" ]] || return 1
  now="$(date -u '+%s')"
  created_epoch="$(date -u -d "$created_at" '+%s' 2>/dev/null || true)"
  [[ -n "$created_epoch" ]] && (( now - created_epoch > 86400 ))
}

pending_entries_have_stale() {
  local _name _et_ip _proto _port created_at
  while IFS=$'\t' read -r _name _et_ip _proto _port created_at; do
    if pending_entry_is_stale "$created_at"; then
      return 0
    fi
  done < <(pending_entries_rows)
  return 1
}

clean_stale_pending_entries() {
  local tmp name et_ip proto port created_at
  [[ -f "$PENDING_ENTRIES_TSV" ]] || return 0
  tmp="$(mktemp)"
  while IFS=$'\t' read -r name et_ip proto port created_at; do
    pending_entry_is_stale "$created_at" && continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$et_ip" "$proto" "$port" "$created_at" >>"$tmp"
  done < <(pending_entries_rows)
  if [[ -s "$tmp" ]]; then
    write_file "$PENDING_ENTRIES_TSV" "$(cat "$tmp")" 600
  else
    rm -f "$PENDING_ENTRIES_TSV"
  fi
  rm -f "$tmp"
}

prompt_pending_entries_before_generation() {
  local count
  count="$(pending_entries_count)"
  (( count > 0 )) || return 0
  info "当前未完成的公网入口接入码："
  display_pending_entries
  if pending_entries_have_stale; then
    warn "存在超过 24 小时的未完成入口接入码。"
    if prompt_yes_no "是否清理过期 pending 记录？" "Y"; then
      clean_stale_pending_entries
    fi
  fi
  count="$(pending_entries_count)"
  (( count == 0 )) && return 0
  prompt_yes_no "是否继续生成下一个入口码？" "N"
}

reserve_pending_entry() {
  local name="$1" et_ip="$2" protocols="$3" port="$4" created_at tmp
  ensure_base_dirs
  protocols="$(normalize_easytier_protocols "$protocols")" || return 1
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  tmp="$(mktemp)"
  pending_entries_rows | awk -F'\t' -v n="$name" -v ip="$et_ip" -v p="$port" '
    $1==n || ($2==ip && $4==p) {next}
    {print}
  ' >"$tmp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$et_ip" "$protocols" "$port" "$created_at" >>"$tmp"
  write_file "$PENDING_ENTRIES_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
}

clear_pending_entry_reservation() {
  local name="$1" et_ip="$2" port="$3" tmp
  [[ -f "$PENDING_ENTRIES_TSV" ]] || return 0
  tmp="$(mktemp)"
  pending_entries_rows | awk -F'\t' -v n="$name" -v ip="$et_ip" -v p="$port" '
    $1==n || ($2==ip && $4==p) {next}
    {print}
  ' >"$tmp"
  if [[ -s "$tmp" ]]; then
    write_file "$PENDING_ENTRIES_TSV" "$(cat "$tmp")" 600
  else
    rm -f "$PENDING_ENTRIES_TSV"
  fi
  rm -f "$tmp"
}

clear_pending_entry_exact() {
  local name="$1" et_ip="$2" port="$3" tmp
  [[ -f "$PENDING_ENTRIES_TSV" ]] || return 0
  tmp="$(mktemp)"
  pending_entries_rows | awk -F'\t' -v n="$name" -v ip="$et_ip" -v p="$port" '
    $1==n && $2==ip && $4==p {next}
    {print}
  ' >"$tmp"
  if [[ -s "$tmp" ]]; then
    write_file "$PENDING_ENTRIES_TSV" "$(cat "$tmp")" 600
  else
    rm -f "$PENDING_ENTRIES_TSV"
  fi
  rm -f "$tmp"
}

forward_exists() {
  local name="$1"
  forwards_rows | awk -F'\t' -v n="$name" '$1==n {found=1} END{exit !found}'
}

next_entry_name() {
  local slot
  slot="$(next_entry_slot)" || return 1
  printf 'public%s' "$slot"
}

next_entry_et_ip() {
  local prefix="10.198.1" slot ip
  slot="$(next_entry_slot)" || return 1
  for ((; slot<=253; slot++)); do
    ip="${prefix}.$((slot + 1))"
    if ! entry_et_ip_reserved "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

next_entry_easytier_port() {
  local slot port
  slot="$(next_entry_slot)" || return 1
  for ((; slot<=253; slot++)); do
    port=$((DEFAULT_EASYTIER_PORT + slot - 1))
    (( port <= FAST_PORT_RANGE_END )) || break
    if easytier_port_available_for_recommend "$port"; then
      printf '%s' "$port"
      return 0
    fi
  done
  for ((port=FAST_PORT_RANGE_START; port<DEFAULT_EASYTIER_PORT; port++)); do
    if easytier_port_available_for_recommend "$port"; then
      printf '%s' "$port"
      return 0
    fi
  done
  return 1
}

entry_slot_from_fields() {
  local name="$1" et_ip="$2" port="$3" slot
  if [[ "$name" =~ ^public([0-9]+)$ ]]; then
    slot="${BASH_REMATCH[1]}"
    (( slot >= 1 && slot <= 253 )) && printf '%s\n' "$slot"
  fi
  if [[ "$et_ip" =~ ^10\.198\.1\.([0-9]+)$ ]]; then
    slot=$((BASH_REMATCH[1] - 1))
    (( slot >= 1 && slot <= 253 )) && printf '%s\n' "$slot"
  fi
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    slot=$((port - DEFAULT_EASYTIER_PORT + 1))
    (( slot >= 1 && slot <= 253 )) && printf '%s\n' "$slot"
  fi
}

entry_reserved_slots() {
  local name public_host et_ip proto port weight enabled created_at
  while IFS=$'\t' read -r name public_host et_ip proto port weight enabled; do
    entry_slot_from_fields "$name" "$et_ip" "$port"
  done < <(entries_rows)
  while IFS=$'\t' read -r name et_ip proto port created_at; do
    entry_slot_from_fields "$name" "$et_ip" "$port"
  done < <(pending_entries_rows)
}

highest_reserved_entry_slot() {
  entry_reserved_slots | awk 'BEGIN{m=0} $1 ~ /^[0-9]+$/ && $1>m {m=$1} END{print m+0}'
}

next_entry_slot() {
  local slot
  slot="$(highest_reserved_entry_slot)"
  slot=$((slot + 1))
  (( slot >= 1 && slot <= 253 )) || return 1
  printf '%s' "$slot"
}

relay_network_env_ready() {
  local role network_name network_secret
  [[ -f "$NETWORK_ENV" ]] || return 1
  role="$(env_file_get "$NETWORK_ENV" ROLE)"
  network_name="$(env_file_get "$NETWORK_ENV" EASYTIER_NETWORK_NAME)"
  network_secret="$(env_file_get "$NETWORK_ENV" EASYTIER_NETWORK_SECRET)"
  [[ "$role" == "leikwan-relay" && -n "$network_name" && -n "$network_secret" ]]
}

validate_entry_official_fields() {
  local name="$1" et_ip="$2" port="$3" current_name="${4:-}" used_by
  [[ -n "$name" ]] || { warn "公网入口名称不能为空。"; return 1; }
  [[ -n "$et_ip" ]] || { warn "EasyTier IP 不能为空。"; return 1; }
  if ! is_ipv4 "$et_ip"; then
    if looks_like_domain "$et_ip"; then
      warn "你输入的是域名，不是 EasyTier 虚拟 IP。请填写 10.198.1.x 这类虚拟 IP。"
      warn "DDNS 域名请在后面的 本机公网 IP / 域名 填写。"
    else
      warn "EasyTier IP 必须是 IPv4：${et_ip}"
    fi
    return 1
  fi
  is_fast_port "$port" || { warn "EasyTier 端口必须位于 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}。"; return 1; }
  if entries_rows | awk -F'\t' -v n="$name" -v cur="$current_name" '$1==n && $1!=cur {found=1} END{exit !found}'; then
    warn "公网入口名称已存在：${name}"
    return 1
  fi
  if entries_rows | awk -F'\t' -v ip="$et_ip" -v cur="$current_name" '$3==ip && $1!=cur {found=1} END{exit !found}'; then
    warn "EasyTier IP 已被使用：${et_ip}"
    return 1
  fi
  used_by="$(entries_rows | awk -F'\t' -v p="$port" -v cur="$current_name" '$5==p && $1!=cur {print $1; exit}')"
  if [[ -n "$used_by" ]]; then
    warn "端口 ${port} 已被公网入口 $(entry_label "$used_by") 使用。"
    prompt_yes_no "是否重新输入？" "Y" || return 1
    return 1
  fi
  return 0
}

validate_unique_entry_fields() {
  local name="$1" et_ip="$2" port="$3" current_name="${4:-}" conflict used_by
  validate_entry_official_fields "$name" "$et_ip" "$port" "$current_name" || return 1
  if pending_entries_rows | awk -F'\t' -v n="$name" '$1==n {found=1} END{exit !found}'; then
    warn "公网入口名称已被未完成接入码预占：${name}"
    return 1
  fi
  if pending_entries_rows | awk -F'\t' -v ip="$et_ip" '$2==ip {found=1} END{exit !found}'; then
    warn "EasyTier IP 已被未完成接入码预占：${et_ip}"
    return 1
  fi
  used_by="$(pending_entries_rows | awk -F'\t' -v p="$port" '$4==p {print $1; exit}')"
  if [[ -n "$used_by" ]]; then
    warn "端口 ${port} 已被 pending 公网入口 $(entry_label "$used_by") 预占。"
    prompt_yes_no "是否重新输入？" "Y" || return 1
    return 1
  fi
  conflict="$(easytier_port_conflict_message "$port" "$current_name" || true)"
  if [[ -n "$conflict" ]]; then
    warn "端口 ${port} ${conflict}。"
    prompt_yes_no "是否重新输入？" "Y" || return 1
    return 1
  fi
  return 0
}

pending_entry_by_ip_port() {
  local et_ip="$1" port="$2"
  pending_entries_rows | awk -F'\t' -v ip="$et_ip" -v p="$port" '$2==ip && $4==p {print; exit}'
}

pending_entry_by_name() {
  local name="$1"
  pending_entries_rows | awk -F'\t' -v n="$name" '$1==n {print; exit}'
}

replace_entry_row() {
  local row="$1" name old_name tmp
  name="${row%%$'\t'*}"
  old_name="${2:-$name}"
  ensure_tsv_files
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" -v old="$old_name" '$1==n || $1==old {next} {print}' "$ENTRIES_TSV" >"$tmp"
  printf '%s\n' "$row" >>"$tmp"
  write_file "$ENTRIES_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
}

replace_forward_row() {
  local row="$1" name entry_port _rest tmp
  IFS=$'\t' read -r name entry_port _rest <<<"$row"
  ensure_tsv_files
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" -v p="$entry_port" '$1==n || $2==p {next} {print}' "$FORWARDS_TSV" >"$tmp"
  printf '%s\n' "$row" >>"$tmp"
  write_file "$FORWARDS_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
}

quick_generate_network_pairing() {
  need_root_unless_dry_run
  ensure_base_dirs
  install_packages openssl coreutils
  local network_name network_secret suggested_name suggested_ip suggested_protocols suggested_proto suggested_port has_network=0
  local candidate_name candidate_ip candidate_proto candidate_port
  prompt_pending_entries_before_generation || return 0
  if relay_network_env_ready; then
    network_name="$(env_file_get "$NETWORK_ENV" EASYTIER_NETWORK_NAME)"
    network_secret="$(env_file_get "$NETWORK_ENV" EASYTIER_NETWORK_SECRET)"
    has_network=1
    info "检测到已有 EasyTier 网络，正在复用现有 network name / secret。"
    info "本操作只生成新公网入口接入码，不会重启 relay，不会影响已接入入口。"
  else
    network_name="leikwan-$(random_hex 4)"
    network_secret="$(random_hex 32)"
  fi
  suggested_name="$(next_entry_name)"
  suggested_ip="$(next_entry_et_ip 2>/dev/null || printf '%s' "$ENTRY_ET_IP_DEFAULT")"
  suggested_protocols="$EASYTIER_PROTOCOLS_DEFAULT"
  suggested_proto="$EASYTIER_PROTOCOL_DEFAULT"
  suggested_port="$(next_entry_easytier_port 2>/dev/null || printf '%s' "$EASYTIER_PORT_DEFAULT")"
  echo
  echo "${BOLD}新增公网入口建议：${RESET}"
  echo "- 名称：$(entry_label "$suggested_name")"
  echo "- EasyTier IP：${suggested_ip}"
  echo "- EasyTier 监听：$(easytier_protocols_display "$suggested_protocols") / ${suggested_port}"
  echo
  if ! prompt_yes_no "是否使用以上推荐？" "Y"; then
    while true; do
      candidate_name="$(safe_name "$(prompt_value "公网入口名称" "$suggested_name")")"
      candidate_ip="$(prompt_easytier_ip "EasyTier IP" "$suggested_ip")"
      candidate_proto="$(prompt_easytier_protocols "EasyTier 传输模式" "$suggested_protocols")"
      candidate_port="$(prompt_port "EasyTier 监听端口（TCP+UDP，同端口，白名单 8000-9000）" "$suggested_port")"
      if validate_unique_entry_fields "$candidate_name" "$candidate_ip" "$candidate_port" ""; then
        suggested_name="$candidate_name"
        suggested_ip="$candidate_ip"
        suggested_protocols="$candidate_proto"
        suggested_proto="$(easytier_legacy_protocol "$suggested_protocols")"
        suggested_port="$candidate_port"
        break
      fi
    done
  else
    validate_unique_entry_fields "$suggested_name" "$suggested_ip" "$suggested_port" "" || return 0
  fi
  if (( has_network == 0 )); then
    write_file "$NETWORK_ENV" "ROLE=leikwan-relay
EASYTIER_NETWORK_NAME=${network_name}
EASYTIER_NETWORK_SECRET=${network_secret}
EASYTIER_LISTEN_PORT=${suggested_port}
EASYTIER_PROTOCOLS=${suggested_protocols}
EASYTIER_TCP_PORT=${suggested_port}
EASYTIER_UDP_PORT=${suggested_port}
EASYTIER_PROTOCOL=${suggested_proto}
EASYTIER_RELAY_ET_IP=${RELAY_ET_IP}" 600
  fi
  write_file "$NETWORK_PAIRING_FILE" "PAIRING_VERSION=0.4
ROLE=leikwan-relay
EASYTIER_NETWORK_NAME=${network_name}
EASYTIER_NETWORK_SECRET=${network_secret}
RELAY_ET_IP=${RELAY_ET_IP}
SUGGESTED_ENTRY_NAME=${suggested_name}
SUGGESTED_ENTRY_DISPLAY_NAME=$(entry_display_name "$suggested_name")
SUGGESTED_ENTRY_ET_IP=${suggested_ip}
SUGGESTED_EASYTIER_PROTOCOLS=${suggested_protocols}
SUGGESTED_EASYTIER_TCP_PORT=${suggested_port}
SUGGESTED_EASYTIER_UDP_PORT=${suggested_port}
SUGGESTED_EASYTIER_PROTOCOL=${suggested_proto}
SUGGESTED_EASYTIER_PORT=${suggested_port}" 600
  reserve_pending_entry "$suggested_name" "$suggested_ip" "$suggested_protocols" "$suggested_port"
  echo
  echo "${BOLD}公网入口接入码摘要${RESET}"
  echo "- 公网入口：$(entry_label "$suggested_name")"
  echo "- EasyTier IP：${suggested_ip}"
  echo "- EasyTier 监听：$(easytier_protocols_display "$suggested_protocols")/${suggested_port}"
  show_pairing_code_and_confirm "公网入口接入码" \
    "-----BEGIN LEIKWAN EASYTIER NETWORK-----" \
    "-----END LEIKWAN EASYTIER NETWORK-----" \
    "$NETWORK_PAIRING_FILE" \
    "LEIKWAN_EASYTIER_NETWORK_BASE64" \
    "去 A 公网入口机，进入快速组网，选择粘贴网络码部署入口。"
}

quick_deploy_entry_from_network_pairing() {
  need_root_unless_dry_run
  ensure_base_dirs
  guard_entry_join_role || return 0
  local source="${1:-}" tmp role network_name network_secret relay_ip name et_ip proto port public_host detected service service_name legacy_proto
  tmp="$(mktemp)"
  read_pairing_code "$tmp" "B 利群主机" "-----END LEIKWAN EASYTIER NETWORK-----" "LEIKWAN_EASYTIER_NETWORK_BASE64" "$source" || { rm -f "$tmp"; return 1; }
  role="$(env_file_get "$tmp" ROLE)"
  case "$role" in
    leikwan-relay) ;;
    cloud-entry) fail "你粘贴的是入口码，需要在 B 利群主机选择第 4 项。"; rm -f "$tmp"; return 1 ;;
    *) fail "这不是 EasyTier 网络码，请确认粘贴的是 B 生成的那段。"; rm -f "$tmp"; return 1 ;;
  esac
  require_pairing_fields "$tmp" PAIRING_VERSION ROLE EASYTIER_NETWORK_NAME EASYTIER_NETWORK_SECRET RELAY_ET_IP SUGGESTED_ENTRY_NAME SUGGESTED_ENTRY_ET_IP || { rm -f "$tmp"; return 1; }
  network_name="$(env_file_get "$tmp" EASYTIER_NETWORK_NAME)"
  network_secret="$(env_file_get "$tmp" EASYTIER_NETWORK_SECRET)"
  relay_ip="$(env_file_get "$tmp" RELAY_ET_IP)"
  name="$(safe_name "$(env_file_get "$tmp" SUGGESTED_ENTRY_NAME)")"
  et_ip="$(env_file_get "$tmp" SUGGESTED_ENTRY_ET_IP)"
  proto="$(easytier_protocols_from_env "$tmp" SUGGESTED_EASYTIER_PROTOCOLS SUGGESTED_EASYTIER_PROTOCOL "$EASYTIER_PROTOCOLS_DEFAULT")" || { fail "网络码里的 EasyTier 传输模式无效。"; rm -f "$tmp"; return 1; }
  port="$(easytier_port_from_env "$tmp" "$proto" SUGGESTED_EASYTIER_TCP_PORT SUGGESTED_EASYTIER_UDP_PORT SUGGESTED_EASYTIER_PORT)" || { rm -f "$tmp"; return 1; }
  local default_name="$name" default_et_ip="$et_ip" default_proto="$proto" default_port="$port"
  local candidate_name candidate_ip candidate_proto candidate_port
  while true; do
    candidate_name="$(safe_name "$(prompt_value "本机公网入口名称" "$default_name")")"
    candidate_ip="$(prompt_easytier_ip "本机 EasyTier IP" "$default_et_ip")"
    candidate_proto="$(prompt_easytier_protocols "EasyTier 传输模式" "$default_proto")"
    candidate_port="$(prompt_port "EasyTier 监听端口（TCP+UDP，同端口，白名单 8000-9000）" "$default_port")"
    if validate_unique_entry_fields "$candidate_name" "$candidate_ip" "$candidate_port" "$candidate_name"; then
      name="$candidate_name"
      et_ip="$candidate_ip"
      proto="$candidate_proto"
      port="$candidate_port"
      break
    fi
  done
  detected="$(detect_public_ipv4 || true)"
  public_host="$(prompt_value "请输入本机公网 IP / 域名，用于 B 连接 EasyTier" "$detected")"
  [[ -n "$public_host" ]] || public_host="$(prompt_host "请输入本机公网 IP / 域名")"
  confirm_summary "entry 快速部署摘要" "入口名称：${name}\n公网地址：${public_host}\nEasyTier IP：${et_ip}\nEasyTier 监听：$(easytier_protocols_display "$proto")/${port}\nRelay EasyTier IP：${relay_ip}" || { rm -f "$tmp"; return 0; }
  legacy_proto="$(easytier_legacy_protocol "$proto")" || { rm -f "$tmp"; return 1; }
  write_file "$NETWORK_ENV" "ROLE=cloud-entry
ENTRY_NAME=${name}
ENTRY_DISPLAY_NAME=$(entry_display_name "$name")
ENTRY_ET_IP=${et_ip}
EASYTIER_NETWORK_NAME=${network_name}
EASYTIER_NETWORK_SECRET=${network_secret}
EASYTIER_LISTEN_PORT=${port}
EASYTIER_PROTOCOLS=${proto}
EASYTIER_TCP_PORT=${port}
EASYTIER_UDP_PORT=${port}
EASYTIER_PROTOCOL=${legacy_proto}
EASYTIER_RELAY_ET_IP=${relay_ip}" 600
  install_easytier_binary || { rm -f "$tmp"; return 1; }
  service="$(render_entry_service "$name" "$et_ip" "$proto" "$port")" || { rm -f "$tmp"; return 1; }
  service_name="$(entry_service_name "$name")"
  write_file "$(entry_service_path "$name")" "$service" 644
  start_service_file "$service_name"
  wait_et_ip "$et_ip" 15 || warn "15 秒内未检测到 EasyTier IP：${et_ip}"
  if easytier_protocols_has "$proto" tcp; then
    if ss -lntH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}'; then ok "EasyTier TCP ${port} 已监听"; else warn "EasyTier TCP ${port} 未监听"; fi
  fi
  if easytier_protocols_has "$proto" udp; then
    if ss -lunH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}'; then ok "EasyTier UDP ${port} 已监听"; else warn "EasyTier UDP ${port} 未监听"; fi
  fi
  replace_entry_row "${name}"$'\t'"${public_host}"$'\t'"${et_ip}"$'\t'"${proto}"$'\t'"${port}"$'\t'"100"$'\t'"true"
write_file "$ENTRY_PAIRING_FILE" "PAIRING_VERSION=0.4
ROLE=cloud-entry
ENTRY_NAME=${name}
ENTRY_DISPLAY_NAME=$(entry_display_name "$name")
ENTRY_PUBLIC_HOST=${public_host}
ENTRY_ET_IP=${et_ip}
EASYTIER_PROTOCOLS=${proto}
EASYTIER_TCP_PORT=${port}
EASYTIER_UDP_PORT=${port}
EASYTIER_PROTOCOL=${legacy_proto}
EASYTIER_PORT=${port}
WEIGHT=100
ENABLED=true" 600
  rm -f "$tmp"
  echo
  echo "${BOLD}公网入口返回码摘要${RESET}"
  echo "- 公网入口：$(entry_label "$name")"
  echo "- 公网地址：${public_host}"
  echo "- EasyTier IP：${et_ip}"
  echo "- EasyTier 监听：$(easytier_protocols_display "$proto")/${port}"
  info "如果 A 在家宽 / NAT 后面，请在路由器中同时映射 TCP 和 UDP ${port} 到本机。"
  info "如果只映射 TCP，则 UDP peer 不会生效，但 TCP 仍可用。"
  info "如果只映射 UDP，则 TCP peer 不会生效，但 UDP 仍可用。"
  show_pairing_code_and_confirm "公网入口返回码" \
    "-----BEGIN LEIKWAN EASYTIER ENTRY-----" \
    "-----END LEIKWAN EASYTIER ENTRY-----" \
    "$ENTRY_PAIRING_FILE" \
    "LEIKWAN_EASYTIER_ENTRY_BASE64" \
    "回到 B 利群主机，选择粘贴入口返回码完成接入。"
}

quick_deploy_relay_from_entry_pairing() {
  need_root_unless_dry_run
  ensure_base_dirs
  guard_relay_join_role || return 0
  [[ -f "$NETWORK_ENV" ]] || { fail "缺少 ${NETWORK_ENV}，请先在 B 执行 pair relay-init。"; return 0; }
  local source="${1:-}" tmp role name public_host et_ip proto port weight enabled row
  local pending_match pending_same_name pending_name pending_et_ip _pending_proto pending_port _pending_created_at
  local same_name pending_same_et_ip pending_same_proto pending_same_port _pending_same_created_at
  tmp="$(mktemp)"
  read_pairing_code "$tmp" "A 公网入口机" "-----END LEIKWAN EASYTIER ENTRY-----" "LEIKWAN_EASYTIER_ENTRY_BASE64" "$source" || { rm -f "$tmp"; return 0; }
  role="$(env_file_get "$tmp" ROLE)"
  case "$role" in
    cloud-entry) ;;
    leikwan-relay) fail "你粘贴的是网络码，需要在 A 公网入口选择第 3 项。"; rm -f "$tmp"; return 0 ;;
    *) fail "这不是 EasyTier 入口码，请确认粘贴的是 A 生成的那段。"; rm -f "$tmp"; return 0 ;;
  esac
  require_pairing_fields "$tmp" PAIRING_VERSION ROLE ENTRY_NAME ENTRY_PUBLIC_HOST ENTRY_ET_IP || { rm -f "$tmp"; return 0; }
  name="$(safe_name "$(env_file_get "$tmp" ENTRY_NAME)")"
  public_host="$(env_file_get "$tmp" ENTRY_PUBLIC_HOST)"
  et_ip="$(env_file_get "$tmp" ENTRY_ET_IP)"
  proto="$(easytier_protocols_from_env "$tmp" EASYTIER_PROTOCOLS EASYTIER_PROTOCOL "$EASYTIER_PROTOCOLS_DEFAULT")" || { fail "入口码里的 EasyTier 传输模式无效。"; rm -f "$tmp"; return 0; }
  port="$(easytier_port_from_env "$tmp" "$proto" EASYTIER_TCP_PORT EASYTIER_UDP_PORT EASYTIER_PORT)" || { rm -f "$tmp"; return 0; }
  pending_match="$(pending_entry_by_ip_port "$et_ip" "$port")"
  pending_same_name="$(pending_entry_by_name "$name")"
  if [[ -n "$pending_same_name" ]]; then
    IFS=$'\t' read -r same_name pending_same_et_ip pending_same_proto pending_same_port _pending_same_created_at <<<"$pending_same_name"
    if [[ "$pending_same_et_ip" != "$et_ip" || "$pending_same_port" != "$port" ]]; then
      warn "未完成接入码同名但 EasyTier IP / 端口不同：${same_name} ${pending_same_et_ip} $(easytier_protocols_display "$pending_same_proto")/${pending_same_port}"
      warn "ENTRY 返回码为：${name} ${et_ip}/${port}。"
      if ! prompt_yes_no "是否忽略这条 pending 并继续保存 ENTRY？" "N"; then
        rm -f "$tmp"
        return 0
      fi
    fi
  fi
  if ! validate_entry_official_fields "$name" "$et_ip" "$port" "$name"; then
    rm -f "$tmp"
    return 0
  fi
  weight="$(env_file_get "$tmp" WEIGHT)"; weight="${weight:-100}"
  enabled="$(env_file_get "$tmp" ENABLED)"; enabled="${enabled:-true}"
  confirm_summary "relay 接入入口摘要" "入口名称：${name}\n入口公网：${public_host}:${port}\n入口 EasyTier 监听：$(easytier_protocols_display "$proto")/${port}\n入口 EasyTier IP：${et_ip}\nRelay EasyTier IP：${RELAY_ET_IP}" || { rm -f "$tmp"; return 0; }
  row="${name}"$'\t'"${public_host}"$'\t'"${et_ip}"$'\t'"${proto}"$'\t'"${port}"$'\t'"${weight}"$'\t'"${enabled}"
  replace_entry_row "$row"
  if [[ -n "$pending_match" ]]; then
    IFS=$'\t' read -r pending_name pending_et_ip _pending_proto pending_port _pending_created_at <<<"$pending_match"
    clear_pending_entry_exact "$pending_name" "$pending_et_ip" "$pending_port"
    ok "已清理未完成接入码预占：${pending_name} / ${pending_et_ip} / ${pending_port}"
    if [[ "$pending_name" != "$name" ]]; then
      info "ENTRY 名称 ${name} 与 pending 名称 ${pending_name} 不同，已按返回码名称保存。"
    fi
  fi
  ok "已保存入口配置：${name}。"
  prompt_apply_relay_after_entry_change || { rm -f "$tmp"; return 1; }
  info "下一步：在 A 公网入口配置端口池后，回到 B 利群主机添加后端转发目标。"
  rm -f "$tmp"
}

pairing_status() {
  echo "network.env：$([[ -f "$NETWORK_ENV" ]] && echo 存在 || echo 不存在) ${NETWORK_ENV}"
  echo "network code：$([[ -f "$NETWORK_PAIRING_FILE" ]] && echo 存在 || echo 不存在) ${NETWORK_PAIRING_FILE}"
  echo "entry code：$([[ -f "$ENTRY_PAIRING_FILE" ]] && echo 存在 || echo 不存在) ${ENTRY_PAIRING_FILE}"
  echo "entries："
  list_entries
}

pairing_menu() {
  local choice
  while true; do
    print_menu_header "快速配对"
    echo "1. 在 B 运行：生成给 A 的网络码"
    echo "2. 在 A 运行：粘贴 B 的网络码，部署 A"
    echo "3. 在 B 运行：粘贴 A 的入口码，完成接入"
    echo "4. 查看 EasyTier 配对状态"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action quick_generate_network_pairing ;;
      2) run_menu_action quick_deploy_entry_from_network_pairing ;;
      3) run_menu_action quick_deploy_relay_from_entry_pairing ;;
      4) run_menu_action pairing_status ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

add_entry() {
  need_root_unless_dry_run
  ensure_tsv_files
  local name public_host et_ip proto port weight enabled row default_ip default_port
  name="$(safe_name "$(prompt_value "入口名称（内部 ASCII，例如 public1 / public2）")")"
  entry_exists "$name" && warn "入口已存在，将覆盖。"
  public_host="$(prompt_host "入口公网 IP 或域名")"
  default_ip="$(next_entry_et_ip 2>/dev/null || printf '%s' "$ENTRY_ET_IP_DEFAULT")"
  default_port="$(next_entry_easytier_port 2>/dev/null || printf '%s' "$EASYTIER_PORT_DEFAULT")"
  while true; do
    et_ip="$(prompt_easytier_ip "入口 EasyTier IP" "$default_ip")"
    proto="$(prompt_easytier_protocols "EasyTier 传输模式" "$EASYTIER_PROTOCOLS_DEFAULT")"
    port="$(prompt_port "EasyTier 监听端口（TCP+UDP，同端口，白名单 8000-9000）" "$default_port")"
    validate_unique_entry_fields "$name" "$et_ip" "$port" "$name" && break
  done
  weight="$(prompt_value "权重" "100")"
  enabled="$(prompt_value "是否启用 true/false" "true")"
  row="${name}"$'\t'"${public_host}"$'\t'"${et_ip}"$'\t'"${proto}"$'\t'"${port}"$'\t'"${weight}"$'\t'"${enabled}"
  confirm_summary "添加入口摘要" "name=${name}\npublic_host=${public_host}\net_ip=${et_ip}\nprotocols=${proto}\nlisten=$(easytier_protocols_display "$proto")/${port}\nport=${port}\nweight=${weight}\nenabled=${enabled}" || return 0
  replace_entry_row "$row"
  clear_pending_entry_reservation "$name" "$et_ip" "$port"
  ok "已保存公网入口：${name}"
  prompt_apply_relay_after_entry_change
}

edit_entry() {
  need_root_unless_dry_run
  ensure_tsv_files
  local name row old_name old_public_host old_et_ip old_proto old_port old_weight old_enabled
  local new_name public_host et_ip proto port weight enabled new_row
  name="$(select_entry_name)" || return 0
  row="$(entries_rows | awk -F'\t' -v n="$name" '$1==n {print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "入口不存在。"; return 0; }
  IFS=$'\034' read -r old_name old_public_host old_et_ip old_proto old_port old_weight old_enabled <<<"$(awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} {print $1,$2,$3,$4,$5,$6,$7}' <<<"$row")"
  while true; do
    new_name="$(safe_name "$(prompt_value "入口名称" "$old_name")")"
    public_host="$(prompt_host "公网 IP / 域名" "$old_public_host")"
    et_ip="$(prompt_easytier_ip "EasyTier IP" "$old_et_ip")"
    proto="$(prompt_easytier_protocols "EasyTier 传输模式" "$old_proto")"
    port="$(prompt_port "EasyTier 监听端口（TCP+UDP，同端口，白名单 8000-9000）" "$old_port")"
    weight="$(prompt_value "权重" "$old_weight")"
    enabled="$(prompt_value "enabled true/false" "$old_enabled")"
    [[ "$weight" =~ ^[0-9]+$ ]] || { warn "权重必须是非负整数。"; continue; }
    [[ "$enabled" == "true" || "$enabled" == "false" ]] || { warn "enabled 必须是 true 或 false。"; continue; }
    validate_unique_entry_fields "$new_name" "$et_ip" "$port" "$old_name" && break
  done
  new_row="${new_name}"$'\t'"${public_host}"$'\t'"${et_ip}"$'\t'"${proto}"$'\t'"${port}"$'\t'"${weight}"$'\t'"${enabled}"
  confirm_summary "修改公网入口摘要" "name=${new_name}\npublic_host=${public_host}\net_ip=${et_ip}\nprotocols=${proto}\nlisten=$(easytier_protocols_display "$proto")/${port}\nweight=${weight}\nenabled=${enabled}" || return 0
  replace_entry_row "$new_row" "$old_name"
  clear_pending_entry_reservation "$new_name" "$et_ip" "$port"
  ok "已修改公网入口：${old_name} -> ${new_name}"
  prompt_apply_relay_after_entry_change
}

list_entries() {
  display_entries
}

delete_entry() {
  need_root_unless_dry_run
  local name tmp
  name="$(select_entry_name)" || return 0
  prompt_yes_no "确认删除入口 ${name}？" "N" || return 0
  auto_snapshot_or_confirm "delete-entry" || return 0
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$ENTRIES_TSV" >"$tmp"
  write_file "$ENTRIES_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
  ok "已删除公网入口：${name}"
  prompt_apply_relay_after_entry_change
}

set_entry_enabled() {
  need_root_unless_dry_run
  local name enabled row old_enabled
  name="$(select_entry_name)" || return 0
  old_enabled="$(entries_rows | awk -F'\t' -v n="$name" '$1==n {print $7; exit}')"
  enabled="$(prompt_value "enabled true/false" "${old_enabled:-true}")"
  [[ "$enabled" == "true" || "$enabled" == "false" ]] || { warn "enabled 必须是 true 或 false。"; return 0; }
  row="$(entries_rows | awk -F'\t' -v n="$name" -v e="$enabled" 'BEGIN{OFS="\t"} $1==n {$7=e; print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "入口不存在。"; return 0; }
  replace_entry_row "$row"
  ok "已更新公网入口：${name} enabled=${enabled}"
  prompt_apply_relay_after_entry_change
}

set_entry_weight() {
  need_root_unless_dry_run
  local name weight row
  name="$(select_entry_name)" || return 0
  weight="$(prompt_value "新权重" "100")"
  [[ "$weight" =~ ^[0-9]+$ ]] || { warn "权重必须是非负整数。"; return 0; }
  row="$(entries_rows | awk -F'\t' -v n="$name" -v w="$weight" 'BEGIN{OFS="\t"} $1==n {$6=w; print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "入口不存在。"; return 0; }
  replace_entry_row "$row"
  ok "已更新公网入口权重：${name} weight=${weight}"
  prompt_apply_relay_after_entry_change
}

switch_primary_entry() {
  need_root_unless_dry_run
  ensure_tsv_files
  local name choice max_weight new_weight content
  name="$(select_entry_name all "请选择要作为主入口的编号或名称，直接回车返回")" || return 0
  echo
  echo "${BOLD}切换模式：${RESET}"
  echo "1. 只启用 ${name}，禁用其它入口（推荐用于手动切换）"
  echo "2. 启用 ${name}，并保留其它入口 enabled（用于多入口备用 / 输出清单）"
  echo "0. 返回"
  choice="$(prompt_menu_choice "请选择：")"
  case "$choice" in
    1)
      content="$(entries_rows | awk -F'\t' -v n="$name" 'BEGIN{OFS="\t"} {$7=($1==n ? "true" : "false"); if ($1==n) $6=100; print}')"
      write_file "$ENTRIES_TSV" "$content" 600
      ok "已切换主公网入口：${name}"
      info "手动切换模式：应用 relay 后只保留 ${name} peer。"
      prompt_apply_relay_after_entry_change
      ;;
    2)
      max_weight="$(entries_rows | awk -F'\t' 'BEGIN{m=0} $6 ~ /^[0-9]+$/ && $6>m {m=$6} END{print m+0}')"
      if (( max_weight < 1000 )); then new_weight=1000; else new_weight=$((max_weight + 10)); fi
      content="$(entries_rows | awk -F'\t' -v n="$name" -v w="$new_weight" 'BEGIN{OFS="\t"} $1==n {$6=w; $7="true"} {print}')"
      write_file "$ENTRIES_TSV" "$content" 600
      ok "已切换主公网入口：${name}"
      info "主备推荐模式：应用 relay 后保留所有 enabled peer，${name} 会在输出清单中标记 PRIMARY。"
      prompt_apply_relay_after_entry_change
      ;;
    3|0|"") return 0 ;;
    *) menu_invalid_choice ;;
  esac
}

bulk_entry_enable_menu() {
  need_root_unless_dry_run
  ensure_tsv_files
  local choice name content count
  count="$(entries_rows | awk 'END{print NR+0}')"
  (( count > 0 )) || { warn "当前没有公网入口。"; return 0; }
  while true; do
    print_menu_header "批量操作"
    echo "1. 启用所有公网入口"
    echo "2. 禁用所有公网入口"
    echo "3. 只保留一个入口 enabled，其它全部 disabled"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1)
        content="$(entries_rows | awk -F'\t' 'BEGIN{OFS="\t"} {$7="true"; print}')"
        write_file "$ENTRIES_TSV" "$content" 600
        ok "已启用所有公网入口。"
        prompt_apply_relay_after_entry_change
        pause_after_action
        return 0
        ;;
      2)
        warn "禁用所有入口会导致 relay 没有公网入口 peer。"
        prompt_yes_no "是否继续？" "N" || return 0
        auto_snapshot_or_confirm "bulk-disable-entries" || return 0
        content="$(entries_rows | awk -F'\t' 'BEGIN{OFS="\t"} {$7="false"; print}')"
        write_file "$ENTRIES_TSV" "$content" 600
        ok "已禁用所有公网入口。"
        prompt_apply_relay_after_entry_change
        pause_after_action
        return 0
        ;;
      3)
        name="$(select_entry_name all "请选择要保留 enabled 的编号或名称，直接回车返回")" || return 0
        auto_snapshot_or_confirm "bulk-disable-entries" || return 0
        content="$(entries_rows | awk -F'\t' -v n="$name" 'BEGIN{OFS="\t"} {$7=($1==n ? "true" : "false"); print}')"
        write_file "$ENTRIES_TSV" "$content" 600
        ok "已只保留公网入口 enabled：${name}"
        prompt_apply_relay_after_entry_change
        pause_after_action
        return 0
        ;;
      4|0|"") return 0 ;;
      *) menu_invalid_choice ;;
    esac
  done
}

select_pending_entry() {
  local count choice row
  count="$(pending_entries_count)"
  (( count > 0 )) || { warn "当前没有未完成接入码。" >&2; return 1; }
  echo >&2
  echo "未完成接入码：" >&2
  display_pending_entries >&2
  echo >&2
  choice="$(prompt_menu_choice "请输入编号、名称或 EasyTier IP，直接回车返回:")"
  choice="$(normalize_menu_choice "$choice")"
  [[ -n "$choice" ]] || return 1
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    row="$(pending_entries_rows | awk -v n="$choice" 'NR==n {print; found=1} END{exit !found}')"
    [[ -n "$row" ]] || { warn "编号无效，请重新选择。" >&2; return 1; }
  else
    row="$(pending_entries_rows | awk -F'\t' -v q="$choice" '$1==q || $2==q {print; found=1; exit} END{exit !found}')"
    [[ -n "$row" ]] || { warn "未完成接入码不存在：${choice}" >&2; return 1; }
  fi
  printf '%s\n' "$row"
}

pending_entries_menu() {
  need_root_unless_dry_run
  ensure_base_dirs
  local choice row name et_ip proto port created_at count
  while true; do
    print_menu_header "未完成接入码"
    if (( $(pending_entries_count) > 0 )); then
      display_pending_entries
    else
      warn "当前没有未完成接入码。"
    fi
    echo
    echo "1. 清理指定未完成接入码"
    echo "2. 清理所有未完成接入码"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1)
        if row="$(select_pending_entry)"; then
          IFS=$'\t' read -r name et_ip proto port created_at <<<"$row"
          if prompt_yes_no "确认清理未完成接入码预占 ${name} / ${et_ip} / ${port}？" "N"; then
            clear_pending_entry_exact "$name" "$et_ip" "$port"
            ok "已清理未完成接入码预占：${name} / ${et_ip} / ${port}"
          fi
          pause_after_action
        fi
        ;;
      2)
        count="$(pending_entries_count)"
        (( count > 0 )) || { warn "当前没有未完成接入码可清理。"; continue; }
        if prompt_yes_no "确认清理所有未完成接入码预占？" "N"; then
          rm -f "$PENDING_ENTRIES_TSV"
          ok "已清理所有未完成接入码预占。"
        fi
        pause_after_action
        ;;
      0|"") return 0 ;;
      *) menu_invalid_choice ;;
    esac
  done
}

entry_peer_text_matches() {
  local peer_text="$1" name="$2" public_host="$3" et_ip="$4" proto="$5" port="$6" peer_url
  grep -Fq "$et_ip" <<<"$peer_text" && return 0
  grep -Fq "$public_host" <<<"$peer_text" && return 0
  while IFS= read -r peer_url; do
    [[ -n "$peer_url" ]] || continue
    grep -Fq "$peer_url" <<<"$peer_text" && return 0
  done < <(easytier_urls "$public_host" "$proto" "$port")
  grep -Fq "$name" <<<"$peer_text" && return 0
  return 1
}

wait_entry_peer_visible() {
  local name="$1" public_host="$2" et_ip="$3" proto="$4" port="$5" attempts="${6:-8}" interval="${7:-1}"
  local i peer_text
  for i in $(seq 1 "$attempts"); do
    peer_text="$(easytier_cli_peer_text)"
    if entry_peer_text_matches "$peer_text" "$name" "$public_host" "$et_ip" "$proto" "$port"; then
      return 0
    fi
    sleep "$interval"
  done
  return 1
}

emit_entry_peer_targets() {
  local name="$1" public_host="$2" proto="$3" port="$4" mode="${5:-plain}" peer_url
  emit_status "$mode" INFO "入口 ${name} peer 目标："
  while IFS= read -r peer_url; do
    [[ -n "$peer_url" ]] && emit_status "$mode" INFO "  * ${peer_url}"
  done < <(easytier_urls "$public_host" "$proto" "$port")
}

check_entry_peer_connectivity() {
  local name="$1" public_host="$2" et_ip="$3" proto="$4" port="$5" mode="${6:-plain}"
  if wait_entry_peer_visible "$name" "$public_host" "$et_ip" "$proto" "$port"; then
    emit_status "$mode" OK "入口 ${name} peer 可见：${et_ip}"
    ping_entry_et_ip "$name" "$et_ip" "$mode" || true
    return 0
  fi
  if ping_entry_et_ip "$name" "$et_ip" "$mode"; then
    emit_status "$mode" INFO "easytier-cli peer 列表暂未显示 ${name}，但 EasyTier IP ping 成功，视为已连通。"
    return 0
  fi
  emit_status "$mode" WARN "入口 ${name} peer 未确认，且 EasyTier IP ping 失败。"
  return 1
}

test_entry_row() {
  local name="$1" public_host="$2" et_ip="$3" proto="$4" port="$5" enabled="$6" ping_mode="${7:-yes}"
  echo
  echo "入口：${name}"
  [[ "$enabled" == "true" ]] || warn "该公网入口当前 disabled，仅执行连通性测试。"
  if easytier_protocols_has "$proto" tcp; then
    case "$(tcp_reachable_status "$public_host" "$port")" in
      0) ok "入口 ${name} TCP 可达：${public_host}:${port}" ;;
      2) warn "未找到 nc，无法测试入口 ${name} TCP；请安装 netcat-openbsd" ;;
      *) warn "入口 ${name} TCP 不可达：${public_host}:${port}" ;;
    esac
  fi
  if easytier_protocols_has "$proto" udp; then
    case "$(udp_probe_status "$public_host" "$port")" in
      0) ok "入口 ${name} UDP 探测完成：${public_host}:${port}" ;;
      2) warn "未找到 nc，无法测试入口 ${name} UDP；请安装 netcat-openbsd" ;;
      *) warn "入口 ${name} UDP 探测未确认。UDP 无连接探测可能不可靠，请结合 EasyTier peer / ping 判断。" ;;
    esac
  fi
  [[ "$ping_mode" == "yes" ]] && ping_entry_et_ip "$name" "$et_ip" plain || true
}

test_entries() {
  local name public_host et_ip proto port _weight enabled
  name="$(select_entry_name)" || return 0
  while IFS=$'\t' read -r name public_host et_ip proto port _weight enabled; do
    test_entry_row "$name" "$public_host" "$et_ip" "$proto" "$port" "$enabled"
    return 0
  done < <(entries_rows | awk -F'\t' -v n="$name" '$1==n')
}

entry_connectivity_ready_once() {
  local name="$1" public_host="$2" et_ip="$3" proto="$4" port="$5"
  local peer_ok=1 ping_ok=1 tcp_ok=0
  wait_entry_peer_visible "$name" "$public_host" "$et_ip" "$proto" "$port" 1 0 && peer_ok=0
  ping -c 1 -W 2 "$et_ip" >/dev/null 2>&1 && ping_ok=0
  if easytier_protocols_has "$proto" tcp; then
    [[ "$(tcp_reachable_status "$public_host" "$port")" == "0" ]] || tcp_ok=1
  fi
  (( ping_ok == 0 && tcp_ok == 0 )) && return 0
  (( peer_ok == 0 && ping_ok == 0 )) && return 0
  return 1
}

test_enabled_entry_with_retry() {
  local name="$1" public_host="$2" et_ip="$3" proto="$4" port="$5" enabled="$6" attempts="${7:-10}" interval="${8:-3}"
  local i
  echo
  emit_entry_peer_targets "$name" "$public_host" "$proto" "$port" plain
  for ((i=1; i<=attempts; i++)); do
    info "等待入口 ${name} 连通：第 ${i}/${attempts} 次..."
    if entry_connectivity_ready_once "$name" "$public_host" "$et_ip" "$proto" "$port"; then
      ok "入口 ${name} 已连通。"
      check_entry_peer_connectivity "$name" "$public_host" "$et_ip" "$proto" "$port" plain || true
      test_entry_row "$name" "$public_host" "$et_ip" "$proto" "$port" "$enabled" no
      return 0
    fi
    (( i < attempts )) && sleep "$interval"
  done
  check_entry_peer_connectivity "$name" "$public_host" "$et_ip" "$proto" "$port" plain || true
  test_entry_row "$name" "$public_host" "$et_ip" "$proto" "$port" "$enabled" no
}

test_all_enabled_entries() {
  local attempts="${1:-10}" interval="${2:-3}"
  local name public_host et_ip proto port _weight enabled tested=0
  ensure_nc_for_test || true
  while IFS=$'\t' read -r name public_host et_ip proto port _weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    tested=1
    test_enabled_entry_with_retry "$name" "$public_host" "$et_ip" "$proto" "$port" "$enabled" "$attempts" "$interval"
  done < <(entries_rows)
  (( tested == 1 )) || warn "没有 enabled 公网入口可测试。"
}

enabled_entries_count() {
  entries_rows | awk -F'\t' '$7=="true"{c++} END{print c+0}'
}

apply_easytier_entry_services() {
  need_root_unless_dry_run
  if machine_looks_like_relay; then
    warn "当前机器看起来是 B 利群主机，不应该启动 entry 服务。"
    warn "如需重启 B，请选择：启动 / 重启 relay 服务。"
    prompt_yes_no "是否仍然继续？" "N" || return 0
  fi
  install_easytier_binary
  local name public_host et_ip proto port weight enabled service
  while IFS=$'\t' read -r name public_host et_ip proto port weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    service="$(render_entry_service "$name" "$et_ip" "$proto" "$port")" || return 1
    write_file "$(entry_service_path "$name")" "$service" 644
    start_service_file "$(entry_service_name "$name")"
    ok "EasyTier entry 已配置：${name} ${et_ip} $(easytier_protocols_display "$proto")/${port} weight=${weight}"
  done < <(entries_rows)
}

apply_easytier_relay_service() {
  need_root_unless_dry_run
  local confirm_mode="${1:-ask}" service enabled_count
  if machine_looks_like_entry; then
    warn "当前机器看起来是 A 公网入口，不应该启动 relay 服务。"
    warn "如需重启 A，请选择：启动 / 重启 entry 服务。"
    prompt_yes_no "是否仍然继续？" "N" || return 0
  fi
  enabled_count="$(enabled_entries_count)"
  if [[ "$confirm_mode" != "confirmed" ]] && (( enabled_count > 0 )); then
    warn "重启 EasyTier relay 会短暂中断所有已接入公网入口。"
    if ! prompt_yes_no "是否继续？" "N"; then
      info "已取消重启 EasyTier relay。"
      return 0
    fi
  fi
  auto_snapshot_or_confirm "restart-relay" || return 0
  install_easytier_binary
  service="$(render_relay_service)" || return 1
  write_file "$EASYTIER_RELAY_SERVICE" "$service" 644
  start_service_file "$EASYTIER_RELAY_SERVICE_NAME"
  ok "EasyTier relay 已配置。"
  wait_systemd_active "$EASYTIER_RELAY_SERVICE_NAME" 15 || warn "15 秒内 easytier-relay.service 未进入 active 状态。"
  wait_et_ip "$RELAY_ET_IP" 15 || warn "15 秒内未检测到 Relay EasyTier IP：${RELAY_ET_IP}"
  test_all_enabled_entries
}

prompt_apply_relay_after_entry_change() {
  info "已更新公网入口配置，但尚未应用到 EasyTier relay。"
  warn "应用公网入口变更需要重启 EasyTier relay，现有入口会短暂中断。"
  if prompt_yes_no "是否现在重启 relay？" "N"; then
    apply_easytier_relay_service confirmed
  else
    info "请在维护窗口执行：利群主机 -> EasyTier 组网管理 -> 启动 / 重启 relay 服务"
  fi
}

reserved_entry_port() {
  case "$1" in
    22|80|443|8301|11010) return 0 ;;
    *) return 1 ;;
  esac
}

route_table_name_from_id() {
  local table="$1"
  [[ -n "$table" ]] || return 1
  if [[ "$table" =~ ^[0-9]+$ && -f "$PBR_RT_TABLES" ]]; then
    awk -v id="$table" '$1==id {print $2; found=1; exit} END{exit !found}' "$PBR_RT_TABLES" 2>/dev/null || printf '%s' "$table"
  else
    printf '%s' "$table"
  fi
}

route_table_display() {
  local table="$1"
  case "$table" in
    ""|main|254) printf '%s' "-" ;;
    *) printf '%s' "$table" ;;
  esac
}

route_table_same() {
  local configured="$1" actual="$2"
  configured="$(normalize_menu_choice "$configured")"
  actual="$(normalize_menu_choice "$actual")"
  [[ "$configured" == "-" ]] && configured=""
  [[ "$actual" == "-" ]] && actual=""
  [[ "$configured" == "254" ]] && configured="main"
  [[ "$actual" == "254" ]] && actual="main"
  [[ -z "$configured" && ( -z "$actual" || "$actual" == "main" ) ]] && return 0
  [[ "$configured" == "$actual" ]]
}

detect_target_route() {
  local host="$1" preferred_table="${2:-}" target_ip route_line dev table src via
  target_ip="$(resolve_ipv4_first "$host" 2>/dev/null || true)"
  [[ -n "$target_ip" ]] || target_ip="$host"
  if [[ -n "$preferred_table" && "$preferred_table" != "-" && "$preferred_table" != "main" ]]; then
    route_line="$(ip route get "$target_ip" table "$preferred_table" 2>/dev/null | head -n 1 || true)"
  else
    route_line=""
  fi
  [[ -n "$route_line" ]] || route_line="$(ip route get "$target_ip" 2>/dev/null | head -n 1 || true)"
  [[ -n "$route_line" ]] || return 1
  dev="$(awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}' <<<"$route_line")"
  table="$(awk '{for (i=1; i<=NF; i++) if ($i=="table") {print $(i+1); exit}}' <<<"$route_line")"
  table="$(route_table_name_from_id "$table" 2>/dev/null || true)"
  src="$(awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' <<<"$route_line")"
  via="$(awk '{for (i=1; i<=NF; i++) if ($i=="via") {print $(i+1); exit}}' <<<"$route_line")"
  printf '%s\034%s\034%s\034%s\034%s\034%s\n' "$target_ip" "$dev" "$table" "$src" "$via" "$route_line"
}

detect_forward_route_defaults() {
  local host="$1" route_info target_ip dev table _src _via _line
  route_info="$(detect_target_route "$host" 2>/dev/null || true)"
  IFS=$'\034' read -r target_ip dev table _src _via _line <<<"$route_info"
  printf '%s\t%s\n' "$dev" "$table"
}

prompt_forward_route_choice() {
  local target_host="$1" current_iface="${2:-}" current_table="${3:-}" route_info target_ip actual_dev actual_table actual_src actual_via route_line
  route_info="$(detect_target_route "$target_host" "$current_table" 2>/dev/null || true)"
  IFS=$'\034' read -r target_ip actual_dev actual_table actual_src actual_via route_line <<<"$route_info"
  if [[ -n "$actual_dev" ]]; then
    echo >&2
    echo "检测到后端目标 ${target_host} 的实际出口：" >&2
    echo "- 目标 IPv4：${target_ip}" >&2
    echo "- 路由表：$(route_table_display "$actual_table")" >&2
    echo "- 出口接口：${actual_dev}" >&2
    echo "- 源地址：${actual_src:-未知}" >&2
    [[ -n "$actual_via" ]] && echo "- 网关：${actual_via}" >&2
    if route_table_same "" "$actual_table"; then
      echo "[INFO] 已检测到实际出口 ${actual_dev}。如你希望固定走 CN2 / 9929，请先配置 PBR，再重新应用转发规则。" >&2
    fi
    if prompt_yes_no "是否使用该出口配置？" "Y"; then
      printf '%s\t%s\n' "$actual_dev" "$actual_table"
      return 0
    fi
  else
    printf '[WARN] 无法通过 ip route get 自动识别 %s 的出口，将进入高级手动输入。\n' "$target_host" >&2
  fi
  local manual_iface manual_table
  manual_iface="$(prompt_value "出口接口 out_iface" "$current_iface")"
  manual_table="$(prompt_value "出口路由表 route_table，留空表示 main/自动" "$current_table")"
  if [[ -n "$manual_table" && "$manual_table" != "-" ]]; then
    route_info="$(detect_target_route "$target_host" "$manual_table" 2>/dev/null || true)"
    IFS=$'\034' read -r _target_ip actual_dev actual_table _actual_src _actual_via _route_line <<<"$route_info"
    if [[ -n "$actual_dev" && "$actual_dev" != "$manual_iface" ]]; then
      printf '[WARN] 路由表 %s 下实际出口接口是 %s，将自动同步 out_iface。\n' "$manual_table" "$actual_dev" >&2
      manual_iface="$actual_dev"
      manual_table="$actual_table"
    fi
  fi
  printf '%s\t%s\n' "$manual_iface" "$manual_table"
}

forward_route_mismatch_text() {
  local name="$1" target_host="$2" configured_iface="$3" configured_table="$4" actual_dev="$5" actual_table="$6"
  if [[ -n "$configured_iface" && "$configured_iface" != "$actual_dev" ]]; then
    cat <<EOF
转发目标 ${name} 出口配置可能错误：
配置 out_iface=${configured_iface:-"-"} route_table=$(route_table_display "$configured_table")
实际路由 dev=${actual_dev:-"-"} table=$(route_table_display "$actual_table")
nftables 规则依赖 oifname=${configured_iface}，实际出口是 ${actual_dev}，这可能导致 A 入口端口可以到 B，但无法转发到后端。
EOF
  else
    cat <<EOF
转发目标 ${name} 路由表元数据可同步：
配置 out_iface=${configured_iface:-"-"} route_table=$(route_table_display "$configured_table")
实际路由 dev=${actual_dev:-"-"} table=$(route_table_display "$actual_table")
出口接口一致；这通常不会单独导致转发失败，但建议同步 route_table 元数据，方便后续诊断和自动修正。
EOF
  fi
}

report_forward_route_consistency() {
  local name="$1" target_host="$2" configured_iface="$3" configured_table="$4"
  local route_info target_ip actual_dev actual_table actual_src actual_via route_line
  route_info="$(detect_target_route "$target_host" 2>/dev/null || true)"
  IFS=$'\034' read -r target_ip actual_dev actual_table actual_src actual_via route_line <<<"$route_info"
  if [[ -z "$actual_dev" ]]; then
    report WARN "转发目标 ${name} 出口无法识别：${target_host}"
    return 0
  fi
  if [[ -n "$configured_iface" && "$configured_iface" != "$actual_dev" ]]; then
    report WARN "转发目标 ${name} 出口接口不一致：配置 ${configured_iface}/$(route_table_display "$configured_table")，实际 ${actual_dev}/$(route_table_display "$actual_table")，可能导致 nft oifname 不匹配。"
  elif ! route_table_same "$configured_table" "$actual_table"; then
    report INFO "转发目标 ${name} 出口接口一致但 route_table 元数据不同：配置 $(route_table_display "$configured_table")，实际 $(route_table_display "$actual_table")。可用 auto-fix-route 同步。"
  else
    report OK "转发目标 ${name} 出口一致：${actual_dev} / $(route_table_display "$actual_table")"
  fi
}

sync_forward_routes_if_needed() {
  local auto_fix="${1:-0}" row name entry_port target_host target_port out_iface route_table enabled comment
  local route_info target_ip actual_dev actual_table actual_src actual_via route_line mismatch fixed=0 tmp content
  validate_forwards_tsv || return 1
  content=$'# name\tentry_port\ttarget_host\ttarget_port\tout_iface\troute_table\tenabled\tcomment'
  while IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment; do
    mismatch=0
    if [[ "$enabled" == "true" ]]; then
      route_info="$(detect_target_route "$target_host" 2>/dev/null || true)"
      IFS=$'\034' read -r target_ip actual_dev actual_table actual_src actual_via route_line <<<"$route_info"
      if [[ -n "$actual_dev" ]]; then
        [[ -n "$out_iface" && "$out_iface" == "$actual_dev" ]] || mismatch=1
        route_table_same "$route_table" "$actual_table" || mismatch=1
        if (( mismatch == 1 )); then
          if [[ -n "$out_iface" && "$out_iface" != "$actual_dev" ]]; then
            warn "$(forward_route_mismatch_text "$name" "$target_host" "$out_iface" "$route_table" "$actual_dev" "$actual_table")"
          else
            info "$(forward_route_mismatch_text "$name" "$target_host" "$out_iface" "$route_table" "$actual_dev" "$actual_table")"
          fi
          if (( auto_fix == 1 )) || { is_interactive && prompt_yes_no "是否自动修正为 out_iface=${actual_dev} route_table=$(route_table_display "$actual_table")？" "Y"; }; then
            out_iface="$actual_dev"
            route_table="$actual_table"
            fixed=1
          else
            warn "未自动修正 ${name}。可执行：lq forward edit ${name}，或 lq forward apply-relay --auto-fix-route"
          fi
        else
          ok "转发目标 ${name} 出口一致：${actual_dev} / $(route_table_display "$actual_table")"
        fi
      else
        warn "无法识别转发目标 ${name} 的实际出口：${target_host}"
      fi
    fi
    row="${name}"$'\t'"${entry_port}"$'\t'"${target_host}"$'\t'"${target_port}"$'\t'"${out_iface}"$'\t'"${route_table}"$'\t'"${enabled}"$'\t'"${comment}"
    content="${content}"$'\n'"${row}"
  done < <(forwards_rows_usv)
  if (( fixed == 1 )); then
    tmp="$(mktemp)"
    printf '%s\n' "$content" >"$tmp"
    write_file "$FORWARDS_TSV" "$(cat "$tmp")" 600
    rm -f "$tmp"
    ok "已自动修正 forwards.tsv 中的出口配置。"
  fi
}

forward_code_path() {
  local name="$1"
  printf '%s/forward-%s.env' "$OUTPUT_DIR" "$name"
}

write_forward_code_file() {
  local file="$1" name="$2" entry_port="$3" target_host="$4" target_port="$5" enabled="$6" comment="$7"
  write_file "$file" "FORWARD_VERSION=0.4
NAME=${name}
ENTRY_PORT=${entry_port}
TARGET_HOST=${target_host}
TARGET_PORT=${target_port}
ENABLED=${enabled}
COMMENT=${comment}" 600
}

print_forward_code() {
  local file="$1"
  echo
  echo "=================================================="
  echo "【复制下面整段到 A 公网入口机】"
  echo "-----BEGIN LEIKWAN FORWARD-----"
  cat "$file"
  echo "-----END LEIKWAN FORWARD-----"
  echo "=================================================="
  echo
  echo "【一行转发码，复制这一行也可以】"
  printf 'LEIKWAN_FORWARD_BASE64=%s\n' "$(pairing_base64 "$file")"
}

parse_forward_raw() {
  local raw="$1" dest="$2" line payload
  : >"$dest"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(normalize_menu_choice "$line")"
    [[ -n "$line" ]] || continue
    case "$line" in
      "-----BEGIN LEIKWAN FORWARD-----"|"-----END LEIKWAN FORWARD-----") continue ;;
    esac
    if [[ "$line" == LEIKWAN_FORWARD_BASE64=* ]]; then
      payload="${line#*=}"
      decode_env_base64 "$payload" "$dest" "FORWARD_VERSION" || { fail "一行转发码解码失败，请重新复制完整内容。"; return 1; }
      return 0
    fi
    if [[ "$line" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && ((${#line} >= 30)); then
      if decode_env_base64 "$line" "$dest" "FORWARD_VERSION"; then
        return 0
      fi
    fi
    if [[ "$line" == *=* ]]; then
      printf '%s\n' "$line" >>"$dest"
    fi
  done <"$raw"
  [[ -s "$dest" ]] || { fail "没有读到有效 FORWARD 转发码。"; return 1; }
}

read_forward_code() {
  local dest="$1" source="${2:-}" raw line has_content=0
  raw="$(mktemp)"
  if [[ -n "$source" ]]; then
    if [[ "$source" == "-" ]]; then
      cat >"$raw"
    elif [[ -f "$source" ]]; then
      cp -a "$source" "$raw"
    else
      printf '%s\n' "$source" >"$raw"
    fi
  else
    echo "请粘贴从 B 利群主机复制的整段 FORWARD 转发码。"
    echo "看到 END 行会自动继续；如果只粘贴 KEY=VALUE 内容，请用空行结束。"
    while IFS= read -r line; do
      line="$(normalize_menu_choice "$line")"
      if [[ -z "$line" ]]; then
        (( has_content == 1 )) && break
        continue
      fi
      has_content=1
      printf '%s\n' "$line" >>"$raw"
      [[ "$line" == "-----END LEIKWAN FORWARD-----" || "$line" == LEIKWAN_FORWARD_BASE64=* ]] && break
      [[ "$line" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && ((${#line} >= 30)) && break
    done
  fi
  parse_forward_raw "$raw" "$dest"
  rm -f "$raw"
}

export_forward_code_by_name() {
  local name="${1:-}" row entry_port target_host target_port out_iface route_table enabled comment file
  ensure_tsv_files
  if [[ -z "$name" ]]; then
    name="$(forwards_rows | awk -F'\t' 'NR==1{print $1}')"
  fi
  [[ -n "$name" ]] || { warn "当前没有转发目标。"; return 0; }
  row="$(forwards_rows | awk -F'\t' -v n="$name" '$1==n {print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "转发不存在：${name}"; return 0; }
  IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment <<<"$(awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} {print $1,$2,$3,$4,$5,$6,$7,$8}' <<<"$row")"
  file="$(forward_code_path "$name")"
  write_forward_code_file "$file" "$name" "$entry_port" "$target_host" "$target_port" "$enabled" "$comment"
  print_forward_code "$file"
}

add_forward() {
  need_root_unless_dry_run
  install_packages iproute2 netcat-openbsd
  ensure_tsv_files
  local name entry_port target_host target_port out_iface route_table enabled comment row target_ip route_defaults existing_name existing_port tcp_rc
  name="$(safe_name "$(prompt_value "转发名称" "service-a")")"
  entry_port="$(prompt_forward_entry_port "$name")" || return 0
  if reserved_entry_port "$entry_port"; then
    warn "该端口属于保留/常用端口：${entry_port}"
    prompt_yes_no "确定强制使用？" "N" || return 0
  fi
  warn_if_forward_port_outside_expose "$entry_port"
  target_host="$(prompt_host "后端目标地址")"
  target_port="$(prompt_required_port "后端目标端口")"
  route_defaults="$(prompt_forward_route_choice "$target_host")"
  IFS=$'\t' read -r out_iface route_table <<<"$route_defaults"
  enabled="$(prompt_value "是否启用 true/false" "true")"
  [[ "$enabled" == "true" || "$enabled" == "false" ]] || { fail "enabled 必须是 true 或 false。"; return 1; }
  comment="$(prompt_value "备注" "${name}-target")"
  target_ip="$(resolve_ipv4_first "$target_host" 2>/dev/null || true)"
  if [[ -n "$target_ip" ]]; then
    if ! is_ipv4 "$target_host"; then
      info "检测到后端目标是域名，当前解析为：${target_ip}"
      info "每次 apply-relay 会重新解析域名并刷新 nftables 规则。"
      info '如果该域名需要固定走 CN2 / 9929，请到 PBR 菜单选择“从现有转发目标添加 PBR”。'
    fi
    ensure_nc_for_test || true
    tcp_rc="$(tcp_reachable_status "$target_ip" "$target_port")"
    case "$tcp_rc" in
      0) ok "后端 TCP 可达：${target_ip}:${target_port}" ;;
      2) warn "未找到 nc，已跳过后端 TCP 测试。你仍可继续写入规则。" ;;
      *) warn "后端 TCP 暂不可达：${target_ip}:${target_port}。你仍可继续写入规则。" ;;
    esac
  else
    warn "后端地址暂未解析：${target_host}。你仍可继续写入规则。"
  fi
  existing_name="$(forwards_rows | awk -F'\t' -v n="$name" '$1==n {print $1; exit}')"
  existing_port="$(forwards_rows | awk -F'\t' -v p="$entry_port" '$2==p {print $1; exit}')"
  if [[ -n "$existing_name" || -n "$existing_port" ]]; then
    warn "检测到同名或同入口端口的转发目标，将覆盖更新：${existing_name:-$existing_port}"
    prompt_yes_no "确认覆盖 / 更新？" "N" || return 0
  fi
  row="${name}"$'\t'"${entry_port}"$'\t'"${target_host}"$'\t'"${target_port}"$'\t'"${out_iface}"$'\t'"${route_table}"$'\t'"${enabled}"$'\t'"${comment}"
  confirm_summary "添加转发目标摘要" "name=${name}\nentry_port=${entry_port}\ntarget=${target_host}:${target_port}\nprotocols=tcp,udp\nout_iface=${out_iface:-auto}\nroute_table=$(route_table_display "$route_table")\nenabled=${enabled}" || return 0
  replace_forward_row "$row"
  apply_nft_rules "leikwan-relay" || warn "relay nftables 未应用成功，请检查后重试。"
  info '下一步：A/B 两边执行"一键诊断"，并从外部机器测试公网入口端口。'
}

list_forwards() {
  display_forwards
}

delete_forward() {
  need_root_unless_dry_run
  local name="${1:-}" tmp
  [[ -n "$name" ]] || name="$(select_forward_name)" || return 0
  name="$(safe_name "$name")"
  forward_exists "$name" || { warn "转发不存在。"; return 0; }
  prompt_yes_no "确认删除转发 ${name}？" "N" || return 0
  auto_snapshot_or_confirm "delete-forward" || return 0
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$FORWARDS_TSV" >"$tmp"
  write_file "$FORWARDS_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
  ok "已删除转发目标：${name}"
  if apply_nft_rules "leikwan-relay"; then
    ok "已重新应用转发规则"
  else
    warn "重新应用转发规则失败；你可以稍后执行：lq forward apply-relay"
  fi
}

set_forward_enabled() {
  need_root_unless_dry_run
  local name enabled row old_enabled
  name="$(select_forward_name)" || return 0
  old_enabled="$(forwards_rows | awk -F'\t' -v n="$name" '$1==n {print $7; exit}')"
  enabled="$(prompt_value "enabled true/false" "${old_enabled:-true}")"
  [[ "$enabled" == "true" || "$enabled" == "false" ]] || { warn "enabled 必须是 true 或 false。"; return 0; }
  row="$(forwards_rows | awk -F'\t' -v n="$name" -v e="$enabled" 'BEGIN{OFS="\t"} $1==n {$7=e; print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "转发不存在。"; return 0; }
  replace_forward_row "$row"
  ok "已更新转发目标：${name} enabled=${enabled}"
  if apply_nft_rules "leikwan-relay"; then
    ok "已重新应用转发规则"
  else
    warn "重新应用转发规则失败；你可以稍后执行：lq forward apply-relay"
  fi
}

edit_forward() {
  need_root_unless_dry_run
  local name row old_name old_port old_host old_tport old_iface old_route old_enabled old_comment
  local entry_port target_host target_port out_iface route_table enabled comment new_row route_defaults
  name="${1:-}"
  [[ -n "$name" ]] || name="$(select_forward_name)" || return 0
  name="$(safe_name "$name")"
  row="$(forwards_rows | awk -F'\t' -v n="$name" '$1==n {print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "转发不存在。"; return 0; }
  IFS=$'\034' read -r old_name old_port old_host old_tport old_iface old_route old_enabled old_comment <<<"$(awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} {print $1,$2,$3,$4,$5,$6,$7,$8}' <<<"$row")"
  entry_port="$(prompt_forward_entry_port "$old_name" "$old_port")" || return 0
  warn_if_forward_port_outside_expose "$entry_port"
  if [[ "$entry_port" != "$old_port" ]] && forwards_rows | awk -F'\t' -v p="$entry_port" '$2==p {found=1} END{exit !found}'; then
    fail "entry_port 已存在：${entry_port}"
    return 1
  fi
  target_host="$(prompt_host "后端 TARGET_HOST" "$old_host")"
  target_port="$(prompt_required_port "后端 TARGET_PORT（当前 ${old_tport}）")"
  route_defaults="$(prompt_forward_route_choice "$target_host" "$old_iface" "$old_route")"
  IFS=$'\t' read -r out_iface route_table <<<"$route_defaults"
  enabled="$(prompt_value "是否启用 true/false" "$old_enabled")"
  comment="$(prompt_value "备注" "$old_comment")"
  new_row="${old_name}"$'\t'"${entry_port}"$'\t'"${target_host}"$'\t'"${target_port}"$'\t'"${out_iface}"$'\t'"${route_table}"$'\t'"${enabled}"$'\t'"${comment}"
  confirm_summary "修改转发目标摘要" "name=${old_name}\nentry_port=${entry_port}\ntarget=${target_host}:${target_port}\nprotocols=tcp,udp\nout_iface=${out_iface:-auto}\nroute_table=$(route_table_display "$route_table")\nenabled=${enabled}" || return 0
  replace_forward_row "$new_row"
  ok "已修改转发目标：${old_name}"
  if apply_nft_rules "leikwan-relay"; then
    ok "已重新应用转发规则"
  else
    warn "重新应用转发规则失败；你可以稍后执行：lq forward apply-relay"
  fi
}

test_forward() {
  local name="${1:-}" row _entry_port target_host target_ip target_port _out_iface _route_table enabled _last_resolved_at _comment
  [[ -n "$name" ]] || name="$(select_forward_name)" || return 0
  name="$(safe_name "$name")"
  forward_exists "$name" || { warn "转发不存在：${name}"; return 0; }
  resolve_forwards || return 1
  row="$(resolved_rows | awk -F'\t' -v n="$name" '$1==n {print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "转发不存在。"; return 0; }
  IFS=$'\034' read -r name _entry_port target_host target_ip target_port _out_iface _route_table enabled _last_resolved_at _comment <<<"$(awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} {print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' <<<"$row")"
  [[ "$enabled" == "true" ]] || warn "该转发当前 disabled，仅执行后端可达性测试。"
  [[ -n "$target_ip" ]] || { warn "目标未解析：${target_host}"; return 0; }
  ensure_nc_for_test || true
  case "$(tcp_reachable_status "$target_ip" "$target_port")" in
    0) ok "${name} target TCP 可达" ;;
    2) warn "未找到 nc，无法测试 ${name} target TCP；请安装 netcat-openbsd" ;;
    *) warn "${name} target TCP 不可达" ;;
  esac
  case "$(udp_probe_status "$target_ip" "$target_port")" in
    0) ok "${name} target UDP 探测完成：${target_ip}:${target_port}" ;;
    2) warn "未找到 nc，无法测试 ${name} target UDP；请安装 netcat-openbsd" ;;
    *) warn "${name} target UDP 探测未确认。UDP 无连接探测可能不可靠，请结合业务实际测试。" ;;
  esac
}

import_forwards_tsv() {
  need_root_unless_dry_run
  local path
  path="$(prompt_value "请输入 forwards.tsv 路径")"
  [[ -f "$path" ]] || { warn "文件不存在：${path}"; return 0; }
  validate_forwards_tsv "$path" || return 1
  confirm_summary "导入 forwards.tsv" "来源：${path}\n目标：${FORWARDS_TSV}" || return 0
  write_file "$FORWARDS_TSV" "$(cat "$path")" 600
  resolve_forwards || return 1
}

import_forward_code() {
  need_root_unless_dry_run
  local source="${1:-}" tmp name entry_port target_host target_port enabled comment row public_host relay_ip
  tmp="$(mktemp)"
  read_forward_code "$tmp" "$source" || { rm -f "$tmp"; return 1; }
  require_env_fields "$tmp" FORWARD_VERSION NAME ENTRY_PORT TARGET_HOST TARGET_PORT ENABLED || { rm -f "$tmp"; return 1; }
  [[ "$(env_file_get "$tmp" FORWARD_VERSION)" == "0.4" ]] || { fail "FORWARD_VERSION 不支持。"; rm -f "$tmp"; return 1; }
  name="$(safe_name "$(env_file_get "$tmp" NAME)")"
  entry_port="$(env_file_get "$tmp" ENTRY_PORT)"
  target_host="$(env_file_get "$tmp" TARGET_HOST)"
  target_port="$(env_file_get "$tmp" TARGET_PORT)"
  enabled="$(env_file_get "$tmp" ENABLED)"
  comment="$(env_file_get "$tmp" COMMENT)"
  is_port "$entry_port" || { fail "ENTRY_PORT 非法：${entry_port}"; rm -f "$tmp"; return 1; }
  is_port "$target_port" || { fail "TARGET_PORT 非法：${target_port}"; rm -f "$tmp"; return 1; }
  [[ "$enabled" == "true" || "$enabled" == "false" ]] || { fail "ENABLED 必须是 true 或 false。"; rm -f "$tmp"; return 1; }
  row="${name}"$'\t'"${entry_port}"$'\t'"${target_host}"$'\t'"${target_port}"$'\t\t\t'"${enabled}"$'\t'"${comment}"
  confirm_summary "导入公网入口转发摘要" "name=${name}\nentry_port=${entry_port}\ntarget=${target_host}:${target_port}\nenabled=${enabled}\n动作：写入本机 forwards.tsv，并应用 cloud-entry nftables。" || { rm -f "$tmp"; return 0; }
  replace_forward_row "$row"
  if [[ ! -f "$ENTRY_EXPOSE_ENV" ]]; then
    warn "未检测到入口端口池配置，将为 legacy import 临时暴露单端口 ${entry_port}。推荐改用 lq entry expose-range。"
    write_file "$ENTRY_EXPOSE_ENV" "ENTRY_EXPOSE_START=${entry_port}
ENTRY_EXPOSE_END=${entry_port}
RELAY_ET_IP=$(current_relay_et_ip)
ENABLED=true" 600
  elif ! port_in_range "$entry_port" "$(entry_expose_start)" "$(entry_expose_end)"; then
    warn "导入端口 ${entry_port} 不在当前入口端口池 $(entry_expose_start)-$(entry_expose_end) 内；请运行 lq entry expose-range 调整端口池。"
  fi
  apply_nft_rules "cloud-entry" || { rm -f "$tmp"; return 1; }
  generate_forward_outputs || true
  public_host="$(current_entry_public_host)"
  relay_ip="$(current_relay_et_ip)"
  echo
  echo "公网入口："
  echo "${public_host}:${entry_port} -> EasyTier relay ${relay_ip}:${entry_port} -> ${target_host}:${target_port}"
  rm -f "$tmp"
}

export_forwards_tsv() {
  ensure_tsv_files
  echo "forwards.tsv：${FORWARDS_TSV}"
  sed -n '1,200p' "$FORWARDS_TSV"
}

resolve_forward_targets_action() {
  display_forward_selection_list all "当前转发目标："
  resolve_forwards
}

resolve_forwards() {
  ensure_tsv_files
  validate_forwards_tsv || return 1
  local content target_ip old_ip name entry_port target_host target_port out_iface route_table enabled comment resolved_at
  resolved_at="$(date '+%F %T')"
  content=$'# name\tentry_port\ttarget_host\tresolved_ip\ttarget_port\tout_iface\troute_table\tenabled\tlast_resolved_at\tcomment'
  while IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment; do
    old_ip="$(last_resolved_ip_for_forward "$name")"
    target_ip="$(resolve_ipv4_first "$target_host" 2>/dev/null || true)"
    if [[ -z "$target_ip" ]]; then
      if [[ -n "$old_ip" ]]; then
        warn "${name} 域名解析失败，继续使用上次解析 IP：${old_ip}"
        target_ip="$old_ip"
      else
        warn "${name} 域名解析失败且没有上次解析 IP，已跳过该转发目标：${target_host}"
        continue
      fi
    elif [[ -n "$old_ip" && "$old_ip" != "$target_ip" ]]; then
      info "转发目标 ${name} 解析变化：${old_ip} -> ${target_ip}"
    fi
    content="${content}"$'\n'"${name}"$'\t'"${entry_port}"$'\t'"${target_host}"$'\t'"${target_ip}"$'\t'"${target_port}"$'\t'"${out_iface}"$'\t'"${route_table}"$'\t'"${enabled}"$'\t'"${resolved_at}"$'\t'"${comment}"
  done < <(forwards_rows_usv)
  write_file "$RESOLVED_TSV" "$content" 600
}

resolved_rows() {
  [[ -f "$RESOLVED_TSV" ]] || return 0
  awk -F'\t' '{gsub(/\r/, "")} NF && $1 !~ /^#/ {print}' "$RESOLVED_TSV"
}

resolved_rows_usv() {
  resolved_rows | awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} NF>=9 {print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}'
}

ddns_config_value() {
  local key="$1" default="$2" value
  value="$(env_file_get "$DDNS_CONFIG" "$key")"
  printf '%s' "${value:-$default}"
}

ddns_config_bool() {
  local key="$1" default="$2" value
  value="$(ddns_config_value "$key" "$default")"
  case "${value,,}" in
    true|yes|1|on) return 0 ;;
    *) return 1 ;;
  esac
}

bool_yes_no() {
  case "${1,,}" in
    true|yes|1|on) printf 'yes' ;;
    *) printf 'no' ;;
  esac
}

bool_to_default() {
  case "${1,,}" in
    true|yes|1|on) printf 'Y' ;;
    *) printf 'N' ;;
  esac
}

bool_enabled_disabled() {
  case "${1,,}" in
    true|yes|1|on) printf 'enabled' ;;
    *) printf 'disabled' ;;
  esac
}

ddns_write_config() {
  local interval="${1:-$(ddns_config_value DDNS_REFRESH_INTERVAL "$DDNS_REFRESH_INTERVAL_DEFAULT")}"
  local refresh_forwards="${2:-$(ddns_config_value DDNS_REFRESH_FORWARDS "$DDNS_REFRESH_FORWARDS_DEFAULT")}"
  local refresh_entries="${3:-$(ddns_config_value DDNS_REFRESH_ENTRIES "$DDNS_REFRESH_ENTRIES_DEFAULT")}"
  local refresh_pbr="${4:-$(ddns_config_value DDNS_REFRESH_PBR "$DDNS_REFRESH_PBR_DEFAULT")}"
  local auto_apply="${5:-$(ddns_config_value DDNS_AUTO_APPLY "$DDNS_AUTO_APPLY_DEFAULT")}"
  local auto_fix="${6:-$(ddns_config_value DDNS_AUTO_FIX_ROUTE "$DDNS_AUTO_FIX_ROUTE_DEFAULT")}"
  local auto_sync_forward_pbr="${7:-$(ddns_config_value DDNS_AUTO_SYNC_FORWARD_PBR "$(ddns_config_value DDNS_AUTO_SYNC_PBR "$DDNS_AUTO_SYNC_FORWARD_PBR_DEFAULT")")}"
  local auto_sync_domain_pbr="${8:-$(ddns_config_value DDNS_AUTO_SYNC_DOMAIN_PBR "$DDNS_AUTO_SYNC_DOMAIN_PBR_DEFAULT")}"
  local entry_auto_restart="${9:-$(ddns_config_value DDNS_ENTRY_AUTO_RESTART_RELAY "$DDNS_ENTRY_AUTO_RESTART_RELAY_DEFAULT")}"
  local keep_old="${10:-$(ddns_config_value DDNS_KEEP_OLD_ON_FAIL "$DDNS_KEEP_OLD_ON_FAIL_DEFAULT")}"
  write_file "$DDNS_CONFIG" "DDNS_REFRESH_INTERVAL=${interval}
DDNS_REFRESH_FORWARDS=${refresh_forwards}
DDNS_REFRESH_ENTRIES=${refresh_entries}
DDNS_REFRESH_PBR=${refresh_pbr}
DDNS_AUTO_APPLY=${auto_apply}
DDNS_AUTO_FIX_ROUTE=${auto_fix}
DDNS_AUTO_SYNC_FORWARD_PBR=${auto_sync_forward_pbr}
DDNS_AUTO_SYNC_DOMAIN_PBR=${auto_sync_domain_pbr}
DDNS_ENTRY_AUTO_RESTART_RELAY=${entry_auto_restart}
DDNS_KEEP_OLD_ON_FAIL=${keep_old}" 600
}

ddns_ensure_config() {
  if [[ ! -f "$DDNS_CONFIG" ]]; then
    ddns_write_config "$DDNS_REFRESH_INTERVAL_DEFAULT" "$DDNS_REFRESH_FORWARDS_DEFAULT" "$DDNS_REFRESH_ENTRIES_DEFAULT" "$DDNS_REFRESH_PBR_DEFAULT" "$DDNS_AUTO_APPLY_DEFAULT" "$DDNS_AUTO_FIX_ROUTE_DEFAULT" "$DDNS_AUTO_SYNC_FORWARD_PBR_DEFAULT" "$DDNS_AUTO_SYNC_DOMAIN_PBR_DEFAULT" "$DDNS_ENTRY_AUTO_RESTART_RELAY_DEFAULT" "$DDNS_KEEP_OLD_ON_FAIL_DEFAULT"
    return 0
  fi
  if ! grep -q '^DDNS_REFRESH_FORWARDS=' "$DDNS_CONFIG" 2>/dev/null ||
    ! grep -q '^DDNS_REFRESH_ENTRIES=' "$DDNS_CONFIG" 2>/dev/null ||
    ! grep -q '^DDNS_REFRESH_PBR=' "$DDNS_CONFIG" 2>/dev/null ||
    ! grep -q '^DDNS_AUTO_SYNC_FORWARD_PBR=' "$DDNS_CONFIG" 2>/dev/null ||
    ! grep -q '^DDNS_AUTO_SYNC_DOMAIN_PBR=' "$DDNS_CONFIG" 2>/dev/null ||
    ! grep -q '^DDNS_ENTRY_AUTO_RESTART_RELAY=' "$DDNS_CONFIG" 2>/dev/null; then
    ddns_write_config
  fi
}

ddns_emit() {
  local level="$1" msg="$2" line
  case "$level" in
    OK) line="[OK] ${msg}" ;;
    WARN) line="[WARN] ${msg}" ;;
    FAIL) line="[FAIL] ${msg}" ;;
    *) line="[INFO] ${msg}" ;;
  esac
  echo "$line"
  if (( DRY_RUN == 0 )) && [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    mkdir -p "$(dirname "$DDNS_LOG_FILE")" 2>/dev/null || true
    printf '[%s] %s\n' "$(status_now)" "$line" >>"$DDNS_LOG_FILE" 2>/dev/null || true
  fi
}

ddns_write_last_status() {
  local result="$1" scope="$2"
  local forward_changed="$3" forward_failed="$4" entry_changed="$5" entry_failed="$6" pbr_changed="$7" pbr_failed="$8"
  local relay_restart_needed="$9" nft_applied="${10}" pbr_applied="${11}" relay_restarted="${12}"
  (( DRY_RUN == 1 )) && return 0
  [[ ${EUID:-$(id -u)} -eq 0 ]] || return 0
  mkdir -p "$STATUS_DIR" 2>/dev/null || return 0
  {
    printf 'LAST_DDNS_TIME=%s\n' "$(status_now)"
    printf 'LAST_DDNS_RESULT=%s\n' "$result"
    printf 'LAST_DDNS_SCOPE=%s\n' "$scope"
    printf 'LAST_DDNS_FORWARD_CHANGED=%s\n' "$forward_changed"
    printf 'LAST_DDNS_FORWARD_FAILED=%s\n' "$forward_failed"
    printf 'LAST_DDNS_ENTRY_CHANGED=%s\n' "$entry_changed"
    printf 'LAST_DDNS_ENTRY_FAILED=%s\n' "$entry_failed"
    printf 'LAST_DDNS_PBR_CHANGED=%s\n' "$pbr_changed"
    printf 'LAST_DDNS_PBR_FAILED=%s\n' "$pbr_failed"
    printf 'LAST_DDNS_RELAY_RESTART_NEEDED=%s\n' "$relay_restart_needed"
    printf 'LAST_DDNS_NFT_APPLIED=%s\n' "$nft_applied"
    printf 'LAST_DDNS_PBR_APPLIED=%s\n' "$pbr_applied"
    printf 'LAST_DDNS_RELAY_RESTARTED=%s\n' "$relay_restarted"
    printf 'LAST_DDNS_VERSION=%s\n' "$TOOL_VERSION"
  } >"$DDNS_STATUS_FILE"
  chmod 600 "$DDNS_STATUS_FILE" 2>/dev/null || true
}

ddns_domain_forward_count() {
  forwards_rows | awk -F'\t' '
    $7=="true" && $3 !~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $3 ~ /[A-Za-z]/ { c++ }
    END { print c+0 }
  '
}

ddns_domain_entry_count() {
  entries_rows | awk -F'\t' '
    $7=="true" && $2 !~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $2 ~ /[A-Za-z]/ { c++ }
    END { print c+0 }
  '
}

ddns_domain_pbr_count() {
  pbr_domain_rows | awk -F'\t' '$4=="true"{c++} END{print c+0}'
}

last_resolved_ip_for_entry() {
  local name="$1"
  resolved_entries_rows | awk -F'\t' -v n="$name" '$1==n && $3!="" {print $3; exit}'
}

last_resolved_changed_for_entry() {
  local name="$1"
  resolved_entries_rows | awk -F'\t' -v n="$name" '$1==n && $5!="" {print $5; exit}'
}

ddns_scope_requested() {
  local scope="$1" wanted="$2"
  [[ "$scope" == "all" || "$scope" == "$wanted" ]]
}

ddns_scope_enabled() {
  local key="$1" default="$2"
  ddns_config_bool "$key" "$default"
}

ddns_timer_state() {
  local timer_state
  timer_state="$(systemd_active_state "${DDNS_SERVICE_NAME}.timer" 2>/dev/null || true)"
  [[ -n "$timer_state" ]] || timer_state="disabled"
  [[ "$timer_state" == "inactive" ]] && timer_state="disabled"
  printf '%s' "$timer_state"
}

ddns_auto_snapshot() {
  local dest
  need_root_unless_dry_run
  dest="${AUTO_SNAPSHOT_DIR}/auto-before-ddns-apply-$(snapshot_timestamp).tar.gz"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] create auto snapshot ${dest}"
    return 0
  fi
  ensure_base_dirs
  if create_snapshot_archive "$dest"; then
    ddns_emit OK "已创建 DDNS 自动快照：${dest}"
    prune_auto_snapshots
    return 0
  fi
  ddns_emit WARN "DDNS 自动快照创建失败，跳过自动应用。"
  return 1
}

ddns_refresh_forwards_scope() {
  validate_forwards_tsv >/dev/null || { DDNS_FORWARD_FAILED="forwards.tsv"; return 1; }
  local content resolved_at name entry_port target_host target_port out_iface route_table enabled comment
  local old_ip target_ip forward_count=0 domain_count=0 changed_count=0 failed_count=0
  resolved_at="$(status_now)"
  content=$'# name\tentry_port\ttarget_host\tresolved_ip\ttarget_port\tout_iface\troute_table\tenabled\tlast_resolved_at\tcomment'
  while IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment; do
    forward_count=$((forward_count + 1))
    old_ip="$(last_resolved_ip_for_forward "$name")"
    target_ip=""
    if is_ipv4 "$target_host"; then
      target_ip="$target_host"
    elif [[ "$enabled" == "true" ]] && is_domain_name "$target_host"; then
      domain_count=$((domain_count + 1))
      target_ip="$(resolve_ipv4_first "$target_host" 2>/dev/null || true)"
      if [[ -z "$target_ip" ]]; then
        failed_count=$((failed_count + 1))
        DDNS_FORWARD_FAILED="${DDNS_FORWARD_FAILED:+${DDNS_FORWARD_FAILED},}${name}"
        if [[ -n "$old_ip" ]]; then
          ddns_emit WARN "转发目标 ${name} 解析失败，保留旧 IP：${old_ip}"
          target_ip="$old_ip"
        else
          ddns_emit WARN "转发目标 ${name} 解析失败，且没有旧 IP：${target_host}"
          continue
        fi
      elif [[ -n "$old_ip" && "$old_ip" == "$target_ip" ]]; then
        ddns_emit OK "转发目标 ${name} 解析未变化：${target_ip}"
      else
        changed_count=$((changed_count + 1))
        DDNS_FORWARD_CHANGED="${DDNS_FORWARD_CHANGED:+${DDNS_FORWARD_CHANGED},}${name}"
        DDNS_FORWARD_NEED_APPLY=1
        ddns_emit WARN "转发目标 ${name} 解析变化：${old_ip:-none} -> ${target_ip}"
        if [[ -n "$route_table" && "$route_table" != "-" ]]; then
          DDNS_FORWARD_PBR_NEED_SYNC=1
          if ! ddns_config_bool DDNS_AUTO_SYNC_FORWARD_PBR "$(ddns_config_value DDNS_AUTO_SYNC_PBR "$DDNS_AUTO_SYNC_FORWARD_PBR_DEFAULT")"; then
            ddns_emit INFO "转发目标 ${name} 的 IP 已变化，PBR 可能需要同步。"
            ddns_emit INFO "可执行：lq pbr sync-from-forwards"
          fi
        fi
      fi
    else
      target_ip="$old_ip"
      if [[ -z "$target_ip" ]] && is_domain_name "$target_host"; then
        target_ip="$(resolve_ipv4_first "$target_host" 2>/dev/null || true)"
      fi
    fi
    [[ -n "$target_ip" ]] || continue
    content="${content}"$'\n'"${name}"$'\t'"${entry_port}"$'\t'"${target_host}"$'\t'"${target_ip}"$'\t'"${target_port}"$'\t'"${out_iface}"$'\t'"${route_table}"$'\t'"${enabled}"$'\t'"${resolved_at}"$'\t'"${comment}"
  done < <(forwards_rows_usv)
  write_file "$RESOLVED_TSV" "$content" 600
  ddns_emit INFO "forwards checked=${forward_count}，domains=${domain_count}，changed=${changed_count}，failed=${failed_count}"
  return 0
}

ddns_refresh_entries_scope() {
  local content checked_at name public_host et_ip proto port weight enabled old_ip new_ip old_changed last_changed
  local entry_count=0 domain_count=0 changed_count=0 failed_count=0
  checked_at="$(status_now)"
  content=$'# name\tpublic_host\tresolved_ip\tlast_checked\tlast_changed'
  while IFS=$'\t' read -r name public_host et_ip proto port weight enabled; do
    if is_domain_name "$public_host"; then
      old_ip="$(last_resolved_ip_for_entry "$name")"
      old_changed="$(last_resolved_changed_for_entry "$name")"
      if [[ "$enabled" == "true" ]]; then
        entry_count=$((entry_count + 1))
        domain_count=$((domain_count + 1))
        new_ip="$(resolve_ipv4_first "$public_host" 2>/dev/null || true)"
        if [[ -z "$new_ip" ]]; then
          failed_count=$((failed_count + 1))
          DDNS_ENTRY_FAILED="${DDNS_ENTRY_FAILED:+${DDNS_ENTRY_FAILED},}${name}"
          if [[ -n "$old_ip" ]]; then
            ddns_emit WARN "公网入口 ${name} 解析失败，保留旧 IP：${old_ip}"
            new_ip="$old_ip"
            last_changed="${old_changed:-$checked_at}"
          else
            ddns_emit WARN "公网入口 ${name} 解析失败，且没有旧 IP：${public_host}"
            continue
          fi
        elif [[ -z "$old_ip" ]]; then
          ddns_emit OK "公网入口 ${name} 解析已记录：${new_ip}"
          last_changed="$checked_at"
        elif [[ "$old_ip" == "$new_ip" ]]; then
          ddns_emit OK "公网入口 ${name} 解析未变化：${new_ip}"
          last_changed="${old_changed:-$checked_at}"
        else
          changed_count=$((changed_count + 1))
          DDNS_ENTRY_CHANGED="${DDNS_ENTRY_CHANGED:+${DDNS_ENTRY_CHANGED},}${name}"
          DDNS_RELAY_RESTART_NEEDED=true
          last_changed="$checked_at"
          ddns_emit WARN "公网入口 ${name} 解析变化：${old_ip:-none} -> ${new_ip}"
        fi
      else
        new_ip="${old_ip:-}"
        last_changed="${old_changed:-}"
      fi
      [[ -n "$new_ip" ]] || continue
      content="${content}"$'\n'"${name}"$'\t'"${public_host}"$'\t'"${new_ip}"$'\t'"${checked_at}"$'\t'"${last_changed}"
    fi
  done < <(entries_rows)
  write_file "$RESOLVED_ENTRIES_TSV" "$content" 600
  ddns_emit INFO "entries checked=${entry_count}，domains=${domain_count}，changed=${changed_count}，failed=${failed_count}"
}

ddns_maybe_restart_relay() {
  local non_interactive="$1"
  [[ "$DDNS_RELAY_RESTART_NEEDED" == "true" ]] || return 0
  ddns_emit WARN "公网入口 ${DDNS_ENTRY_CHANGED} 的 DDNS 解析已变化。"
  ddns_emit WARN "EasyTier relay 可能需要重启才能重新解析 peer。"
  if (( non_interactive == 0 )) && is_interactive; then
    if prompt_yes_no "是否现在重启 relay？" "N"; then
      if apply_easytier_relay_service confirmed; then
        DDNS_RELAY_RESTARTED=true
        ddns_emit OK "已重启 relay。"
      else
        ddns_emit WARN "relay 重启失败，请稍后手动检查。"
        return 1
      fi
    else
      ddns_emit INFO "已记录公网入口 DDNS 变化，但未重启 relay。"
      ddns_emit INFO "可在维护窗口执行：利群主机 -> EasyTier 组网管理 -> 启动 / 重启 relay 服务"
    fi
  elif ddns_config_bool DDNS_ENTRY_AUTO_RESTART_RELAY "$DDNS_ENTRY_AUTO_RESTART_RELAY_DEFAULT"; then
    ddns_emit INFO "DDNS_ENTRY_AUTO_RESTART_RELAY=true，正在自动重启 relay。"
    if apply_easytier_relay_service confirmed; then
      DDNS_RELAY_RESTARTED=true
      ddns_emit OK "已自动重启 relay。"
    else
      ddns_emit WARN "relay 自动重启失败。"
      return 1
    fi
  else
    ddns_emit INFO "timer/非交互模式默认不重启 relay。"
  fi
}

ddns_refresh_once() {
  need_root_unless_dry_run
  ensure_base_dirs
  ddns_ensure_config
  local scope="all" non_interactive=0 arg ddns_lock="" result="ok" auto_apply auto_fix
  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --scope) scope="${2:-all}"; shift 2 ;;
      --non-interactive) non_interactive=1; shift ;;
      *) fail "未知 ddns run 参数：${arg}"; return 1 ;;
    esac
  done
  case "$scope" in
    all|forwards|entries|pbr) ;;
    *) fail "DDNS scope 无效：${scope}"; return 1 ;;
  esac
  DDNS_FORWARD_CHANGED=""; DDNS_FORWARD_FAILED=""; DDNS_ENTRY_CHANGED=""; DDNS_ENTRY_FAILED=""
  DDNS_PBR_CHANGED=""; DDNS_PBR_FAILED=""; DDNS_RELAY_RESTART_NEEDED=false
  DDNS_NFT_APPLIED=false; DDNS_PBR_APPLIED=false; DDNS_RELAY_RESTARTED=false
  DDNS_FORWARD_NEED_APPLY=0; DDNS_FORWARD_PBR_NEED_SYNC=0
  if ! lock_acquire "$DDNS_LOCK_PATH" "DDNS 刷新" ddns_lock; then
    ddns_write_last_status "skipped" "$scope" "" "" "" "" "" "" false false false false
    return 0
  fi
  if ! global_lock_acquire; then
    lock_release "$ddns_lock"
    ddns_write_last_status "skipped" "$scope" "" "" "" "" "" "" false false false false
    return 0
  fi
  ddns_emit INFO "DDNS 刷新开始，scope=${scope}。"
  auto_apply="$(ddns_config_value DDNS_AUTO_APPLY "$DDNS_AUTO_APPLY_DEFAULT")"
  auto_fix="$(ddns_config_value DDNS_AUTO_FIX_ROUTE "$DDNS_AUTO_FIX_ROUTE_DEFAULT")"
  if ddns_scope_requested "$scope" forwards; then
    if ddns_scope_enabled DDNS_REFRESH_FORWARDS "$DDNS_REFRESH_FORWARDS_DEFAULT"; then
      ddns_refresh_forwards_scope || result="fail"
    else
      ddns_emit INFO "forwards scope 已禁用。"
    fi
  fi
  if ddns_scope_requested "$scope" entries; then
    if ddns_scope_enabled DDNS_REFRESH_ENTRIES "$DDNS_REFRESH_ENTRIES_DEFAULT"; then
      ddns_refresh_entries_scope || result="warn"
    else
      ddns_emit INFO "entries scope 已禁用。"
    fi
  fi
  if ddns_scope_requested "$scope" pbr; then
    if ddns_scope_enabled DDNS_REFRESH_PBR "$DDNS_REFRESH_PBR_DEFAULT"; then
      if ddns_config_bool DDNS_AUTO_SYNC_DOMAIN_PBR "$DDNS_AUTO_SYNC_DOMAIN_PBR_DEFAULT"; then
        pbr_domain_sync --from-ddns || result="warn"
        [[ -n "$PBR_DOMAIN_SYNC_CHANGED_NAMES" ]] && DDNS_PBR_CHANGED="$PBR_DOMAIN_SYNC_CHANGED_NAMES"
        [[ -n "$PBR_DOMAIN_SYNC_FAILED_NAMES" ]] && DDNS_PBR_FAILED="$PBR_DOMAIN_SYNC_FAILED_NAMES"
        ddns_emit INFO "pbr domains checked=$(ddns_domain_pbr_count 2>/dev/null || printf '0')，changed=${DDNS_PBR_CHANGED:-none}，failed=${DDNS_PBR_FAILED:-none}"
      else
        ddns_emit INFO "DDNS_AUTO_SYNC_DOMAIN_PBR=false，跳过域名 PBR 自动同步。"
      fi
    else
      ddns_emit INFO "pbr scope 已禁用。"
    fi
  fi
  if (( DDNS_FORWARD_NEED_APPLY == 1 )); then
    if [[ "${auto_apply,,}" == "true" ]]; then
      if ddns_auto_snapshot; then
        ddns_emit INFO "检测到域名后端变化，正在安全重应用 nftables 转发规则。"
        if apply_nft_rules "leikwan-relay" "$([[ "${auto_fix,,}" == "true" ]] && printf '1' || printf '0')"; then
          DDNS_NFT_APPLIED=true
          ddns_emit OK "已重应用 nftables 转发规则。"
        else
          result="fail"
          ddns_emit WARN "nftables 转发规则重应用失败。"
        fi
      else
        result="warn"
      fi
    else
      result="warn"
      ddns_emit WARN "检测到域名后端变化，但 DDNS_AUTO_APPLY=${auto_apply}，未自动应用。"
    fi
  fi
  if (( DDNS_FORWARD_PBR_NEED_SYNC == 1 )); then
    if ddns_config_bool DDNS_AUTO_SYNC_FORWARD_PBR "$(ddns_config_value DDNS_AUTO_SYNC_PBR "$DDNS_AUTO_SYNC_FORWARD_PBR_DEFAULT")"; then
      ddns_emit INFO "DDNS_AUTO_SYNC_FORWARD_PBR=true，正在同步 forward 来源 PBR。"
      pbr_sync_from_forwards --no-apply || result="warn"
    fi
  fi
  if [[ -n "$DDNS_PBR_CHANGED" ]] || { [[ -n "$DDNS_FORWARD_CHANGED" ]] && (( DDNS_FORWARD_PBR_NEED_SYNC == 1 )); }; then
    if [[ "${auto_apply,,}" == "true" ]]; then
      if pbr_apply; then
        DDNS_PBR_APPLIED=true
        ddns_emit OK "已应用 PBR。"
      else
        result="warn"
        ddns_emit WARN "PBR 应用失败。"
      fi
    else
      result="warn"
      ddns_emit INFO "DDNS_AUTO_APPLY=${auto_apply}，已更新 PBR 配置但未应用。"
    fi
  fi
  if ! ddns_maybe_restart_relay "$non_interactive"; then
    result="warn"
  fi
  if [[ -n "$DDNS_FORWARD_FAILED$DDNS_ENTRY_FAILED$DDNS_PBR_FAILED" && "$result" == "ok" ]]; then
    result="warn"
  fi
  ddns_emit INFO "summary scope=${scope} forwards changed=${DDNS_FORWARD_CHANGED:-none} failed=${DDNS_FORWARD_FAILED:-none}; entries changed=${DDNS_ENTRY_CHANGED:-none} failed=${DDNS_ENTRY_FAILED:-none}; pbr changed=${DDNS_PBR_CHANGED:-none} failed=${DDNS_PBR_FAILED:-none}; nft_applied=${DDNS_NFT_APPLIED}; pbr_applied=${DDNS_PBR_APPLIED}; relay_restart_needed=${DDNS_RELAY_RESTART_NEEDED}; relay_restarted=${DDNS_RELAY_RESTARTED}"
  ddns_write_last_status "$result" "$scope" "$DDNS_FORWARD_CHANGED" "$DDNS_FORWARD_FAILED" "$DDNS_ENTRY_CHANGED" "$DDNS_ENTRY_FAILED" "$DDNS_PBR_CHANGED" "$DDNS_PBR_FAILED" "$DDNS_RELAY_RESTART_NEEDED" "$DDNS_NFT_APPLIED" "$DDNS_PBR_APPLIED" "$DDNS_RELAY_RESTARTED"
  ddns_emit INFO "DDNS 刷新结束：$(status_result_display "$result")。"
  global_lock_release
  lock_release "$ddns_lock"
}

render_ddns_service() {
  cat <<EOF
# Managed by leikwan-toolkit ${TOOL_VERSION}
[Unit]
Description=Leikwan DDNS backend / entry / PBR refresh
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/leikwan-toolkit.sh ddns run --non-interactive
EOF
}

render_ddns_timer() {
  local interval
  interval="$(ddns_config_value DDNS_REFRESH_INTERVAL "$DDNS_REFRESH_INTERVAL_DEFAULT")"
  cat <<EOF
# Managed by leikwan-toolkit ${TOOL_VERSION}
[Unit]
Description=Leikwan DDNS backend / entry / PBR refresh timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval}
Unit=${DDNS_SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF
}

ddns_install_units() {
  need_root_unless_dry_run
  ddns_ensure_config
  write_file "$DDNS_SERVICE" "$(render_ddns_service)" 644
  write_file "$DDNS_TIMER" "$(render_ddns_timer)" 644
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || warn "systemd daemon-reload 失败。"
  fi
}

ddns_enable_timer() {
  need_root_unless_dry_run
  ddns_ensure_config
  ddns_install_units
  info "将每 $(ddns_config_value DDNS_REFRESH_INTERVAL "$DDNS_REFRESH_INTERVAL_DEFAULT") 刷新 enabled 后端转发目标、公网入口和域名 PBR。"
  warn "公网入口 DDNS 变化默认只记录 relay restart needed，不会自动中断 relay。"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now "${DDNS_SERVICE_NAME}.timer"
    ok "DDNS 自动刷新 timer 已启用。"
  else
    warn "未找到 systemctl，无法启用 DDNS timer。"
    return 1
  fi
}

ddns_disable_timer() {
  need_root_unless_dry_run
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "${DDNS_SERVICE_NAME}.timer" 2>/dev/null || true
    ok "DDNS 自动刷新 timer 已禁用。"
  else
    warn "未找到 systemctl，无法禁用 DDNS timer。"
  fi
}

ddns_status() {
  local timer_state interval refresh_forwards refresh_entries refresh_pbr auto_apply auto_sync_forward_pbr auto_sync_domain_pbr entry_auto_restart
  local last_time last_result last_scope forward_changed forward_failed entry_changed entry_failed pbr_changed pbr_failed
  local relay_restart_needed nft_applied pbr_applied relay_restarted forward_count entry_count pbr_count
  ddns_ensure_config
  timer_state="$(ddns_timer_state)"
  interval="$(ddns_config_value DDNS_REFRESH_INTERVAL "$DDNS_REFRESH_INTERVAL_DEFAULT")"
  refresh_forwards="$(ddns_config_value DDNS_REFRESH_FORWARDS "$DDNS_REFRESH_FORWARDS_DEFAULT")"
  refresh_entries="$(ddns_config_value DDNS_REFRESH_ENTRIES "$DDNS_REFRESH_ENTRIES_DEFAULT")"
  refresh_pbr="$(ddns_config_value DDNS_REFRESH_PBR "$DDNS_REFRESH_PBR_DEFAULT")"
  auto_apply="$(ddns_config_value DDNS_AUTO_APPLY "$DDNS_AUTO_APPLY_DEFAULT")"
  auto_sync_forward_pbr="$(ddns_config_value DDNS_AUTO_SYNC_FORWARD_PBR "$(ddns_config_value DDNS_AUTO_SYNC_PBR "$DDNS_AUTO_SYNC_FORWARD_PBR_DEFAULT")")"
  auto_sync_domain_pbr="$(ddns_config_value DDNS_AUTO_SYNC_DOMAIN_PBR "$DDNS_AUTO_SYNC_DOMAIN_PBR_DEFAULT")"
  entry_auto_restart="$(ddns_config_value DDNS_ENTRY_AUTO_RESTART_RELAY "$DDNS_ENTRY_AUTO_RESTART_RELAY_DEFAULT")"
  last_time="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_TIME)"
  last_result="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_RESULT)"
  last_scope="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_SCOPE)"
  forward_changed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_FORWARD_CHANGED)"
  forward_failed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_FORWARD_FAILED)"
  entry_changed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_ENTRY_CHANGED)"
  entry_failed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_ENTRY_FAILED)"
  pbr_changed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_PBR_CHANGED)"
  pbr_failed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_PBR_FAILED)"
  relay_restart_needed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_RELAY_RESTART_NEEDED)"
  nft_applied="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_NFT_APPLIED)"
  pbr_applied="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_PBR_APPLIED)"
  relay_restarted="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_RELAY_RESTARTED)"
  forward_count="$(ddns_domain_forward_count 2>/dev/null || printf '0')"
  entry_count="$(ddns_domain_entry_count 2>/dev/null || printf '0')"
  pbr_count="$(ddns_domain_pbr_count 2>/dev/null || printf '0')"
  echo "DDNS 自动刷新状态"
  echo "----------------------------------------"
  echo "timer: ${timer_state}"
  echo "interval: ${interval}"
  echo "forwards: $(bool_enabled_disabled "$refresh_forwards") (${forward_count})"
  echo "entries: $(bool_enabled_disabled "$refresh_entries") (${entry_count})"
  echo "pbr: $(bool_enabled_disabled "$refresh_pbr") (${pbr_count})"
  echo "auto apply: ${auto_apply}"
  echo "auto sync forward pbr: ${auto_sync_forward_pbr}"
  echo "auto sync domain pbr: ${auto_sync_domain_pbr}"
  echo "entry auto restart relay: ${entry_auto_restart}"
  echo "last run: ${last_time:-"-"}"
  echo "last result: ${last_result:-"-"}"
  echo "last scope: ${last_scope:-"-"}"
  echo "forward changed: ${forward_changed:-"-"}"
  echo "forward failed: ${forward_failed:-"-"}"
  echo "entry changed: ${entry_changed:-"-"}"
  echo "entry failed: ${entry_failed:-"-"}"
  echo "pbr changed: ${pbr_changed:-"-"}"
  echo "pbr failed: ${pbr_failed:-"-"}"
  echo "relay restart needed: $(bool_yes_no "${relay_restart_needed:-false}")"
  echo "nft applied: $(bool_yes_no "${nft_applied:-false}")"
  echo "pbr applied: $(bool_yes_no "${pbr_applied:-false}")"
  echo "relay restarted: $(bool_yes_no "${relay_restarted:-false}")"
}

ddns_logs() {
  if [[ -f "$DDNS_LOG_FILE" ]]; then
    tail -n 100 "$DDNS_LOG_FILE"
  else
    info "暂无 DDNS 刷新日志：${DDNS_LOG_FILE}"
  fi
}

ddns_set_interval() {
  need_root_unless_dry_run
  ddns_ensure_config
  local choice interval refresh_forwards refresh_entries refresh_pbr auto_apply auto_fix auto_sync_forward_pbr auto_sync_domain_pbr entry_auto_restart keep_old
  echo
  echo "设置 DDNS 刷新间隔和范围："
  echo "1. 5min"
  echo "2. 10min"
  echo "3. 30min"
  echo "4. 1h"
  echo "0. 返回"
  choice="$(prompt_menu_choice "请选择：")"
  case "$choice" in
    1) interval="5min" ;;
    2) interval="10min" ;;
    3) interval="30min" ;;
    4) interval="1h" ;;
    0|"") return 0 ;;
    *) warn "无效选择。"; return 0 ;;
  esac
  refresh_forwards="$(ddns_config_value DDNS_REFRESH_FORWARDS "$DDNS_REFRESH_FORWARDS_DEFAULT")"
  refresh_entries="$(ddns_config_value DDNS_REFRESH_ENTRIES "$DDNS_REFRESH_ENTRIES_DEFAULT")"
  refresh_pbr="$(ddns_config_value DDNS_REFRESH_PBR "$DDNS_REFRESH_PBR_DEFAULT")"
  auto_apply="$(ddns_config_value DDNS_AUTO_APPLY "$DDNS_AUTO_APPLY_DEFAULT")"
  auto_fix="$(ddns_config_value DDNS_AUTO_FIX_ROUTE "$DDNS_AUTO_FIX_ROUTE_DEFAULT")"
  auto_sync_forward_pbr="$(ddns_config_value DDNS_AUTO_SYNC_FORWARD_PBR "$(ddns_config_value DDNS_AUTO_SYNC_PBR "$DDNS_AUTO_SYNC_FORWARD_PBR_DEFAULT")")"
  auto_sync_domain_pbr="$(ddns_config_value DDNS_AUTO_SYNC_DOMAIN_PBR "$DDNS_AUTO_SYNC_DOMAIN_PBR_DEFAULT")"
  entry_auto_restart="$(ddns_config_value DDNS_ENTRY_AUTO_RESTART_RELAY "$DDNS_ENTRY_AUTO_RESTART_RELAY_DEFAULT")"
  keep_old="$(ddns_config_value DDNS_KEEP_OLD_ON_FAIL "$DDNS_KEEP_OLD_ON_FAIL_DEFAULT")"
  if prompt_yes_no "刷新后端转发目标域名？" "$(bool_to_default "$refresh_forwards")"; then refresh_forwards="true"; else refresh_forwards="false"; fi
  if prompt_yes_no "刷新公网入口 public_host 域名？" "$(bool_to_default "$refresh_entries")"; then refresh_entries="true"; else refresh_entries="false"; fi
  if prompt_yes_no "刷新域名 PBR？" "$(bool_to_default "$refresh_pbr")"; then refresh_pbr="true"; else refresh_pbr="false"; fi
  if prompt_yes_no "域名后端变化后自动重应用 nftables / PBR？" "$(bool_to_default "$auto_apply")"; then auto_apply="true"; else auto_apply="false"; fi
  if prompt_yes_no "转发目标 DDNS 变化后自动同步 forward 来源 PBR？" "$(bool_to_default "$auto_sync_forward_pbr")"; then auto_sync_forward_pbr="true"; else auto_sync_forward_pbr="false"; fi
  if prompt_yes_no "自动同步域名 PBR？" "$(bool_to_default "$auto_sync_domain_pbr")"; then auto_sync_domain_pbr="true"; else auto_sync_domain_pbr="false"; fi
  if prompt_yes_no "公网入口 DDNS 变化后自动重启 relay？" "$(bool_to_default "$entry_auto_restart")"; then entry_auto_restart="true"; else entry_auto_restart="false"; fi
  ddns_write_config "$interval" "$refresh_forwards" "$refresh_entries" "$refresh_pbr" "$auto_apply" "$auto_fix" "$auto_sync_forward_pbr" "$auto_sync_domain_pbr" "$entry_auto_restart" "$keep_old"
  ddns_install_units
  ok "DDNS 刷新间隔已设置为：${interval}"
  if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled --quiet "${DDNS_SERVICE_NAME}.timer" 2>/dev/null; then
    systemctl restart "${DDNS_SERVICE_NAME}.timer" || warn "DDNS timer 重启失败，请稍后手动检查。"
  fi
}

ddns_menu() {
  local choice
  while true; do
    print_menu_header "DDNS 后端 / PBR / 公网入口自动刷新"
    echo "1. 立即刷新全部"
    echo "2. 只刷新后端转发目标"
    echo "3. 只刷新公网入口域名"
    echo "4. 只刷新域名 PBR"
    echo "5. 启用自动刷新"
    echo "6. 禁用自动刷新"
    echo "7. 查看自动刷新状态"
    echo "8. 查看刷新日志"
    echo "9. 设置刷新间隔和范围"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause ddns_refresh_once --scope all ;;
      2) run_menu_action_pause ddns_refresh_once --scope forwards ;;
      3) run_menu_action_pause ddns_refresh_once --scope entries ;;
      4) run_menu_action_pause ddns_refresh_once --scope pbr ;;
      5) run_menu_action_pause ddns_enable_timer ;;
      6) run_menu_action_pause ddns_disable_timer ;;
      7) run_menu_action_pause ddns_status ;;
      8) run_menu_action_pause ddns_logs ;;
      9) run_menu_action_pause ddns_set_interval ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

configure_forward_sysctl() {
  write_file "$FORWARD_SYSCTL" "net.ipv4.ip_forward=1" 644
  (( DRY_RUN == 1 )) || sysctl --system >/dev/null || true
}

render_nft_cloud() {
  local relay_ip start end mss
  if [[ ! -f "$ENTRY_EXPOSE_ENV" ]]; then
    fail "公网入口端口池未配置，请执行 lq entry expose-range。"
    return 1
  fi
  mss="$(tcp_mss_clamp_value)"
  relay_ip="$(entry_expose_relay_ip)"
  start="$(entry_expose_start)"
  end="$(entry_expose_end)"
  if ! is_port "$start" || ! is_port "$end" || (( start > end )); then
    fail "入口端口池配置非法：${start}-${end}"
    return 1
  fi
  cat <<EOF
table inet leikwan_forward {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    tcp dport ${start}-${end} dnat ip to ${relay_ip}
    udp dport ${start}-${end} dnat ip to ${relay_ip}
EOF
  cat <<EOF
  }
  chain forward {
    type filter hook forward priority mangle; policy accept;
    ct state established,related accept
EOF
  if mss_clamp_enabled; then
    printf '    tcp flags syn tcp option maxseg size set %s\n' "$mss"
  fi
  cat <<EOF
    ip daddr ${relay_ip} tcp dport ${start}-${end} accept
    ip daddr ${relay_ip} udp dport ${start}-${end} accept
EOF
  cat <<EOF
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr ${relay_ip} tcp dport ${start}-${end} masquerade
    ip daddr ${relay_ip} udp dport ${start}-${end} masquerade
EOF
  cat <<EOF
  }
}
EOF
}

render_nft_relay() {
  local et_iface name entry_port target_host target_ip target_port out_iface route_table enabled _last_resolved_at comment mss
  mss="$(tcp_mss_clamp_value)"
  et_iface="$(et_iface_by_ip "$RELAY_ET_IP")"
  [[ -n "$et_iface" ]] || et_iface="easytier0"
  cat <<EOF
table inet leikwan_forward {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
EOF
  while IFS=$'\034' read -r name entry_port target_host target_ip target_port out_iface route_table enabled _last_resolved_at comment; do
    [[ "$enabled" == "true" && -n "$target_ip" ]] || continue
    printf '    iifname "%s" tcp dport %s dnat ip to %s:%s\n' "$et_iface" "$entry_port" "$target_ip" "$target_port"
    printf '    iifname "%s" udp dport %s dnat ip to %s:%s\n' "$et_iface" "$entry_port" "$target_ip" "$target_port"
  done < <(resolved_rows_usv)
  cat <<EOF
  }
  chain forward {
    type filter hook forward priority mangle; policy accept;
    ct state established,related accept
EOF
  if mss_clamp_enabled; then
    printf '    tcp flags syn tcp option maxseg size set %s\n' "$mss"
  fi
  while IFS=$'\034' read -r name entry_port target_host target_ip target_port out_iface route_table enabled _last_resolved_at comment; do
    [[ "$enabled" == "true" && -n "$target_ip" ]] || continue
    if [[ -n "$out_iface" ]]; then
      printf '    iifname "%s" oifname "%s" ip daddr %s tcp dport %s accept\n' "$et_iface" "$out_iface" "$target_ip" "$target_port"
      printf '    iifname "%s" oifname "%s" ip daddr %s udp dport %s accept\n' "$et_iface" "$out_iface" "$target_ip" "$target_port"
    else
      printf '    iifname "%s" ip daddr %s tcp dport %s accept\n' "$et_iface" "$target_ip" "$target_port"
      printf '    iifname "%s" ip daddr %s udp dport %s accept\n' "$et_iface" "$target_ip" "$target_port"
    fi
  done < <(resolved_rows_usv)
  cat <<EOF
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
EOF
  while IFS=$'\034' read -r name entry_port target_host target_ip target_port out_iface route_table enabled _last_resolved_at comment; do
    [[ "$enabled" == "true" && -n "$target_ip" ]] || continue
    if [[ -n "$out_iface" ]]; then
      printf '    oifname "%s" ip daddr %s tcp dport %s masquerade\n' "$out_iface" "$target_ip" "$target_port"
      printf '    oifname "%s" ip daddr %s udp dport %s masquerade\n' "$out_iface" "$target_ip" "$target_port"
    else
      printf '    ip daddr %s tcp dport %s masquerade\n' "$target_ip" "$target_port"
      printf '    ip daddr %s udp dport %s masquerade\n' "$target_ip" "$target_port"
    fi
  done < <(resolved_rows_usv)
  cat <<EOF
  }
}
EOF
}

render_nft_service() {
  local nft_bin
  nft_bin="$(command -v nft || printf '%s' /usr/sbin/nft)"
  cat <<EOF
# Managed by leikwan-toolkit ${TOOL_VERSION}
[Unit]
Description=Leikwan nftables L4 forwarding
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${nft_bin} -f ${NFT_RULE_FILE}
ExecStop=-${nft_bin} delete table inet leikwan_forward

[Install]
WantedBy=multi-user.target
EOF
}

detect_role() {
  if systemctl list-unit-files --type=service --no-legend "${EASYTIER_RELAY_SERVICE_NAME}.service" 2>/dev/null | grep -q .; then echo "leikwan-relay"; return; fi
  if et_ip_present "$RELAY_ET_IP"; then echo "leikwan-relay"; return; fi
  if systemctl list-unit-files --type=service --no-legend 'easytier-entry-*.service' 2>/dev/null | grep -q .; then echo "cloud-entry"; return; fi
  if [[ -f "$ENTRY_PAIRING_FILE" ]]; then echo "cloud-entry"; return; fi
  echo "unknown"
}

current_entry_et_ip() {
  local ip
  ip="$(env_file_get "$ENTRY_PAIRING_FILE" ENTRY_ET_IP)"
  [[ -n "$ip" ]] || ip="$(entries_rows | awk -F'\t' '$7=="true"{print $3; exit}')"
  printf '%s' "${ip:-$ENTRY_ET_IP_DEFAULT}"
}

current_relay_et_ip() {
  local ip
  ip="$(env_file_get "$NETWORK_ENV" RELAY_ET_IP)"
  [[ -n "$ip" ]] || ip="$(env_file_get "$NETWORK_ENV" EASYTIER_RELAY_ET_IP)"
  printf '%s' "${ip:-$RELAY_ET_IP}"
}

current_entry_configured_public_host() {
  local host
  host="$(env_file_get "$ENTRY_PAIRING_FILE" ENTRY_PUBLIC_HOST)"
  [[ -n "$host" ]] || host="$(env_file_get "$NETWORK_ENV" ENTRY_PUBLIC_HOST)"
  [[ -n "$host" ]] || host="$(entries_rows | awk -F'\t' '$7=="true"{print $2; exit}')"
  printf '%s' "$host"
}

current_entry_public_host() {
  local host
  host="$(current_entry_configured_public_host)"
  [[ -n "$host" ]] || host="$(detect_public_ipv4 2>/dev/null || true)"
  printf '%s' "${host:-<A_PUBLIC_HOST>}"
}

entry_expose_start() {
  local value
  value="$(env_file_get "$ENTRY_EXPOSE_ENV" ENTRY_EXPOSE_START)"
  printf '%s' "${value:-$ENTRY_EXPOSE_START_DEFAULT}"
}

entry_expose_end() {
  local value
  value="$(env_file_get "$ENTRY_EXPOSE_ENV" ENTRY_EXPOSE_END)"
  printf '%s' "${value:-$ENTRY_EXPOSE_END_DEFAULT}"
}

entry_expose_relay_ip() {
  local value
  value="$(env_file_get "$ENTRY_EXPOSE_ENV" RELAY_ET_IP)"
  [[ -n "$value" ]] || value="$(current_relay_et_ip)"
  printf '%s' "${value:-$RELAY_ET_IP}"
}

parse_port_range() {
  local range="$1" start end
  range="$(normalize_menu_choice "$range")"
  start="${range%-*}"
  end="${range#*-}"
  if is_port "$start" && is_port "$end" && (( start <= end )); then
    printf '%s\t%s\n' "$start" "$end"
    return 0
  fi
  fail "端口范围非法：${range}，格式示例 10000-19999"
  return 1
}

port_in_range() {
  local port="$1" start="$2" end="$3"
  is_port "$port" && is_port "$start" && is_port "$end" && (( port >= start && port <= end ))
}

warn_if_forward_port_outside_expose() {
  local port="$1" start end
  if [[ -f "$ENTRY_EXPOSE_ENV" ]]; then
    start="$(entry_expose_start)"
    end="$(entry_expose_end)"
    if port_in_range "$port" "$start" "$end"; then
      info "entry_port ${port} 位于入口端口池 ${start}-${end}。"
    else
      warn "entry_port ${port} 不在入口端口池 ${start}-${end} 内，公网入口可能无法访问。"
    fi
  else
    info "未读取到 A 入口端口池范围；将仅校验常见端口池 ${FORWARD_ENTRY_PORT_FALLBACK_START}-${FORWARD_ENTRY_PORT_FALLBACK_END}。"
    if port_in_range "$port" "$FORWARD_ENTRY_PORT_FALLBACK_START" "$FORWARD_ENTRY_PORT_FALLBACK_END"; then
      ok "entry_port ${port} 位于常见入口端口池 ${FORWARD_ENTRY_PORT_FALLBACK_START}-${FORWARD_ENTRY_PORT_FALLBACK_END}。"
    else
      warn "entry_port ${port} 不在默认推荐范围 ${FORWARD_ENTRY_PORT_FALLBACK_START}-${FORWARD_ENTRY_PORT_FALLBACK_END} 内。"
    fi
  fi
}

entry_expose_range() {
  need_root_unless_dry_run
  ensure_base_dirs
  local start="$ENTRY_EXPOSE_START_DEFAULT" end="$ENTRY_EXPOSE_END_DEFAULT" relay_ip="" apply="ask" arg range parsed
  local conflict_ports
  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --start)
        start="${2:-}"; shift 2 ;;
      --end)
        end="${2:-}"; shift 2 ;;
      --range)
        range="${2:-}"; parsed="$(parse_port_range "$range")" || return 1
        IFS=$'\t' read -r start end <<<"$parsed"
        shift 2 ;;
      --relay-ip)
        relay_ip="${2:-}"; shift 2 ;;
      --no-apply)
        apply="no"; shift ;;
      *)
        fail "未知 entry expose-range 参数：${arg}"; return 1 ;;
    esac
  done
  if [[ "${start}" == "$ENTRY_EXPOSE_START_DEFAULT" && "${end}" == "$ENTRY_EXPOSE_END_DEFAULT" && -z "${relay_ip}" && "$apply" == "ask" ]]; then
    range="$(prompt_value "入口端口范围" "${ENTRY_EXPOSE_START_DEFAULT}-${ENTRY_EXPOSE_END_DEFAULT}")"
    parsed="$(parse_port_range "$range")" || return 1
    IFS=$'\t' read -r start end <<<"$parsed"
    relay_ip="$(prompt_value "Relay EasyTier IP" "$(current_relay_et_ip)")"
    prompt_yes_no "是否应用 nftables？" "Y" && apply="yes" || apply="no"
  fi
  if ! is_port "$start" || ! is_port "$end" || (( start > end )); then
    fail "入口端口范围非法：${start}-${end}"
    return 1
  fi
  conflict_ports=""
  if command -v ss >/dev/null 2>&1; then
    conflict_ports="$({
      ss -lntH 2>/dev/null
      ss -lunH 2>/dev/null
    } | awk -v s="$start" -v e="$end" '
      {
        p=$4
        sub(/^.*:/, "", p)
        if (p ~ /^[0-9]+$/ && p >= s && p <= e) seen[p]=1
      }
      END {
        for (p in seen) print p
      }
    ' | sort -n | paste -sd, -)"
  fi
  if [[ -n "$conflict_ports" ]]; then
    warn "入口端口池 ${start}-${end} 中发现本机监听端口：${conflict_ports}"
    prompt_yes_no "是否继续配置端口池？" "N" || return 0
  fi
  is_ipv4 "${relay_ip:-$RELAY_ET_IP}" || { fail "Relay EasyTier IP 非法：${relay_ip:-$RELAY_ET_IP}"; return 1; }
  relay_ip="${relay_ip:-$RELAY_ET_IP}"
  confirm_summary "配置公网入口端口池摘要" "ENTRY_EXPOSE_START=${start}\nENTRY_EXPOSE_END=${end}\nRELAY_ET_IP=${relay_ip}\n动作：A 侧把该端口池 TCP+UDP DNAT 到 Relay EasyTier IP，保持原端口不变。" || return 0
  write_file "$ENTRY_EXPOSE_ENV" "ENTRY_EXPOSE_START=${start}
ENTRY_EXPOSE_END=${end}
RELAY_ET_IP=${relay_ip}
ENABLED=true" 600
  if [[ "$apply" != "no" ]]; then
    apply_nft_rules "cloud-entry" || warn "公网入口 nftables 未应用成功，请检查后重试。"
  fi
  info "下一步：回到 B 利群主机，如果需要指定 CN2 / 9929 出口，请先选择第 7 项配置 PBR，再选择第 6 项添加后端转发目标。"
}

warn_forward_apply_ssh_risk() {
  APPLY_NFT_LAST_STATUS=""
  [[ -n "${SSH_CONNECTION:-}" ]] || return 0
  if ! is_interactive; then
    info "正在后台/非交互应用 nftables 转发规则。"
    return 0
  fi
  warn "正在重新应用 nftables 转发规则。"
  warn "如果当前 SSH 连接经过公网入口 / EasyTier / 转发链路，连接可能短暂中断。"
  info "如担心 SSH 断开，可使用："
  echo "nohup lq forward apply-relay --auto-fix-route >${APPLY_RELAY_LOG} 2>&1 &"
  if ! prompt_yes_no "是否继续前台执行？" "Y"; then
    APPLY_NFT_LAST_STATUS="skipped"
    info "已取消前台执行。"
    return 130
  fi
  return 0
}

nft_prepare_project_table_apply_file() {
  local content="$1" output="$2" chain
  : >"$output"
  if nft_project_table_exists; then
    printf '%s\n' 'flush table inet leikwan_forward' >>"$output"
    while IFS= read -r chain; do
      [[ -n "$chain" ]] || continue
      printf 'delete chain inet leikwan_forward %s\n' "$chain" >>"$output"
    done < <(nft_existing_project_chains)
  else
    printf '%s\n' 'add table inet leikwan_forward' >>"$output"
  fi
  awk '
    /^[[:space:]]*chain[[:space:]]+/ {
      chain = $2
      next
    }
    chain != "" && /^[[:space:]]*type[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      print "add chain inet leikwan_forward " chain " { " line " }"
      next
    }
    chain != "" && /^[[:space:]]*}/ {
      chain = ""
      next
    }
    chain != "" {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^[{}]/) {
        print "add rule inet leikwan_forward " chain " " line
      }
    }
  ' <<<"$content" >>"$output"
}

apply_relay_rules_background() {
  need_root_unless_dry_run
  local cmd=()
  if command -v lq >/dev/null 2>&1; then
    cmd=(lq forward apply-relay --auto-fix-route)
  else
    cmd=(bash "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" forward apply-relay --auto-fix-route)
  fi
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] nohup ${cmd[*]} >${APPLY_RELAY_LOG} 2>&1 &"
    return 0
  fi
  nohup "${cmd[@]}" >"$APPLY_RELAY_LOG" 2>&1 &
  info "已后台执行，请稍后查看："
  echo "tail -f ${APPLY_RELAY_LOG}"
  info "后台执行完成后，可运行：lq --doctor"
}

apply_relay_rules_menu() {
  local choice
  while true; do
    print_menu_header "重新应用利群转发规则"
    echo "1. 前台执行"
    echo "2. 后台执行并写入 ${APPLY_RELAY_LOG}"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause apply_nft_rules "leikwan-relay" 1; return 0 ;;
      2) run_menu_action_pause apply_relay_rules_background; return 0 ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

apply_nft_rules() {
  local rc release_global_lock=0
  need_root_unless_dry_run
  if [[ -z "$LEIKWAN_GLOBAL_LOCK_TOKEN" ]]; then
    global_lock_acquire || return 1
    release_global_lock=1
  fi
  set +e
  apply_nft_rules_impl "$@"
  rc=$?
  set -e
  (( release_global_lock == 1 )) && global_lock_release
  return "$rc"
}

apply_nft_rules_impl() {
  local role="$1" auto_fix_route="${2:-0}" content tmp old enabled_count=-1 relay_ip start end proto
  local rollback
  APPLY_NFT_LAST_STATUS=""
  need_root_unless_dry_run
  install_packages nftables iproute2 || return 1
  configure_forward_sysctl || warn "IPv4 转发 sysctl 写入失败，请稍后手动检查。"
  case "$role" in
    cloud-entry)
      [[ -f "$ENTRY_EXPOSE_ENV" ]] || { warn "公网入口端口池未配置，请执行 lq entry expose-range"; return 1; }
      relay_ip="$(entry_expose_relay_ip)"
      start="$(entry_expose_start)"
      end="$(entry_expose_end)"
      if ! content="$(render_nft_cloud)"; then
        fail "公网入口 nftables 规则生成失败。"
        return 1
      fi
      for proto in tcp udp; do
        if ! grep -q "${proto} dport ${start}-${end} dnat ip to ${relay_ip}" <<<"$content"; then
          fail "入口端口池 ${start}-${end} 未生成 ${proto^^} DNAT 规则。"
          return 1
        fi
      done
      ;;
	    leikwan-relay)
	      enabled_count="$(enabled_forwards_count)" || return 1
	      sync_forward_routes_if_needed "$auto_fix_route" || warn "转发出口一致性检查未完成，将继续尝试应用规则。"
	      resolve_forwards || return 1
      if (( enabled_count == 0 )); then
        warn "当前没有任何启用的转发目标。"
        prompt_yes_no "当前没有任何启用的转发目标，是否仍然应用空规则？" "N" || return 0
      fi
      if (( enabled_count > 0 )) && ! resolved_rows | awk -F'\t' '$8=="true" && $4!="" {found=1} END{exit !found}'; then
        fail "没有可用的 resolved 转发规则，已停止应用 nftables。"
        return 1
      fi
      if ! content="$(render_nft_relay)"; then
        fail "利群转发 nftables 规则生成失败。"
        return 1
      fi
      if (( enabled_count > 0 )) && ! grep -q 'dnat ip to ' <<<"$content"; then
        fail "enabled forwards=${enabled_count}，但 relay nftables 未生成 DNAT 规则。"
        return 1
      fi
      warn_forward_apply_ssh_risk || return $?
      ;;
    *) fail "无法识别角色：${role}"; return 1 ;;
  esac
  case "$role" in
    leikwan-relay) auto_snapshot_or_confirm "apply-relay-nft" || return 1 ;;
    cloud-entry) auto_snapshot_or_confirm "apply-entry-nft" || return 1 ;;
  esac
  write_file "$NFT_RULE_FILE" "$content" 644
  write_file "$NFT_SERVICE" "$(render_nft_service)" 644
  (( DRY_RUN == 1 )) && return 0
  tmp="$(mktemp)"; old="$(mktemp)"; rollback="$(mktemp)"
  nft_prepare_project_table_apply_file "$content" "$tmp"
  if ! nft -c -f "$tmp"; then
    fail "nftables 规则校验失败。"
    rm -f "$tmp" "$old" "$rollback"
    return 1
  fi
  nft list table inet leikwan_forward >"$old" 2>/dev/null || true
  if nft -f "$tmp"; then
    if command -v systemctl >/dev/null 2>&1; then
      systemctl daemon-reload || warn "systemd daemon-reload 失败，请稍后手动检查。"
      systemctl enable "${NFT_SERVICE_NAME}.service" || warn "nftables 持久化服务启用失败，请稍后手动检查。"
    else
      warn "未找到 systemctl，nftables 已临时应用但无法创建持久化服务。"
    fi
    if (( enabled_count == 0 )); then
      warn "已应用空 nftables 项目表；当前没有转发 DNAT 规则。"
    elif [[ "$role" == "cloud-entry" ]]; then
      ok "公网入口端口池 nftables 规则已应用。"
    else
      ok "nftables 转发规则已应用。"
    fi
    if mss_clamp_enabled && nft_has_mss_clamp; then
      ok "已自动启用 TCP MSS clamp: $(tcp_mss_clamp_value)"
    fi
  else
    fail "nftables 应用失败，尝试回滚。"
    if [[ -s "$old" ]]; then
      nft_prepare_project_table_apply_file "$(cat "$old")" "$rollback"
      nft -f "$rollback" || true
    else
      nft delete table inet leikwan_forward 2>/dev/null || true
    fi
    rm -f "$tmp" "$old" "$rollback"
    return 1
  fi
  rm -f "$tmp" "$old" "$rollback"
  if [[ "$role" == "leikwan-relay" ]]; then
    write_status_cache apply ok "forward apply-relay"
  fi
}

nft_project_table_exists() {
  command -v nft >/dev/null 2>&1 || return 1
  nft list table inet leikwan_forward >/dev/null 2>&1
}

nft_show_rules() {
  if [[ -f "$NFT_RULE_FILE" ]]; then
    echo
    echo "${BOLD}脚本生成的 nftables 规则文件：${NFT_RULE_FILE}${RESET}"
    sed -n '1,200p' "$NFT_RULE_FILE"
  else
    warn "未找到 nftables 规则文件，请先配置公网入口端口池或利群转发目标。"
  fi
  if ! command -v nft >/dev/null 2>&1; then
    warn "系统未安装 nft 命令，无法读取当前内核规则。"
    return 0
  fi
  echo
  echo "${BOLD}当前内核中的项目 nftables 表：${RESET}"
  if nft_project_table_exists; then
    nft list table inet leikwan_forward || warn "读取 nftables 项目表失败。"
  else
    warn "当前未发现脚本生成的 nftables 表。"
  fi
}

cleanup_nftables_rules() {
  need_root_unless_dry_run
  echo
  echo "${BOLD}将清理以下脚本生成的 nftables 项：${RESET}"
  echo "- nft table inet leikwan_forward"
  echo "- ${NFT_RULE_FILE}"
  echo "- ${NFT_SERVICE}"
  prompt_yes_no "二次确认清理脚本生成的 nftables 规则？" "N" || return 0
  (( DRY_RUN == 1 )) && return 0
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "${NFT_SERVICE_NAME}.service" 2>/dev/null || warn "nftables 持久化服务不存在或停止失败，继续清理文件。"
  else
    warn "未找到 systemctl，跳过服务停止。"
  fi
  if command -v nft >/dev/null 2>&1; then
    if nft_project_table_exists; then
      nft delete table inet leikwan_forward 2>/dev/null || warn "删除 nftables 项目表失败，请手动检查。"
    else
      warn "当前未发现脚本生成的 nftables 表。"
    fi
  else
    warn "系统未安装 nft 命令，跳过内核规则清理。"
  fi
  rm -f "$NFT_RULE_FILE" "$NFT_SERVICE"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || warn "systemd daemon-reload 失败，请稍后手动检查。"
  fi
  ok "nftables 清理完成。"
}

nftables_menu() {
  local choice
  while true; do
    print_menu_header "nftables 规则管理"
    echo "1. 查看当前 nftables 规则"
    echo "2. 重新应用公网入口规则"
    echo "3. 重新应用利群转发规则"
    echo "4. 清理脚本生成的 nftables 规则"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause nft_show_rules ;;
      2) run_menu_action_pause apply_nft_rules "cloud-entry" || warn_and_pause "公网入口 nftables 规则未应用成功。" ;;
      3) run_menu_action_pause apply_nft_rules "leikwan-relay" || warn_and_pause "利群转发 nftables 规则未应用成功。" ;;
      4) run_menu_action_pause cleanup_nftables_rules ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

pbr_init_rt_tables() {
  if [[ ! -f "$PBR_RT_TABLES" ]]; then
    write_file "$PBR_RT_TABLES" $'255 local\n254 main\n253 default\n0 unspec' 644
  fi
}

pbr_domain_rows() {
  [[ -f "$PBR_DOMAIN_TSV" ]] || return 0
  awk -F'\t' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    { gsub(/\r/, "") }
    NF == 0 { next }
    $1 ~ /^#/ { next }
    {
      name=trim($1)
      host=trim($2)
      route_table=trim($3)
      enabled=trim($4)
      comment=trim($5)
      if (name=="" || host=="" || route_table=="" || enabled=="") next
      printf "%s\t%s\t%s\t%s\t%s\n", name, host, route_table, enabled, comment
    }
  ' "$PBR_DOMAIN_TSV"
}

pbr_resolved_domain_rows() {
  [[ -f "$PBR_RESOLVED_DOMAIN_TSV" ]] || return 0
  awk -F'\t' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    { gsub(/\r/, "") }
    NF == 0 { next }
    $1 ~ /^#/ { next }
    {
      name=trim($1)
      host=trim($2)
      resolved_ip=trim($3)
      route_table=trim($4)
      last_checked=trim($5)
      last_changed=trim($6)
      if (name=="" || host=="") next
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", name, host, resolved_ip, route_table, last_checked, last_changed
    }
  ' "$PBR_RESOLVED_DOMAIN_TSV"
}

last_resolved_ip_for_pbr_domain() {
  local name="$1"
  pbr_resolved_domain_rows | awk -F'\t' -v n="$name" '$1==n && $3!="" {print $3; exit}'
}

last_resolved_changed_for_pbr_domain() {
  local name="$1"
  pbr_resolved_domain_rows | awk -F'\t' -v n="$name" '$1==n && $6!="" {print $6; exit}'
}

pbr_group_gateway() {
  case "$1" in
    T_9929|9929) printf '%s' "10.7.0.1" ;;
    T_CN2|CN2) printf '%s' "10.8.0.1" ;;
    T_JPSDWAN|JPSDWAN) printf '%s' "10.3.0.1" ;;
    T_DESDWAN|DESDWAN) printf '%s' "10.3.10.1" ;;
    T_KRSDWAN|KRSDWAN) printf '%s' "10.4.0.1" ;;
    T_HKSDWAN|HKSDWAN) printf '%s' "10.3.50.1" ;;
    T_TWSDWAN|TWSDWAN) printf '%s' "10.3.100.1" ;;
    *) return 1 ;;
  esac
}

pbr_table_id() {
  local group="$1"
  group="${group#T_}"
  case "$group" in
    9929) echo 101 ;; CN2) echo 102 ;; JPSDWAN) echo 103 ;; DESDWAN) echo 104 ;;
    KRSDWAN) echo 105 ;; HKSDWAN) echo 106 ;; TWSDWAN) echo 107 ;; *) return 1 ;;
  esac
}

pbr_refresh_dynamic_rules() {
  [[ -f "$PBR_STATIC_CONF" ]] || return 0
  local tmp line cidr group source_type source_name source_host _rest current_ip new_cidr changed=0
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" || "$line" == \#* ]]; then
      printf '%s\n' "$line" >>"$tmp"
      continue
    fi
    read -r cidr group source_type source_name source_host _rest <<<"$line"
    if [[ "$source_type" == "forward" && -n "$source_host" ]]; then
      if is_ipv4 "$source_host"; then
        new_cidr="${source_host}/32"
      else
        current_ip="$(resolve_ipv4_first "$source_host" 2>/dev/null || true)"
        if [[ -z "$current_ip" ]]; then
          warn "PBR 来源转发 ${source_name} 的域名解析失败，继续使用当前规则：${cidr}"
          printf '%s\n' "$line" >>"$tmp"
          continue
        fi
        new_cidr="${current_ip}/32"
      fi
      if [[ "$new_cidr" != "$cidr" ]]; then
        info "PBR 来源转发 ${source_name} 解析变化：${cidr} -> ${new_cidr}"
        cidr="$new_cidr"
        changed=1
      fi
      printf '%s %s forward %s %s\n' "$cidr" "$group" "$source_name" "$source_host" >>"$tmp"
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$PBR_STATIC_CONF"
  if (( changed == 1 )); then
    write_file "$PBR_STATIC_CONF" "$(cat "$tmp")" 600
  fi
  rm -f "$tmp"
}

pbr_apply() {
  need_root_unless_dry_run
  local release_global_lock=0
  if [[ -z "$LEIKWAN_GLOBAL_LOCK_TOKEN" ]]; then
    global_lock_acquire || return 1
    release_global_lock=1
  fi
  pbr_init_rt_tables
  pbr_refresh_dynamic_rules
  if [[ ! -f "$PBR_STATIC_CONF" ]]; then
    warn "暂无 PBR 静态规则。"
    (( release_global_lock == 1 )) && global_lock_release
    return 0
  fi
  local cidr group _source_type _source_name _source_host table_id gw table_name normalized apply_failed=0
  while ip rule del priority "$PBR_PRIORITY" 2>/dev/null; do :; done
  while read -r cidr group _source_type _source_name _source_host; do
    [[ -n "$cidr" && "$cidr" != \#* ]] || continue
    normalized="$(normalize_ipv4_cidr "$cidr" 2>/dev/null || true)"
    if [[ -z "$normalized" ]]; then
      warn "跳过无效 PBR 目标：${cidr}"
      continue
    fi
    cidr="$normalized"
    group="${group#T_}"
    table_name="T_${group}"
    table_id="$(pbr_table_id "$group" 2>/dev/null || true)"
    if [[ -z "$table_id" ]]; then
      table_id="$(awk -v t="$table_name" '$2==t {print $1; exit}' "$PBR_RT_TABLES" 2>/dev/null || true)"
      [[ -n "$table_id" ]] || table_id="$table_name"
    fi
    gw="$(pbr_group_gateway "$group" 2>/dev/null || true)"
    if [[ "$table_id" =~ ^[0-9]+$ ]]; then
      grep -qE "^[[:space:]]*${table_id}[[:space:]]+${table_name}$" "$PBR_RT_TABLES" 2>/dev/null || echo "${table_id} ${table_name}" >>"$PBR_RT_TABLES"
    fi
    if [[ -n "$gw" ]]; then
      if ! ip route replace default via "$gw" table "$table_id" 2>/dev/null; then
        fail "PBR 路由表 ${table_name} 默认路由写入失败：via ${gw}"
        apply_failed=1
        continue
      fi
    fi
    if ! ip rule add to "$cidr" table "$table_id" priority "$PBR_PRIORITY" 2>/dev/null; then
      fail "PBR 应用失败：${cidr} -> ${table_name}"
      apply_failed=1
      continue
    fi
    ok "PBR：${cidr} -> ${table_name}"
  done <"$PBR_STATIC_CONF"
  (( release_global_lock == 1 )) && global_lock_release
  return "$apply_failed"
}

pbr_select_group() {
  local choice custom
  while true; do
    echo >&2
    echo "请选择线路组：" >&2
    echo "1. CN2 -> T_CN2" >&2
    echo "2. 9929 -> T_9929" >&2
    echo "3. 自定义路由表" >&2
    echo "0. 返回" >&2
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) printf '%s' "CN2"; return 0 ;;
      2) printf '%s' "9929"; return 0 ;;
      3)
        custom="$(prompt_value "请输入自定义 route_table，例如 T_HKSDWAN")"
        custom="${custom#T_}"
        [[ -n "$custom" ]] || { warn "route_table 不能为空。"; continue; }
        printf '%s' "$custom"
        return 0
        ;;
      0|"") return 1 ;;
      *) echo "无效选择，请重新输入。" >&2 ;;
    esac
  done
}

pbr_add_static() {
  need_root_unless_dry_run
  local cidr group input
  while true; do
    input="$(prompt_value "目标 IP/CIDR")"
    cidr="$(normalize_ipv4_cidr "$input" 2>/dev/null || true)"
    [[ -n "$cidr" ]] && break
    if [[ "$input" =~ [A-Za-z] ]]; then
      warn '静态 PBR 只接受 IPv4 或 CIDR。如果要给域名 / DDNS 添加 PBR，请选择“从现有转发目标添加 PBR”。'
    else
      warn "目标 IP/CIDR 无效，请重新输入。"
    fi
  done
  group="$(pbr_select_group)" || return 0
  mkdir -p "$PBR_DIR"
  grep -qxF "${cidr} ${group#T_}" "$PBR_STATIC_CONF" 2>/dev/null || echo "${cidr} ${group#T_}" >>"$PBR_STATIC_CONF"
  pbr_apply
  info "如果这个目标已经存在转发规则，请执行：lq forward apply-relay --auto-fix-route"
}

pbr_add_from_forward() {
  need_root_unless_dry_run
  ensure_tsv_files >/dev/null
  local name row target_host target_ip group cidr
  name="$(select_forward_name enabled "可用于 PBR 的转发目标：")" || return 0
  row="$(forwards_rows | awk -F'\t' -v n="$name" '$1==n {print; exit}')"
  [[ -n "$row" ]] || { warn "转发目标不存在：${name}"; return 0; }
  target_host="$(awk -F'\t' '{print $3}' <<<"$row")"
  target_ip="$(resolve_ipv4_first "$target_host" 2>/dev/null || true)"
  if [[ -z "$target_ip" ]]; then
    warn "无法解析转发目标 ${name}：${target_host}"
    return 0
  fi
  group="$(pbr_select_group)" || return 0
  cidr="${target_ip}/32"
  mkdir -p "$PBR_DIR"
  if grep -qE "^[[:space:]]*${cidr//./\\.}[[:space:]]+${group#T_}([[:space:]]|$)" "$PBR_STATIC_CONF" 2>/dev/null; then
    warn "PBR 已存在：${cidr} -> T_${group#T_}"
  else
    printf '%s %s forward %s %s\n' "$cidr" "${group#T_}" "$name" "$target_host" >>"$PBR_STATIC_CONF"
    ok "已从转发目标添加 PBR：${name} ${target_host}(${target_ip}) -> T_${group#T_}"
  fi
  if pbr_apply; then
    if prompt_yes_no "是否立即重新应用转发规则并同步 route_table？" "Y"; then
      if apply_nft_rules "leikwan-relay" 1; then
        ok "已重新应用转发规则并同步 route_table 元数据。"
      else
        warn "PBR 已添加，但转发规则重新应用失败；请稍后执行：lq forward apply-relay --auto-fix-route"
      fi
    else
      info "PBR 已添加。请稍后执行：lq forward apply-relay --auto-fix-route 以同步转发目标元数据。"
    fi
  else
    warn "PBR 已写入，但应用失败；请稍后执行：lq pbr apply"
  fi
}

pbr_rows() {
  [[ -f "$PBR_STATIC_CONF" ]] || return 0
  local line line_no=0 cidr group source_type source_name rest normalized table_name source
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="${line//$'\r'/}"
    line="$(normalize_menu_choice "$line")"
    [[ -n "$line" && "$line" != \#* ]] || continue
    cidr=""
    group=""
    source_type=""
    source_name=""
    rest=""
    read -r cidr group source_type source_name rest <<<"$line"
    [[ -n "$cidr" && -n "$group" ]] || continue
    normalized="$(normalize_ipv4_cidr "$cidr" 2>/dev/null || true)"
    [[ -n "$normalized" ]] || normalized="$cidr"
    table_name="${group#T_}"
    if [[ -z "$source_type" ]]; then
      source="static"
    elif [[ "$source_type" == "forward" && -n "$source_name" ]]; then
      source="forward:${source_name}"
      [[ -n "$rest" ]] && source="${source} ${rest}"
    else
      source="$source_type"
      [[ -n "$source_name" ]] && source="${source} ${source_name}"
      [[ -n "$rest" ]] && source="${source} ${rest}"
    fi
    printf '%s\t%s\t%s\t%s\n' "$line_no" "$normalized" "T_${table_name}" "$source"
  done <"$PBR_STATIC_CONF"
}

pbr_rules_count() {
  pbr_rows | awk 'END{print NR+0}'
}

display_pbr_rules() {
  local numbered="${1:-no}" title="${2:-}" labels
  [[ -n "$title" ]] && { echo; echo "$title"; }
  labels=$'编号\t目标网段\t路由表\t来源'
  if [[ "$numbered" == "numbered" ]]; then
    pbr_rows | awk -F'\t' '{printf "%d.\t%s\t%s\t%s\n", ++i, $2, $3, $4}' | render_tsv_table 78 "$labels"
  else
    pbr_rows | awk -F'\t' '{printf "%d.\t%s\t%s\t%s\n", ++i, $2, $3, $4}' | render_tsv_table 78 "$labels"
  fi
}

pbr_show() {
  local count
  echo
  count="$(pbr_rules_count)"
  if (( count == 0 )); then
    info "当前没有 PBR 规则。"
    return 0
  fi
  display_pbr_rules
}

resolve_pbr_rule_selection() {
  local choice="$1" selected target count
  choice="$(normalize_menu_choice "$choice")"
  [[ -n "$choice" ]] || return 1
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    selected="$(pbr_rows | awk -F'\t' -v idx="$choice" 'NR==idx {print; exit}')"
    [[ -n "$selected" ]] || return 2
  else
    target="$(normalize_ipv4_cidr "$choice" 2>/dev/null || true)"
    [[ -n "$target" ]] || target="$choice"
    selected="$(pbr_rows | awk -F'\t' -v cidr="$target" '$2==cidr {print}')"
    count="$(printf '%s\n' "$selected" | awk 'NF {c++} END{print c+0}')"
    (( count > 0 )) || return 4
    (( count == 1 )) || return 3
  fi
  printf '%s\n' "$selected"
}

warn_pbr_selection_error() {
  local rc="$1" choice="$2"
  case "$rc" in
    2) warn "编号无效，请重新选择。" ;;
    3) warn "同一目标网段存在多条 PBR 规则，请输入编号精确选择。" ;;
    *) warn "PBR 规则不存在：${choice}" ;;
  esac
}

select_pbr_rule() {
  local choice selected rc count
  count="$(pbr_rules_count)"
  if (( count == 0 )); then
    warn "当前没有 PBR 规则可删除。" >&2
    return 1
  fi
  display_pbr_rules numbered "当前 PBR 规则：" >&2
  echo >&2
  while true; do
    choice="$(prompt_value "请输入编号或目标网段，直接回车返回")"
    [[ -z "$choice" ]] && return 1
    if selected="$(resolve_pbr_rule_selection "$choice")"; then
      printf '%s\n' "$selected"
      return 0
    else
      rc=$?
      warn_pbr_selection_error "$rc" "$choice" >&2
    fi
  done
}

delete_pbr_rule() {
  need_root_unless_dry_run
  local selection="${1:-}" selected rc line_no cidr table _source tmp count
  count="$(pbr_rules_count)"
  if (( count == 0 )); then
    warn "当前没有 PBR 规则可删除。"
    return 0
  fi
  if [[ -n "$selection" ]]; then
    if selected="$(resolve_pbr_rule_selection "$selection")"; then
      :
    else
      rc=$?
      warn_pbr_selection_error "$rc" "$selection"
      return 0
    fi
  else
    selected="$(select_pbr_rule)" || return 0
  fi
  IFS=$'\t' read -r line_no cidr table _source <<<"$selected"
  prompt_yes_no "确认删除 PBR 规则 ${cidr} -> ${table}？" "N" || return 0
  auto_snapshot_or_confirm "delete-pbr-rule" || return 0
  tmp="$(mktemp)"
  awk -v del="$line_no" 'NR != del {print}' "$PBR_STATIC_CONF" >"$tmp"
  write_file "$PBR_STATIC_CONF" "$(cat "$tmp")" 600
  rm -f "$tmp"
  ok "已删除 PBR 规则：${cidr} -> ${table}"
  if pbr_apply; then
    ok "PBR 已重新应用"
  else
    warn "PBR 规则已删除，但重新应用失败。请稍后执行 PBR -> 应用 PBR。"
  fi
}

pbr_rule_key_exists() {
  local file="$1" cidr="$2" group="$3"
  [[ -f "$file" ]] || return 1
  awk -v cidr="$cidr" -v group="${group#T_}" '
    /^[[:space:]]*($|#)/ { next }
    {
      g=$2
      sub(/^T_/, "", g)
      if ($1 == cidr && g == group) found=1
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

pbr_domain_source_exists() {
  local file="$1" name="$2"
  [[ -f "$file" ]] || return 1
  awk -v src="pbr-domain:${name}" '
    /^[[:space:]]*($|#)/ { next }
    $3 == src { found=1 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

replace_pbr_domain_row() {
  local row="$1" name tmp
  IFS=$'\t' read -r name _ <<<"$row"
  ensure_tsv_files
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$PBR_DOMAIN_TSV" >"$tmp"
  printf '%s\n' "$row" >>"$tmp"
  write_file "$PBR_DOMAIN_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
}

display_pbr_domains() {
  local labels
  labels=$'编号\t名称\t域名\t路由表\t启用\t备注'
  pbr_domain_rows | awk -F'\t' '{printf "%d.\t%s\t%s\t%s\t%s\t%s\n", ++i, $1, $2, $3, $4, ($5!="" ? $5 : "-")}' | render_tsv_table 100 "$labels"
}

pbr_domain_list() {
  if ! pbr_domain_rows | awk 'NR==1 {found=1} END{exit !found}'; then
    info "当前没有域名 PBR。"
    return 0
  fi
  display_pbr_domains
}

select_pbr_domain_name() {
  local choice name
  if ! pbr_domain_rows | awk 'NR==1 {found=1} END{exit !found}'; then
    warn "当前没有域名 PBR。" >&2
    return 1
  fi
  display_pbr_domains >&2
  while true; do
    choice="$(prompt_value "请输入编号或名称，直接回车返回")"
    [[ -z "$choice" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      name="$(pbr_domain_rows | awk -F'\t' -v idx="$choice" 'NR==idx {print $1; exit}')"
    else
      name="$(pbr_domain_rows | awk -F'\t' -v n="$choice" '$1==n {print $1; exit}')"
    fi
    [[ -n "$name" ]] && { printf '%s' "$name"; return 0; }
    warn "域名 PBR 不存在：${choice}" >&2
  done
}

pbr_domain_sync() {
  need_root_unless_dry_run
  ensure_tsv_files >/dev/null
  local no_apply=1 from_ddns=0 arg acquired_lock=0
  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --apply) no_apply=0; shift ;;
      --no-apply) no_apply=1; shift ;;
      --from-ddns) from_ddns=1; no_apply=1; shift ;;
      *) fail "未知 pbr domain sync 参数：${arg}"; return 1 ;;
    esac
  done
  if [[ -z "$LEIKWAN_GLOBAL_LOCK_TOKEN" ]]; then
    global_lock_acquire || return 0
    acquired_lock=1
  fi
  local tmp_static tmp_resolved checked_at name host route_table enabled comment old_ip new_ip old_changed last_changed
  local cidr group candidates=0 synced=0 skipped=0 failed=0 changed=0 rc=0
  PBR_DOMAIN_SYNC_CHANGED_NAMES=""
  PBR_DOMAIN_SYNC_FAILED_NAMES=""
  mkdir -p "$PBR_DIR"
  [[ -f "$PBR_STATIC_CONF" ]] || : >"$PBR_STATIC_CONF"
  tmp_static="$(mktemp)"
  tmp_resolved="$(mktemp)"
  checked_at="$(status_now)"
  awk '
    /^[[:space:]]*($|#)/ { print; next }
    $3 ~ /^pbr-domain:/ { next }
    { print }
  ' "$PBR_STATIC_CONF" >"$tmp_static"
  printf '# name\thost\tresolved_ip\troute_table\tlast_checked\tlast_changed\n' >"$tmp_resolved"
  while IFS=$'\t' read -r name host route_table enabled comment; do
    old_ip="$(last_resolved_ip_for_pbr_domain "$name")"
    old_changed="$(last_resolved_changed_for_pbr_domain "$name")"
    if [[ "$enabled" != "true" ]]; then
      [[ -n "$old_ip" ]] && printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$host" "$old_ip" "$route_table" "$checked_at" "${old_changed:-$checked_at}" >>"$tmp_resolved"
      continue
    fi
    candidates=$((candidates + 1))
    if ! is_domain_name "$host"; then
      warn "域名 PBR ${name} 的 host 不是域名：${host}"
      failed=$((failed + 1))
      PBR_DOMAIN_SYNC_FAILED_NAMES="${PBR_DOMAIN_SYNC_FAILED_NAMES:+${PBR_DOMAIN_SYNC_FAILED_NAMES},}${name}"
      continue
    fi
    new_ip="$(resolve_ipv4_first "$host" 2>/dev/null || true)"
    if [[ -z "$new_ip" ]]; then
      failed=$((failed + 1))
      PBR_DOMAIN_SYNC_FAILED_NAMES="${PBR_DOMAIN_SYNC_FAILED_NAMES:+${PBR_DOMAIN_SYNC_FAILED_NAMES},}${name}"
      if [[ -n "$old_ip" ]]; then
        warn "域名 PBR ${name} 解析失败，保留旧 IP：${old_ip}"
        new_ip="$old_ip"
        last_changed="${old_changed:-$checked_at}"
      else
        warn "域名 PBR ${name} 解析失败，且没有旧 IP：${host}"
        continue
      fi
    elif [[ -n "$old_ip" && "$old_ip" == "$new_ip" ]]; then
      ok "域名 PBR ${name} 解析未变化：${new_ip}"
      last_changed="${old_changed:-$checked_at}"
    else
      changed=$((changed + 1))
      PBR_DOMAIN_SYNC_CHANGED_NAMES="${PBR_DOMAIN_SYNC_CHANGED_NAMES:+${PBR_DOMAIN_SYNC_CHANGED_NAMES},}${name}"
      warn "域名 PBR ${name} 解析变化：${old_ip:-none} -> ${new_ip}"
      last_changed="$checked_at"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$host" "$new_ip" "$route_table" "$checked_at" "$last_changed" >>"$tmp_resolved"
    cidr="${new_ip}/32"
    group="${route_table#T_}"
    if pbr_rule_key_exists "$tmp_static" "$cidr" "$group"; then
      skipped=$((skipped + 1))
      info "已存在同 CIDR/table 的非域名 PBR，跳过 pbr-domain:${name} ${cidr} -> T_${group}"
      continue
    fi
    printf '%s %s pbr-domain:%s %s\n' "$cidr" "$group" "$name" "$host" >>"$tmp_static"
    synced=$((synced + 1))
  done < <(pbr_domain_rows)
  write_file "$PBR_RESOLVED_DOMAIN_TSV" "$(cat "$tmp_resolved")" 600
  write_file "$PBR_STATIC_CONF" "$(cat "$tmp_static")" 600
  rm -f "$tmp_static" "$tmp_resolved"
  if (( candidates == 0 )); then
    info "没有 enabled 域名 PBR 需要同步。"
  else
    info "域名 PBR 同步完成：enabled=${candidates}，写入=${synced}，已有=${skipped}，changed=${changed}，failed=${failed}。"
  fi
  if (( no_apply == 0 )); then
    pbr_apply || rc=1
  elif (( from_ddns == 0 )); then
    info "如需立即生效，请执行：lq --pbr-apply"
  fi
  (( acquired_lock == 1 )) && global_lock_release
  (( rc == 0 )) || return "$rc"
  (( failed == 0 ))
}

pbr_domain_add() {
  need_root_unless_dry_run
  ensure_tsv_files >/dev/null
  local name host group route_table enabled comment row resolved
  name="$(safe_name "$(prompt_value "域名 PBR 名称" "tw")")"
  [[ -n "$name" ]] || { warn "域名 PBR 名称不能为空。"; return 0; }
  while true; do
    host="$(prompt_host "域名 host")"
    is_domain_name "$host" && break
    warn "域名 PBR 的 host 必须是域名，不能是纯 IPv4。"
  done
  group="$(pbr_select_group)" || return 0
  route_table="T_${group#T_}"
  enabled="$(prompt_value "enabled true/false" "true")"
  [[ "$enabled" == "true" || "$enabled" == "false" ]] || { warn "enabled 必须是 true 或 false。"; return 0; }
  comment="$(prompt_value "备注" "${name}-ddns-pbr")"
  resolved="$(resolve_ipv4_first "$host" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || { warn "域名暂未解析成功，未写入域名 PBR：${host}"; return 0; }
  row="${name}"$'\t'"${host}"$'\t'"${route_table}"$'\t'"${enabled}"$'\t'"${comment}"
  confirm_summary "添加域名 PBR 摘要" "name=${name}\nhost=${host}\nresolved=${resolved}\nroute_table=${route_table}\nenabled=${enabled}\nsource=pbr-domain:${name} ${host}" || return 0
  replace_pbr_domain_row "$row"
  pbr_domain_sync --apply
}

pbr_domain_delete() {
  need_root_unless_dry_run
  ensure_tsv_files >/dev/null
  local name tmp
  name="$(select_pbr_domain_name)" || return 0
  prompt_yes_no "确认删除域名 PBR ${name}？" "N" || return 0
  auto_snapshot_or_confirm "delete-pbr-domain" || return 0
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$PBR_DOMAIN_TSV" >"$tmp"
  write_file "$PBR_DOMAIN_TSV" "$(cat "$tmp")" 600
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$PBR_RESOLVED_DOMAIN_TSV" >"$tmp"
  write_file "$PBR_RESOLVED_DOMAIN_TSV" "$(cat "$tmp")" 600
  [[ -f "$PBR_STATIC_CONF" ]] || : >"$PBR_STATIC_CONF"
  awk -v src="pbr-domain:${name}" '
    /^[[:space:]]*($|#)/ { print; next }
    $3 == src { next }
    { print }
  ' "$PBR_STATIC_CONF" >"$tmp"
  write_file "$PBR_STATIC_CONF" "$(cat "$tmp")" 600
  rm -f "$tmp"
  ok "已删除域名 PBR：${name}"
  pbr_apply
}

pbr_domain_menu() {
  local choice
  while true; do
    print_menu_header "域名 PBR 管理"
    echo "1. 添加域名 PBR"
    echo "2. 查看域名 PBR"
    echo "3. 删除域名 PBR"
    echo "4. 立即同步域名 PBR"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause pbr_domain_add ;;
      2) run_menu_action_pause pbr_domain_list ;;
      3) run_menu_action_pause pbr_domain_delete ;;
      4) run_menu_action_pause pbr_domain_sync ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

pbr_sync_from_forwards() {
  need_root_unless_dry_run
  ensure_tsv_files >/dev/null
  resolve_forwards >/dev/null 2>&1 || true
  mkdir -p "$PBR_DIR"
  [[ -f "$PBR_STATIC_CONF" ]] || : >"$PBR_STATIC_CONF"
  local no_apply=0 arg acquired_lock=0
  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --apply) no_apply=0; shift ;;
      --no-apply) no_apply=1; shift ;;
      *) fail "未知 pbr sync-from-forwards 参数：${arg}"; return 1 ;;
    esac
  done
  if [[ -z "$LEIKWAN_GLOBAL_LOCK_TOKEN" ]]; then
    global_lock_acquire || return 0
    acquired_lock=1
  fi
  local tmp name _entry_port target_host target_ip _target_port _out_iface route_table enabled _resolved_at _comment
  local cidr group synced=0 skipped=0 candidates=0 rc=0
  tmp="$(mktemp)"
  awk '
    /^[[:space:]]*($|#)/ { print; next }
    $3 == "forward" { next }
    { print }
  ' "$PBR_STATIC_CONF" >"$tmp"

  while IFS=$'\034' read -r name _entry_port target_host target_ip _target_port _out_iface route_table enabled _resolved_at _comment; do
    [[ "$enabled" == "true" ]] || continue
    [[ -n "$target_ip" ]] || continue
    [[ -n "$route_table" && "$route_table" != "-" ]] || continue
    candidates=$((candidates + 1))
    cidr="${target_ip}/32"
    group="${route_table#T_}"
    if pbr_rule_key_exists "$tmp" "$cidr" "$group"; then
      skipped=$((skipped + 1))
      info "PBR 已存在，跳过 forward:${name} ${cidr} -> T_${group}"
      continue
    fi
    printf '%s %s forward %s %s\n' "$cidr" "$group" "$name" "$target_host" >>"$tmp"
    synced=$((synced + 1))
    ok "已同步 forward PBR：${name} ${cidr} -> T_${group}"
  done < <(resolved_rows_usv)

  write_file "$PBR_STATIC_CONF" "$(cat "$tmp")" 600
  rm -f "$tmp"
  if (( candidates == 0 )); then
    info "没有需要同步 PBR 的 enabled 转发目标。"
  else
    info "PBR 同步完成：新增 ${synced}，已存在 ${skipped}。"
  fi
  if (( no_apply == 0 )); then
    pbr_apply || rc=1
  else
    info "已更新 forward 来源 PBR 配置，稍后由统一流程应用。"
  fi
  (( acquired_lock == 1 )) && global_lock_release
  return "$rc"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

html_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

output_generated_at() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

write_output_status() {
  write_named_status "${STATUS_DIR}/last-output.env" "LAST_OUTPUT" "ok" "forward-endpoints" "$FORWARD_TXT"
}

generate_forward_outputs() {
  local quiet="${1:-0}"
  ensure_tsv_files
  validate_forwards_tsv || return 1
  mkdir -p "$OUTPUT_DIR"
  local generated_at txt tsv json html name entry_port target_host target_port out_iface route_table enabled comment
  local e_name e_label public_host et_ip proto port weight e_enabled tcp_health udp_health role rank enabled_entries enabled_forwards
  local first_entry=1 first_forward=1 first_endpoint=1 tcp_endpoint udp_endpoint protocols_json
  generated_at="$(output_generated_at)"
  enabled_entries="$(enabled_entries_sorted | awk 'END{print NR+0}')"
  enabled_forwards="$(forwards_rows | awk -F'\t' '$7=="true"{c++} END{print c+0}')"
  txt="【转发入口清单】"$'\n'
  txt="${txt}生成时间：${generated_at}"$'\n'
  txt="${txt}脚本版本：${TOOL_VERSION}"$'\n'
  txt="${txt}公网入口：${enabled_entries} enabled"$'\n'
  txt="${txt}转发目标：${enabled_forwards} enabled"$'\n'
  tsv=$'generated_at\tversion\ttarget_name\tentry_name\tentry_label\trole\tpublic_host\tentry_port\tprotocols\ttcp_endpoint\tudp_endpoint\ttarget_host\ttarget_port\troute_table\tcomment\ttcp_health\tudp_health\tweight\tenabled'
  json="{"
  json="${json}"$'\n'"  \"version\": \"$(json_escape "$TOOL_VERSION")\","
  json="${json}"$'\n'"  \"generated_at\": \"$(json_escape "$generated_at")\","
  json="${json}"$'\n'"  \"entries\": ["
  rank=0
  while IFS=$'\t' read -r e_name public_host et_ip proto port weight e_enabled; do
    rank=$((rank + 1))
    if (( rank == 1 )); then role="PRIMARY"; else role="BACKUP"; fi
    e_label="$(entry_label "$e_name")"
    protocols_json="[\"tcp\", \"udp\"]"
    tcp_endpoint="tcp://${public_host}:${port}"
    udp_endpoint="udp://${public_host}:${port}"
    (( first_entry == 0 )) && json="${json},"
    first_entry=0
    json="${json}"$'\n'"    {\"name\":\"$(json_escape "$e_name")\",\"label\":\"$(json_escape "$e_label")\",\"role\":\"${role}\",\"public_host\":\"$(json_escape "$public_host")\",\"protocols\":${protocols_json},\"port\":${port},\"easytier_port\":${port},\"tcp_endpoint\":\"$(json_escape "$tcp_endpoint")\",\"udp_endpoint\":\"$(json_escape "$udp_endpoint")\",\"enabled\":$([[ "$e_enabled" == "true" ]] && printf 'true' || printf 'false')}"
  done < <(enabled_entries_sorted)
  json="${json}"$'\n'"  ],"
  json="${json}"$'\n'"  \"forwards\": ["
  while IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment; do
    [[ "$enabled" == "true" ]] || continue
    (( first_forward == 0 )) && json="${json},"
    first_forward=0
    json="${json}"$'\n'"    {\"name\":\"$(json_escape "$name")\",\"entry_port\":${entry_port},\"protocols\":[\"tcp\", \"udp\"],\"target_host\":\"$(json_escape "$target_host")\",\"target_port\":${target_port},\"route_table\":\"$(json_escape "${route_table:-}")\",\"comment\":\"$(json_escape "$comment")\",\"enabled\":true}"
  done < <(forwards_rows_usv)
  json="${json}"$'\n'"  ],"
  json="${json}"$'\n'"  \"endpoints\": ["

  html='<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
  html="${html}<title>Leikwan 转发端点</title><style>body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;margin:0;background:#f6f7f9;color:#172033}main{max-width:1100px;margin:auto;padding:24px}h1{font-size:24px}h2{font-size:18px;margin-top:28px}.note{background:#fff7d6;border:1px solid #ead27a;padding:12px;border-radius:6px}.target{background:white;border:1px solid #d8dde6;border-radius:8px;margin:16px 0;padding:16px}.endpoint{display:grid;grid-template-columns:92px 1fr;gap:8px;border-top:1px solid #edf0f5;padding:10px 0}.badge{font-weight:700}.primary{color:#126c3a}.backup{color:#6b5870}code{word-break:break-all}@media(max-width:640px){main{padding:14px}.endpoint{grid-template-columns:1fr}}</style></head><body><main>"
  html="${html}<h1>Leikwan 转发端点</h1><p>生成时间：$(html_escape "$generated_at")<br>脚本版本：$(html_escape "$TOOL_VERSION")</p>"
  html="${html}<div class=\"note\">端点输出仅用于分享 TCP/UDP 访问入口，不是代理链接，不包含 EasyTier network secret 或配对码。</div>"
  html="${html}<h2>公网入口</h2>"
  rank=0
  while IFS=$'\t' read -r e_name public_host et_ip proto port weight e_enabled; do
    [[ "$e_enabled" == "true" ]] || continue
    rank=$((rank + 1))
    if (( rank == 1 )); then role="PRIMARY"; else role="BACKUP"; fi
    e_label="$(entry_label "$e_name")"
    tcp_endpoint="tcp://${public_host}:${port}"
    udp_endpoint="udp://${public_host}:${port}"
    html="${html}<div class=\"endpoint\"><div><span class=\"badge $([[ "$role" == "PRIMARY" ]] && printf 'primary' || printf 'backup')\">${role}</span><br>$(html_escape "$e_label")</div><div><strong>TCP</strong> <code>$(html_escape "$tcp_endpoint")</code><br><strong>UDP</strong> <code>$(html_escape "$udp_endpoint")</code><br>enabled=true</div></div>"
  done < <(enabled_entries_sorted)
  html="${html}<h2>转发目标</h2>"

  while IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment; do
    [[ "$enabled" == "true" ]] || continue
    txt="${txt}"$'\n'"目标：${name}"$'\n'"后端：${target_host}:${target_port}"$'\n'"入口端口：${entry_port} TCP+UDP"$'\n'"route_table：${route_table:-"-"}"$'\n'"备注：${comment:-"-"}"$'\n'"入口："$'\n'
    html="${html}<section class=\"target\"><h2>$(html_escape "$name")</h2><p>后端：<code>$(html_escape "$target_host"):${target_port}</code><br>入口端口：${entry_port} TCP / UDP<br>route_table：$(html_escape "${route_table:-"-"}")<br>备注：$(html_escape "${comment:-"-"}")</p>"
    rank=0
    while IFS=$'\t' read -r e_name public_host et_ip proto port weight e_enabled; do
      [[ "$e_enabled" == "true" ]] || continue
      rank=$((rank + 1))
      if (( rank == 1 )); then role="PRIMARY"; else role="BACKUP"; fi
      tcp_health="UNKNOWN"
      udp_health="UNKNOWN"
      if command -v nc >/dev/null 2>&1; then
        if nc -vz -w 2 "$public_host" "$entry_port" >/dev/null 2>&1; then tcp_health="UP"; else tcp_health="DOWN"; fi
        if nc -uvz -w 2 "$public_host" "$entry_port" >/dev/null 2>&1; then udp_health="PROBED"; fi
      fi
      e_label="$(entry_label "$e_name")"
      tcp_endpoint="tcp://${public_host}:${entry_port}"
      udp_endpoint="udp://${public_host}:${entry_port}"
      txt="${txt}* ${role} ${e_label}  TCP ${tcp_endpoint}  UDP ${udp_endpoint}  状态：TCP=${tcp_health} UDP=${udp_health}  权重：${weight}"$'\n'
      tsv="${tsv}"$'\n'"${generated_at}"$'\t'"${TOOL_VERSION}"$'\t'"${name}"$'\t'"${e_name}"$'\t'"${e_label}"$'\t'"${role}"$'\t'"${public_host}"$'\t'"${entry_port}"$'\t'"tcp,udp"$'\t'"${tcp_endpoint}"$'\t'"${udp_endpoint}"$'\t'"${target_host}"$'\t'"${target_port}"$'\t'"${route_table}"$'\t'"${comment}"$'\t'"${tcp_health}"$'\t'"${udp_health}"$'\t'"${weight}"$'\t'"${e_enabled}"
      (( first_endpoint == 0 )) && json="${json},"
      first_endpoint=0
      json="${json}"$'\n'"    {\"target\":\"$(json_escape "$name")\",\"entry\":\"$(json_escape "$e_name")\",\"label\":\"$(json_escape "$e_label")\",\"role\":\"${role}\",\"entry_port\":${entry_port},\"protocols\":[\"tcp\", \"udp\"],\"tcp_endpoint\":\"$(json_escape "$tcp_endpoint")\",\"udp_endpoint\":\"$(json_escape "$udp_endpoint")\"}"
      html="${html}<div class=\"endpoint\"><div><span class=\"badge $([[ "$role" == "PRIMARY" ]] && printf 'primary' || printf 'backup')\">${role}</span><br>$(html_escape "$e_label")</div><div><strong>TCP</strong> <code>$(html_escape "$tcp_endpoint")</code><br><strong>UDP</strong> <code>$(html_escape "$udp_endpoint")</code><br>状态：TCP=$(html_escape "$tcp_health") UDP=$(html_escape "$udp_health")</div></div>"
    done < <(enabled_entries_sorted)
    html="${html}</section>"
  done < <(forwards_rows_usv)
  json="${json}"$'\n'"  ]"$'\n'"}"
  html="${html}</main></body></html>"
  txt="${txt}"$'\n'"[INFO] 本工具不会自动把外部客户端流量按权重分流；权重用于排序和推荐。"$'\n'
  txt="${txt}[INFO] 真正负载均衡需要客户端、DNS 或外部 LB 配合。"$'\n'
  txt="${txt}[INFO] 如需手动切换入口，请使用：公网入口列表管理 -> 切换主公网入口。"$'\n'
  txt="${txt}[INFO] 端点输出不包含 EasyTier secret，不等于代理链接。"
  write_file "$FORWARD_TXT" "$txt" 644
  write_file "$FORWARD_TSV" "$tsv" 644
  write_file "$FORWARD_JSON" "$json" 644
  write_file "$FORWARD_HTML" "$html" 644
  write_output_status
  if (( quiet == 0 )); then
    cat "$FORWARD_TXT"
    echo
    ok "已生成：${FORWARD_TXT}"
    ok "已生成：${FORWARD_TSV}"
    ok "已生成：${FORWARD_JSON}"
    ok "已生成：${FORWARD_HTML}"
  fi
}

output_show() {
  [[ -f "$FORWARD_TXT" ]] || generate_forward_outputs 1
  cat "$FORWARD_TXT"
}

output_json() {
  [[ -f "$FORWARD_JSON" ]] || generate_forward_outputs 1
  cat "$FORWARD_JSON"
}

output_html() {
  [[ -f "$FORWARD_HTML" ]] || generate_forward_outputs 1
  ok "HTML 输出：${FORWARD_HTML}"
}

output_qr() {
  ensure_tsv_files
  validate_forwards_tsv || return 1
  if ! command -v qrencode >/dev/null 2>&1; then
    info "未安装 qrencode，跳过二维码输出。"
    return 0
  fi
  mkdir -p "$FORWARD_QR_DIR"
  local name entry_port target_host target_port out_iface route_table enabled comment
  local e_name public_host et_ip proto port weight e_enabled tcp_endpoint udp_endpoint tcp_png udp_png count=0
  while IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment; do
    [[ "$enabled" == "true" ]] || continue
    while IFS=$'\t' read -r e_name public_host et_ip proto port weight e_enabled; do
      [[ "$e_enabled" == "true" ]] || continue
      tcp_endpoint="tcp://${public_host}:${entry_port}"
      udp_endpoint="udp://${public_host}:${entry_port}"
      tcp_png="${FORWARD_QR_DIR}/$(safe_name "${name}-${e_name}-tcp").png"
      udp_png="${FORWARD_QR_DIR}/$(safe_name "${name}-${e_name}-udp").png"
      qrencode -o "$tcp_png" "$tcp_endpoint"
      qrencode -o "$udp_png" "$udp_endpoint"
      count=$((count + 2))
    done < <(enabled_entries_sorted)
  done < <(forwards_rows_usv)
  ok "已生成二维码 ${count} 个：${FORWARD_QR_DIR}"
}

config_export_time() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

config_sensitive_redact_tree() {
  local root="$1" file
  [[ -d "$root" ]] || return 0
  while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    LC_ALL=C grep -Iq . "$file" 2>/dev/null || continue
    sed -E -i \
      -e 's/(EASYTIER_NETWORK_SECRET=).*/\1REDACTED/g' \
      -e 's/(([A-Za-z0-9_]*PAIRING[A-Za-z0-9_]*BASE64=)).*/\1REDACTED/g' \
      -e 's/(LEIKWAN_[A-Z0-9_]*_BASE64=).*/\1REDACTED/g' \
      -e 's/(([A-Za-z0-9_]*)(SECRET|Secret|secret|TOKEN|Token|token|PASSWORD|Password|password)([A-Za-z0-9_]*)([[:space:]_=-]+))[^[:space:]]+/\1REDACTED/g' \
      -e 's/(PrivateKey[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1REDACTED/g' \
      "$file" 2>/dev/null || true
  done < <(find "$root" -type f -size -5M -print0 2>/dev/null)
}

config_package_mode_label() {
  case "${1:-full}" in
    redacted) printf 'redacted' ;;
    *) printf 'full' ;;
  esac
}

write_config_export_status() {
  write_named_status "${STATUS_DIR}/last-config-export.env" "LAST_CONFIG_EXPORT" "$1" "$2" "$3"
}

write_config_import_status() {
  write_named_status "${STATUS_DIR}/last-config-import.env" "LAST_CONFIG_IMPORT" "$1" "$2" "$3"
}

config_export_copy_path() {
  local src="$1" dest_dir="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$dest_dir"
  cp -a "$src" "$dest_dir/"
}

config_manifest_env() {
  local mode="$1" contains_secret="$2" export_time="$3" role="$4" entries_count="$5" forwards_count="$6" pbr_count="$7" ddns_enabled="$8" hostname
  hostname="$(hostname 2>/dev/null || printf 'unknown')"
  cat <<EOF
LEIKWAN_CONFIG_FORMAT=1
EXPORT_TIME=${export_time}
EXPORT_VERSION=${TOOL_VERSION}
EXPORT_HOSTNAME=${hostname}
EXPORT_ROLE=${role}
EXPORT_MODE=${mode}
CONTAINS_SECRET=${contains_secret}
ENTRIES_COUNT=${entries_count}
FORWARDS_COUNT=${forwards_count}
PBR_COUNT=${pbr_count}
DDNS_ENABLED=${ddns_enabled}
EOF
}

config_manifest_json() {
  local mode="$1" contains_secret="$2" export_time="$3" role="$4" entries_count="$5" forwards_count="$6" pbr_count="$7" ddns_enabled="$8" hostname
  hostname="$(hostname 2>/dev/null || printf 'unknown')"
  cat <<EOF
{
  "format": 1,
  "export_time": "$(json_escape "$export_time")",
  "export_version": "$(json_escape "$TOOL_VERSION")",
  "export_hostname": "$(json_escape "$hostname")",
  "export_role": "$(json_escape "$role")",
  "export_mode": "$(json_escape "$mode")",
  "contains_secret": ${contains_secret},
  "entries_count": ${entries_count},
  "forwards_count": ${forwards_count},
  "pbr_count": ${pbr_count},
  "ddns_enabled": ${ddns_enabled}
}
EOF
}

config_export() {
  need_root_unless_dry_run
  ensure_tsv_files
  local mode="full" explicit_full=0 arg config_lock="" ts package_name dest tmp stage state_work checksums_tmp
  local export_time role entries_count forwards_count pbr_count ddns_enabled contains_secret base_name sha_file
  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --redacted) mode="redacted"; shift ;;
      --full) mode="full"; explicit_full=1; shift ;;
      *) fail "未知 config export 参数：${arg}"; return 1 ;;
    esac
  done
  if ! lock_acquire "$CONFIG_LOCK_PATH" "配置导入/导出" config_lock; then
    warn "已有 Leikwan 任务运行中，请稍后再试。"
    return 1
  fi
  if [[ "$mode" == "full" ]]; then
    warn "完整配置包包含 EasyTier network secret。"
    warn "泄露后可能导致别人加入你的 EasyTier 网络。"
    if (( explicit_full == 1 )) && is_interactive; then
      prompt_yes_no "确认继续导出完整配置包？" "N" || { lock_release "$config_lock"; return 0; }
    fi
    contains_secret=true
    base_name="leikwan-config"
  else
    contains_secret=false
    base_name="leikwan-config-redacted"
  fi
  ts="$(snapshot_timestamp)"
  package_name="${base_name}-${ts}"
  dest="/root/${package_name}.tar.gz"
  sha_file="${dest}.sha256"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] export ${mode} config package ${dest}"
    lock_release "$config_lock"
    return 0
  fi
  tmp="$(mktemp -d /tmp/leikwan-config-export.XXXXXX)"
  stage="${tmp}/${package_name}"
  state_work="${tmp}/state-work"
  mkdir -p "$stage/state" "$stage/systemd" "$stage/nft" "$stage/iproute" "$stage/sysctl" "$stage/status" "$stage/outputs" "$stage/logs" "$state_work"
  export_time="$(config_export_time)"
  role="$(detect_role)"
  entries_count="$(entries_rows | awk 'END{print NR+0}')"
  forwards_count="$(forwards_rows | awk 'END{print NR+0}')"
  pbr_count="$(pbr_rules_count 2>/dev/null || printf '0')"
  if [[ "$(ddns_timer_state 2>/dev/null || true)" == "active" ]]; then ddns_enabled=true; else ddns_enabled=false; fi
  config_manifest_env "$mode" "$contains_secret" "$export_time" "$role" "$entries_count" "$forwards_count" "$pbr_count" "$ddns_enabled" >"${stage}/manifest.env"
  config_manifest_json "$mode" "$contains_secret" "$export_time" "$role" "$entries_count" "$forwards_count" "$pbr_count" "$ddns_enabled" >"${stage}/manifest.json"
  if [[ -d "$STATE_DIR" ]]; then
    tar --exclude='etc/leikwan-toolkit/snapshots' -C / -cf - etc/leikwan-toolkit 2>/dev/null | tar -C "$state_work" -xf - 2>/dev/null || true
  else
    mkdir -p "${state_work}${STATE_DIR}"
  fi
  if [[ "$mode" == "redacted" ]]; then
    config_sensitive_redact_tree "$state_work"
  fi
  tar -czf "${stage}/state/etc-leikwan-toolkit.tar.gz" -C "$state_work" etc/leikwan-toolkit 2>/dev/null || tar -czf "${stage}/state/etc-leikwan-toolkit.tar.gz" -C "$state_work" . 2>/dev/null
  config_export_copy_path "$EASYTIER_RELAY_SERVICE" "${stage}/systemd"
  while IFS= read -r svc; do config_export_copy_path "$svc" "${stage}/systemd"; done < <(find /etc/systemd/system -maxdepth 1 -type f -name 'easytier-entry-*.service' 2>/dev/null || true)
  config_export_copy_path "$NFT_SERVICE" "${stage}/systemd"
  config_export_copy_path "$DDNS_SERVICE" "${stage}/systemd"
  config_export_copy_path "$DDNS_TIMER" "${stage}/systemd"
  command -v nft >/dev/null 2>&1 && nft list ruleset >"${stage}/nft/ruleset.nft" 2>&1 || echo "nft command not found" >"${stage}/nft/ruleset.nft"
  config_export_copy_path "$NFT_RULE_FILE" "${stage}/nft"
  config_export_copy_path "$PBR_RT_TABLES" "${stage}/iproute"
  command -v ip >/dev/null 2>&1 && ip rule show >"${stage}/iproute/ip_rule_show.txt" 2>&1 || echo "ip command not found" >"${stage}/iproute/ip_rule_show.txt"
  command -v ip >/dev/null 2>&1 && ip route show table all >"${stage}/iproute/ip_route_show_table_all.txt" 2>&1 || echo "ip command not found" >"${stage}/iproute/ip_route_show_table_all.txt"
  config_export_copy_path "$FORWARD_SYSCTL" "${stage}/sysctl"
  config_export_copy_path "$BBR_SYSCTL_CONF" "${stage}/sysctl"
  (LOG_DISABLED=1 status_overview >"${stage}/status/lq-status.txt" 2>&1) || true
  (LOG_DISABLED=1 doctor >"${stage}/status/lq-doctor.txt" 2>&1) || true
  generate_forward_outputs 1 >/dev/null 2>&1 || true
  for file in "$FORWARD_TXT" "$FORWARD_TSV" "$FORWARD_JSON" "$FORWARD_HTML"; do
    config_export_copy_path "$file" "${stage}/outputs"
  done
  [[ -f "$LOG_FILE" ]] && tail -n 200 "$LOG_FILE" >"${stage}/logs/leikwan-toolkit.tail.log" 2>/dev/null || true
  [[ -f "$DDNS_LOG_FILE" ]] && tail -n 200 "$DDNS_LOG_FILE" >"${stage}/logs/leikwan-ddns-refresh.tail.log" 2>/dev/null || true
  if [[ "$mode" == "redacted" ]]; then
    config_sensitive_redact_tree "$stage"
  fi
  checksums_tmp="${tmp}/checksums.sha256"
  (cd "$stage" && find . -type f ! -name checksums.sha256 -print | sort | while IFS= read -r file; do sha256sum "$file"; done >"$checksums_tmp")
  mv "$checksums_tmp" "${stage}/checksums.sha256"
  tar -czf "$dest" -C "$tmp" "$package_name"
  (cd "$(dirname "$dest")" && sha256sum "$(basename "$dest")" >"$(basename "$sha_file")")
  rm -rf "$tmp"
  ok "已导出配置包：${dest}"
  ok "sha256：${sha_file}"
  if [[ "$mode" == "full" ]]; then
    warn "完整配置包包含 EasyTier network secret，请妥善保存。"
  else
    info "脱敏配置包适合排错和 issue 附件，不适合完整恢复运行。"
  fi
  write_config_export_status "ok" "$mode" "$dest"
  lock_release "$config_lock"
}

config_verify_external_sha() {
  local pkg="$1" required="${2:-0}" sha
  sha="${pkg}.sha256"
  if [[ ! -f "$sha" ]]; then
    if (( required == 1 )); then
      fail "未找到外部 sha256 文件：${sha}"
      return 1
    fi
    warn "未找到外部 sha256 文件：${sha}"
    return 0
  fi
  (cd "$(dirname "$pkg")" && sha256sum -c "$(basename "$sha")" >/dev/null)
}

config_extract_package() {
  local pkg="$1" out_tmp="$2" out_root="$3" tmp root
  tmp="$(mktemp -d /tmp/leikwan-config-inspect.XXXXXX)"
  tar -xzf "$pkg" -C "$tmp"
  root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$root" && -f "${root}/manifest.env" ]] || { rm -rf "$tmp"; fail "配置包 manifest.env 缺失。"; return 1; }
  printf -v "$out_tmp" '%s' "$tmp"
  printf -v "$out_root" '%s' "$root"
}

config_verify_internal_checksums() {
  local root="$1"
  [[ -f "${root}/checksums.sha256" ]] || { warn "配置包缺少 checksums.sha256。"; return 1; }
  (cd "$root" && sha256sum -c checksums.sha256 >/dev/null)
}

config_inspect_root() {
  local root="$1" manifest
  local export_time export_version export_role export_mode contains_secret entries_count forwards_count pbr_count ddns_enabled
  manifest="${root}/manifest.env"
  export_time="$(env_file_get "$manifest" EXPORT_TIME)"
  export_version="$(env_file_get "$manifest" EXPORT_VERSION)"
  export_role="$(env_file_get "$manifest" EXPORT_ROLE)"
  export_mode="$(env_file_get "$manifest" EXPORT_MODE)"
  contains_secret="$(env_file_get "$manifest" CONTAINS_SECRET)"
  entries_count="$(env_file_get "$manifest" ENTRIES_COUNT)"
  forwards_count="$(env_file_get "$manifest" FORWARDS_COUNT)"
  pbr_count="$(env_file_get "$manifest" PBR_COUNT)"
  ddns_enabled="$(env_file_get "$manifest" DDNS_ENABLED)"
  echo "配置包信息"
  echo "----------------------------------------"
  echo "导出时间: ${export_time:-unknown}"
  echo "导出版本: ${export_version:-unknown}"
  echo "角色: ${export_role:-unknown}"
  echo "模式: ${export_mode:-unknown}"
  echo "包含 secret: ${contains_secret:-unknown}"
  echo "entries 数量: ${entries_count:-0}"
  echo "forwards 数量: ${forwards_count:-0}"
  echo "PBR 数量: ${pbr_count:-0}"
  echo "DDNS 启用: ${ddns_enabled:-unknown}"
  echo "包含 systemd: $([[ -d "${root}/systemd" ]] && find "${root}/systemd" -type f | grep -q . && echo yes || echo no)"
  echo "包含 nft: $([[ -s "${root}/nft/ruleset.nft" || -s "${root}/nft/leikwan-forward.nft" ]] && echo yes || echo no)"
  echo "包含 ip rule 快照: $([[ -s "${root}/iproute/ip_rule_show.txt" ]] && echo yes || echo no)"
}

config_inspect() {
  local pkg="$1" tmp="" root=""
  [[ -n "$pkg" ]] || { fail "请提供配置包路径。"; return 1; }
  [[ -f "$pkg" ]] || { fail "配置包不存在：${pkg}"; return 1; }
  if config_verify_external_sha "$pkg"; then
    ok "外部 sha256 校验通过。"
  else
    fail "外部 sha256 校验失败：${pkg}.sha256"
    return 1
  fi
  config_extract_package "$pkg" tmp root || return 1
  if config_verify_internal_checksums "$root"; then
    ok "内部 checksums.sha256 校验通过。"
  else
    fail "内部 checksums.sha256 校验失败。"
    rm -rf "$tmp"
    return 1
  fi
  config_inspect_root "$root"
  rm -rf "$tmp"
}

config_import_auto_snapshot_or_confirm() {
  local dest
  dest="${AUTO_SNAPSHOT_DIR}/auto-before-config-import-$(snapshot_timestamp).tar.gz"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] create auto snapshot ${dest}"
    return 0
  fi
  ensure_base_dirs
  if create_snapshot_archive "$dest"; then
    ok "已创建自动快照：${dest}"
    prune_auto_snapshots
    return 0
  fi
  warn "自动快照失败，导入风险较高。"
  prompt_yes_no "是否继续？" "N"
}

config_restore_full_assets() {
  local root="$1" svc
  mkdir -p /etc/systemd/system "$(dirname "$NFT_RULE_FILE")" "$(dirname "$FORWARD_SYSCTL")" "$(dirname "$BBR_SYSCTL_CONF")" "$(dirname "$PBR_RT_TABLES")"
  for svc in easytier-relay.service leikwan-nft-forward.service leikwan-ddns-refresh.service leikwan-ddns-refresh.timer; do
    [[ -f "${root}/systemd/${svc}" ]] && cp -a "${root}/systemd/${svc}" "/etc/systemd/system/${svc}"
  done
  while IFS= read -r svc; do
    cp -a "$svc" "/etc/systemd/system/$(basename "$svc")"
  done < <(find "${root}/systemd" -maxdepth 1 -type f -name 'easytier-entry-*.service' 2>/dev/null || true)
  [[ -f "${root}/nft/leikwan-forward.nft" ]] && cp -a "${root}/nft/leikwan-forward.nft" "$NFT_RULE_FILE"
  [[ -f "${root}/sysctl/99-leikwan-forward.conf" ]] && cp -a "${root}/sysctl/99-leikwan-forward.conf" "$FORWARD_SYSCTL"
  [[ -f "${root}/sysctl/99-leikwan-bbr.conf" ]] && cp -a "${root}/sysctl/99-leikwan-bbr.conf" "$BBR_SYSCTL_CONF"
  [[ -f "${root}/iproute/rt_tables" ]] && cp -a "${root}/iproute/rt_tables" "$PBR_RT_TABLES"
  command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
  command -v sysctl >/dev/null 2>&1 && sysctl --system >/dev/null 2>&1 || true
}

config_apply_after_import() {
  local mode="$1" assume_yes="$2" role
  [[ "$mode" == "apply" || "$mode" == "full" ]] || return 0
  warn "应用导入配置可能重新渲染 systemd、nftables、PBR，并重启 EasyTier 服务。"
  if is_interactive && (( assume_yes == 0 )); then
    prompt_yes_no "是否继续应用导入配置？" "N" || return 0
  fi
  role="$(detect_role)"
  case "$role" in
    leikwan-relay)
      apply_easytier_relay_service confirmed || warn "relay service 重渲染/重启未完成。"
      apply_nft_rules "leikwan-relay" 1 || warn "relay nftables 应用未完成。"
      ;;
    cloud-entry)
      apply_easytier_entry_services || warn "entry service 重渲染/重启未完成。"
      apply_nft_rules "cloud-entry" || warn "entry nftables 应用未完成。"
      ;;
    *)
      warn "无法识别角色，跳过 EasyTier/nftables 自动应用。"
      ;;
  esac
  pbr_apply || warn "PBR 应用未完成。"
}

config_import() {
  need_root_unless_dry_run
  local pkg="${1:-}" mode="" assume_yes=0 arg config_lock="" tmp="" root="" manifest contains_secret import_mode
  [[ -n "$pkg" ]] || { fail "请提供配置包路径。"; return 1; }
  shift || true
  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --mode) mode="${2:-}"; shift 2 ;;
      --yes|-y) assume_yes=1; shift ;;
      *) fail "未知 config import 参数：${arg}"; return 1 ;;
    esac
  done
  [[ -f "$pkg" ]] || { fail "配置包不存在：${pkg}"; return 1; }
  case "$mode" in
    ""|config-only|apply|full) ;;
    *) fail "导入模式无效：${mode}"; return 1 ;;
  esac
  if [[ "$mode" == "full" && "$assume_yes" != "1" ]] && ! is_interactive; then
    fail "非交互 full import 必须显式添加 --yes。"
    return 1
  fi
  if ! lock_acquire "$CONFIG_LOCK_PATH" "配置导入/导出" config_lock; then
    warn "已有 Leikwan 任务运行中，请稍后再试。"
    return 1
  fi
  if ! global_lock_acquire; then
    warn "已有 Leikwan 任务运行中，请稍后再试。"
    lock_release "$config_lock"
    return 1
  fi
  config_verify_external_sha "$pkg" 1 || { global_lock_release; lock_release "$config_lock"; return 1; }
  config_extract_package "$pkg" tmp root || { global_lock_release; lock_release "$config_lock"; return 1; }
  config_verify_internal_checksums "$root" || { rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 1; }
  manifest="${root}/manifest.env"
  [[ "$(env_file_get "$manifest" LEIKWAN_CONFIG_FORMAT)" == "1" ]] || { fail "配置包格式不支持。"; rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 1; }
  config_inspect_root "$root"
  contains_secret="$(env_file_get "$manifest" CONTAINS_SECRET)"
  if [[ "$contains_secret" != "true" ]]; then
    warn "这是脱敏配置包，不能恢复 EasyTier network secret。"
    info "仅适合排错查看，不适合直接恢复运行。"
    if [[ "$mode" == "full" ]]; then
      fail "脱敏配置包不能使用 full 模式导入。"
      rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 1
    fi
  fi
  if [[ -z "$mode" ]]; then
    if is_interactive; then
      echo
      echo "选择导入模式："
      echo "1. 仅导入 /etc/leikwan-toolkit 配置"
      echo "2. 导入配置并重新渲染 systemd / nftables / PBR"
      echo "3. 完整迁移恢复，包括 systemd service、nftables、PBR、sysctl"
      echo "0. 返回"
      case "$(prompt_menu_choice "请选择：")" in
        1) mode="config-only" ;;
        2) mode="apply" ;;
        3) mode="full" ;;
        0|"") rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 0 ;;
        *) warn "无效选择。"; rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 0 ;;
      esac
    else
      mode="config-only"
    fi
  fi
  echo "[WARN] 即将导入配置包，可能覆盖当前 /etc/leikwan-toolkit。"
  echo "[WARN] 当前服务不会立即重启，除非你选择应用配置。"
  if is_interactive && (( assume_yes == 0 )); then
    prompt_yes_no "确认继续？" "N" || { rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 0; }
  fi
  config_import_auto_snapshot_or_confirm || { rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 1; }
  import_mode="$mode"
  if [[ -f "${root}/state/etc-leikwan-toolkit.tar.gz" ]]; then
    tar -xzf "${root}/state/etc-leikwan-toolkit.tar.gz" -C /
  else
    fail "配置包缺少 state/etc-leikwan-toolkit.tar.gz。"
    rm -rf "$tmp"; global_lock_release; lock_release "$config_lock"; return 1
  fi
  if [[ "$mode" == "full" ]]; then
    config_restore_full_assets "$root"
  fi
  config_apply_after_import "$mode" "$assume_yes"
  ok "配置导入完成：${pkg}"
  info "建议下一步执行：lq status"
  info "建议下一步执行：lq --doctor"
  info "如需重应用转发规则：lq forward apply-relay --auto-fix-route"
  write_config_import_status "ok" "$import_mode" "$pkg"
  rm -rf "$tmp"
  global_lock_release
  lock_release "$config_lock"
}

config_list() {
  local files=() file size i=0
  mapfile -t files < <(find /root -maxdepth 1 -type f \( -name 'leikwan-config-*.tar.gz' -o -name 'leikwan-config-redacted-*.tar.gz' \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{sub(/^[^ ]+ /, ""); print}')
  if (( ${#files[@]} == 0 )); then
    warn "未找到已导出的配置包。"
    return 0
  fi
  echo "已导出的配置包"
  echo "----------------------------------------"
  for file in "${files[@]}"; do
    i=$((i + 1))
    size="$(du -h "$file" 2>/dev/null | awk '{print $1}')"
    printf '%d. %s (%s)\n' "$i" "$file" "${size:-unknown}"
  done
}

config_menu() {
  local choice pkg
  while true; do
    print_menu_header "配置导入 / 导出"
    echo "1. 导出完整配置包"
    echo "2. 导出脱敏配置包"
    echo "3. 查看配置包信息"
    echo "4. 导入配置包"
    echo "5. 查看已导出的配置包"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause config_export --full ;;
      2) run_menu_action_pause config_export --redacted ;;
      3) pkg="$(prompt_value "配置包路径")"; [[ -n "$pkg" ]] && run_menu_action_pause config_inspect "$pkg" ;;
      4) pkg="$(prompt_value "配置包路径")"; [[ -n "$pkg" ]] && run_menu_action_pause config_import "$pkg" ;;
      5) run_menu_action_pause config_list ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

report() {
  local status="$1" msg="$2"
  case "$status" in
    WARN) REPORT_WARN_COUNT=$((REPORT_WARN_COUNT + 1)) ;;
    FAIL) REPORT_FAIL_COUNT=$((REPORT_FAIL_COUNT + 1)) ;;
  esac
  case "$status" in
    OK) echo "${GREEN}[OK]${RESET} ${msg}" ;;
    WARN) echo "${YELLOW}[WARN]${RESET} ${msg}" ;;
    FAIL) echo "${RED}[FAIL]${RESET} ${msg}" ;;
    HINT) echo "[HINT] ${msg}" ;;
    INFO|DEBUG) echo "[${status}] ${msg}" ;;
  esac
}

ping_avg_ms() {
  awk -F= '/rtt|round-trip/ {
    split($2, a, "/")
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[2])
    print a[2]
    exit
  }'
}

ping_loss_text() {
  awk -F, '/packet loss/ {
    for (i=1; i<=NF; i++) {
      if ($i ~ /packet loss/) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
        print $i
        exit
      }
    }
  }'
}

ping_loss_percent() {
  awk -F, '/packet loss/ {
    for (i=1; i<=NF; i++) {
      if ($i ~ /packet loss/) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
        sub(/[[:space:]]*packet loss.*/, "", $i)
        print $i
        exit
      }
    }
  }'
}

emit_status() {
  local mode="$1" status="$2" msg="$3"
  if [[ "$mode" == "report" ]]; then
    report "$status" "$msg"
  else
    case "$status" in
      OK) ok "$msg" ;;
      WARN) warn "$msg" ;;
      INFO) info "$msg" ;;
      FAIL) fail "$msg" ;;
      *) echo "[${status}] ${msg}" ;;
    esac
  fi
}

ping_entry_et_ip() {
  local name="$1" et_ip="$2" mode="${3:-plain}" output rc avg loss msg
  rc=0
  output="$(ping -c 2 -W 2 "$et_ip" 2>&1)" || rc=$?
  log "PING ${name} ${et_ip}: $(printf '%s' "$output" | tr '\n' ' ')"
  avg="$(printf '%s\n' "$output" | ping_avg_ms)"
  loss="$(printf '%s\n' "$output" | ping_loss_percent)"
  if (( rc == 0 )); then
    msg="ping ${name} ${et_ip} 成功${avg:+，RTT avg=${avg}ms}"
    emit_status "$mode" OK "$msg"
    return 0
  fi
  msg="ping ${name} ${et_ip} 失败，packet loss=${loss:-unknown}"
  emit_status "$mode" WARN "$msg"
  return 1
}

report_ping_quality() {
  local host="$1" label="$2" output rc avg loss
  rc=0
  output="$(ping -c 4 "$host" 2>&1)" || rc=$?
  avg="$(printf '%s\n' "$output" | ping_avg_ms)"
  loss="$(printf '%s\n' "$output" | ping_loss_text)"
  if (( rc != 0 )); then
    report WARN "${label} 失败：${loss:-无 RTT}。请检查 EasyTier peer、路由和端口白名单。"
    return 1
  fi
  if [[ -n "$avg" ]] && awk -v a="$avg" 'BEGIN{exit !(a > 1000)}'; then
    report FAIL "${label} RTT avg=${avg}ms，严重异常；优先确认 EasyTier 端口是否走 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END} 白名单。"
  elif [[ -n "$avg" ]] && awk -v a="$avg" 'BEGIN{exit !(a > 200)}'; then
    report WARN "${label} RTT avg=${avg}ms 偏高；建议检查 EasyTier 端口是否走 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END} 白名单。"
  else
    report OK "${label} 成功${avg:+，RTT avg=${avg}ms}"
  fi
}

report_mss_clamp_status() {
  local mss
  mss="$(tcp_mss_clamp_value)"
  if nft_has_mss_clamp; then
    report OK "TCP MSS clamp enabled: ${mss}"
  else
    report WARN "TCP MSS clamp 未启用，EasyTier/tun TCP 转发可能出现有延迟但连接异常"
  fi
}

report_entry_policy_summary() {
  local count rank label name public_host et_ip proto port weight enabled
  count="$(enabled_entries_count)"
  report INFO "公网入口策略："
  report INFO "enabled entries: ${count}"
  if (( count == 0 )); then
    report WARN "当前没有 enabled 公网入口，relay peer 列表为空。"
    return 0
  fi
  rank=0
  while IFS=$'\t' read -r name public_host et_ip proto port weight enabled; do
    rank=$((rank + 1))
    if (( rank == 1 )); then label="PRIMARY"; else label="BACKUP"; fi
    report INFO "${label}: ${name} weight=${weight} $(easytier_protocols_display "$proto")/${port}"
  done < <(enabled_entries_sorted)
  if (( count == 1 )); then
    name="$(enabled_entries_sorted | awk -F'\t' 'NR==1 {print $1}')"
    report OK "当前为单入口模式：${name}"
  else
    report INFO "当前为多入口模式，权重只影响输出排序，不代表自动流量负载均衡。"
  fi
}

doctor_recheck_relay_dnat_rules() {
  local name entry_port target_host target_ip target_port out_iface route_table enabled _last_resolved_at comment
  local dnat_missing=0 forwards
  forwards="$(enabled_forwards_count 2>/dev/null || printf '0')"
  if (( forwards == 0 )); then
    report INFO "当前没有 enabled 转发目标，跳过 DNAT 复查。"
    return 0
  fi
  if ! nft_has_dnat_rules; then
    report WARN "nftables DNAT 规则复查：仍未发现 DNAT"
    return 1
  fi
  resolve_forwards >/dev/null 2>&1 || { report WARN "resolved.tsv 复查失败，无法逐条确认 DNAT。"; return 1; }
  while IFS=$'\034' read -r name entry_port target_host target_ip target_port out_iface route_table enabled _last_resolved_at comment; do
    [[ "$enabled" == "true" && -n "$target_ip" ]] || continue
    if ! nft_has_relay_dnat tcp "$entry_port" "$target_ip" "$target_port"; then
      report WARN "${name} relay TCP DNAT 复查仍缺失"
      dnat_missing=1
    fi
    if ! nft_has_relay_dnat udp "$entry_port" "$target_ip" "$target_port"; then
      report WARN "${name} relay UDP DNAT 复查仍缺失"
      dnat_missing=1
    fi
  done < <(resolved_rows_usv)
  return "$dnat_missing"
}

doctor_offer_forward_rule_fix() {
  local fix_needed="$1"
  local reason="${2:-legacy}"
  (( fix_needed == 1 )) || return 0
  case "$reason" in
    empty)
      report WARN "nftables 表存在，但没有任何转发 DNAT 规则。"
      report INFO "检测到转发规则可能尚未应用，请执行：lq forward apply-relay --auto-fix-route"
      ;;
    partial)
      report WARN "检测到部分转发 DNAT 规则缺失，当前 nftables 规则可能不是最新模板。"
      report INFO "请执行：lq forward apply-relay --auto-fix-route"
      ;;
    mss)
      report INFO "检测到 TCP MSS clamp 未启用，可能是旧版本 nftables 模板或规则未重新应用。"
      report INFO "请执行：lq forward apply-relay --auto-fix-route"
      ;;
    *)
      report INFO "检测到转发规则可能是旧版本模板，请执行：lq forward apply-relay --auto-fix-route"
      ;;
  esac
  is_interactive || return 0
  (( DOCTOR_INTERACTIVE_FIX == 1 )) || return 0
  if prompt_yes_no "是否立即重新应用转发规则并同步 route_table？" "Y"; then
    report INFO "正在重新应用转发规则并同步 route_table..."
    if apply_nft_rules "leikwan-relay" 1; then
      report OK "已重新应用转发规则并同步 route_table。"
      if mss_clamp_enabled; then
        report_mss_clamp_status
      fi
      if doctor_recheck_relay_dnat_rules && { ! mss_clamp_enabled || nft_has_mss_clamp; }; then
        report OK "转发规则复查通过。"
      else
        report WARN "转发规则已重新应用，但仍存在缺失，请查看上方明细。"
      fi
    elif [[ "$APPLY_NFT_LAST_STATUS" == "skipped" ]]; then
      report INFO "已取消前台执行。可使用 nohup 后台方式安全应用。"
    else
      report WARN "转发规则重新应用失败，请稍后执行：lq forward apply-relay --auto-fix-route"
    fi
  else
    report INFO "已跳过自动修复。可稍后执行：lq forward apply-relay --auto-fix-route"
  fi
}

doctor_cloud() {
  report OK "角色：cloud-entry"
  local entry_ip proto port iface service_name relay_ip start end
  local _public_host _et_ip _proto _port _weight
  entry_ip="$(current_entry_et_ip)"
  if [[ -x "$EASYTIER_CORE_BIN" && -x "$EASYTIER_CLI_BIN" ]]; then
    report OK "EasyTier binary 存在"
    report INFO "easytier-core: ${EASYTIER_CORE_BIN}"
    report INFO "easytier-cli: ${EASYTIER_CLI_BIN}"
  else
    report WARN "EasyTier binary 不存在，请先安装 EasyTier"
  fi
  while IFS=$'\t' read -r name _public_host _et_ip _proto _port _weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    service_name="$(entry_service_name "$name")"
    if systemctl is-active --quiet "${service_name}.service"; then report OK "${service_name} active"; else report WARN "${service_name} 未运行"; fi
  done < <(entries_rows)
  iface="$(et_iface_by_ip "$entry_ip")"
  if [[ -n "$iface" ]]; then report OK "EasyTier IP ${entry_ip} 在接口 ${iface}"; else report WARN "未检测到 EasyTier IP：${entry_ip}"; fi
  if [[ -f "$ENTRY_PAIRING_FILE" ]]; then
    proto="$(easytier_protocols_from_env "$ENTRY_PAIRING_FILE" EASYTIER_PROTOCOLS EASYTIER_PROTOCOL "$EASYTIER_PROTOCOLS_DEFAULT" 2>/dev/null || printf '%s' "$EASYTIER_PROTOCOLS_DEFAULT")"
    port="$(easytier_port_from_env "$ENTRY_PAIRING_FILE" "$proto" EASYTIER_TCP_PORT EASYTIER_UDP_PORT EASYTIER_PORT 2>/dev/null || true)"
  else
    proto="$(easytier_protocols_from_env "$NETWORK_ENV" EASYTIER_PROTOCOLS EASYTIER_PROTOCOL "$EASYTIER_PROTOCOLS_DEFAULT" 2>/dev/null || printf '%s' "$EASYTIER_PROTOCOLS_DEFAULT")"
    port=""
  fi
  [[ -n "$port" ]] || port="$(easytier_port_from_env "$NETWORK_ENV" "$proto" EASYTIER_TCP_PORT EASYTIER_UDP_PORT EASYTIER_LISTEN_PORT 2>/dev/null || printf '%s' "$EASYTIER_PORT_DEFAULT")"
  if is_fast_port "$port"; then report OK "EasyTier 监听端口：$(easytier_protocols_display "$proto")/${port}，位于白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}"; else report WARN "EasyTier 监听端口：$(easytier_protocols_display "$proto")/${port}，不在白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}"; fi
  if easytier_protocols_has "$proto" tcp; then
    if ss -lntH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}'; then report OK "EasyTier TCP ${port} 已监听"; else report WARN "EasyTier TCP ${port} 未监听"; fi
  fi
  if easytier_protocols_has "$proto" udp; then
    if ss -lunH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}'; then report OK "EasyTier UDP ${port} 已监听"; else report WARN "EasyTier UDP ${port} 未监听"; fi
  fi
  ping_entry_et_ip "relay" "$RELAY_ET_IP" report || true
  if nft list table inet leikwan_forward >/dev/null 2>&1; then
    report OK "nftables table inet leikwan_forward 存在"
    if nft_has_dnat_rules; then report OK "nftables DNAT 规则存在"; else report WARN "nftables 表存在，但没有任何 DNAT 规则。"; fi
    report_mss_clamp_status
  else
    report WARN "nftables 项目表不存在"
  fi
  report_local_entry_ddns_status
  if [[ -f "$ENTRY_EXPOSE_ENV" ]]; then
    start="$(entry_expose_start)"
    end="$(entry_expose_end)"
    relay_ip="$(entry_expose_relay_ip)"
    report OK "入口端口池：${start}-${end} -> ${relay_ip}"
    if nft_has_cloud_dnat tcp "$relay_ip" "${start}-${end}"; then
      report OK "入口端口池 TCP DNAT 正常"
    else
      report FAIL "入口端口池 TCP DNAT 缺失：应为 tcp dport ${start}-${end} dnat ip to ${relay_ip}"
    fi
    if nft_has_cloud_dnat udp "$relay_ip" "${start}-${end}"; then
      report OK "入口端口池 UDP DNAT 正常"
    else
      report FAIL "入口端口池 UDP DNAT 缺失：应为 udp dport ${start}-${end} dnat ip to ${relay_ip}"
    fi
  else
    report WARN "公网入口端口池未配置，请执行 lq entry expose-range"
  fi
  [[ -f "$ENTRY_PAIRING_FILE" ]] && report OK "入口配对码：已生成"
}

doctor_relay() {
  report OK "角色：leikwan-relay"
  local iface entries forwards name public_host et_ip proto port _weight enabled target_ip target_port
  local entry_port target_host out_iface route_table comment
  local forward_rule_fix_needed=0
  local forward_rule_fix_reason=""
  local nft_table_exists=0 table_has_any_dnat=0 relay_tcp_missing=0 relay_udp_missing=0
  forwards=0
  if [[ -x "$EASYTIER_CORE_BIN" && -x "$EASYTIER_CLI_BIN" ]]; then
    report OK "EasyTier binary 存在"
    report INFO "easytier-core: ${EASYTIER_CORE_BIN}"
    report INFO "easytier-cli: ${EASYTIER_CLI_BIN}"
  else
    report WARN "EasyTier binary 不存在，请先安装 EasyTier"
  fi
  if systemctl is-active --quiet "${EASYTIER_RELAY_SERVICE_NAME}.service"; then report OK "easytier-relay.service active"; else report WARN "easytier-relay.service 未运行"; fi
  iface="$(et_iface_by_ip "$RELAY_ET_IP")"
  if [[ -n "$iface" ]]; then report OK "Relay EasyTier IP ${RELAY_ET_IP} 在接口 ${iface}"; else report WARN "未检测到 Relay EasyTier IP：${RELAY_ET_IP}"; fi
  entries="$(entries_rows | awk -F'\t' '$7=="true"{c++} END{print c+0}')"; report INFO "enabled entries：${entries}"
  report_entry_policy_summary
  while IFS=$'\t' read -r name public_host et_ip proto port _weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    emit_entry_peer_targets "$name" "$public_host" "$proto" "$port" report
    check_entry_peer_connectivity "$name" "$public_host" "$et_ip" "$proto" "$port" report || true
    if is_fast_port "$port"; then report OK "入口 ${name} EasyTier 端口 ${port} 位于白名单"; else report WARN "入口 ${name} EasyTier 端口 ${port} 不在白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}"; fi
    if easytier_protocols_has "$proto" tcp; then
      case "$(tcp_reachable_status "$public_host" "$port")" in
        0) report OK "入口 ${name} TCP 可达：${public_host}:${port}" ;;
        2) report WARN "未找到 nc，无法测试入口 ${name} TCP；请安装 netcat-openbsd" ;;
        *) report WARN "入口 ${name} TCP 不可达：${public_host}:${port}" ;;
      esac
    fi
    if easytier_protocols_has "$proto" udp; then
      case "$(udp_probe_status "$public_host" "$port")" in
        0) report OK "入口 ${name} UDP 探测完成：${public_host}:${port}" ;;
        2) report WARN "未找到 nc，无法测试入口 ${name} UDP；请安装 netcat-openbsd" ;;
        *) report WARN "入口 ${name} UDP 探测未确认。UDP 无连接探测可能不可靠，请结合 EasyTier peer / ping 判断。" ;;
      esac
    fi
  done < <(entries_rows)
  if sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -qx 1; then report OK "net.ipv4.ip_forward=1"; else report WARN "net.ipv4.ip_forward 未启用"; fi
  if nft list table inet leikwan_forward >/dev/null 2>&1; then
    nft_table_exists=1
    report OK "nftables table inet leikwan_forward 存在"
    if nft_has_dnat_rules; then table_has_any_dnat=1; report OK "nftables DNAT 规则存在"; fi
    report_mss_clamp_status
    if mss_clamp_enabled && ! nft_has_mss_clamp; then
      forward_rule_fix_needed=1
      forward_rule_fix_reason="mss"
    fi
  else
    report WARN "nftables 项目表不存在"
  fi
  if forwards="$(enabled_forwards_count 2>/dev/null)"; then
    report INFO "enabled forwards：${forwards}"
    if (( forwards == 0 )); then
      report INFO "当前没有 enabled 转发目标。"
    fi
  else
    report FAIL "forwards.tsv 校验失败，请检查 TAB 分隔和字段数。"
  fi
  if resolve_forwards >/dev/null 2>&1; then
    while IFS=$'\034' read -r name entry_port target_host target_ip target_port out_iface route_table enabled _last_resolved_at comment; do
      [[ "$enabled" == "true" ]] || continue
      if port_in_range "$entry_port" "$FORWARD_ENTRY_PORT_FALLBACK_START" "$FORWARD_ENTRY_PORT_FALLBACK_END"; then
        report OK "${name} entry_port ${entry_port} 位于常见入口端口池 ${FORWARD_ENTRY_PORT_FALLBACK_START}-${FORWARD_ENTRY_PORT_FALLBACK_END}"
      else
        report WARN "${name} entry_port ${entry_port} 不在常见入口端口池 ${FORWARD_ENTRY_PORT_FALLBACK_START}-${FORWARD_ENTRY_PORT_FALLBACK_END}"
      fi
      if [[ -n "$target_ip" ]]; then
        report OK "${name} resolved -> ${target_ip}"
      else
        report WARN "${name} target 未解析"
      fi
      if [[ -n "$target_ip" ]]; then
        report_forward_route_consistency "$name" "$target_host" "$out_iface" "$route_table"
        case "$(tcp_reachable_status "$target_ip" "$target_port")" in
          0) report OK "${name} target TCP 可达" ;;
          2) report WARN "未找到 nc，无法测试 ${name} target TCP；请安装 netcat-openbsd" ;;
          *) report WARN "${name} target TCP 不可达" ;;
        esac
        case "$(udp_probe_status "$target_ip" "$target_port")" in
          0) report OK "${name} target UDP 探测完成" ;;
          2) report WARN "未找到 nc，无法测试 ${name} target UDP；请安装 netcat-openbsd" ;;
          *) report WARN "${name} target UDP 探测未确认。UDP 无连接探测可能不可靠，请结合业务实际测试。" ;;
        esac
      fi
      if [[ -n "$target_ip" ]]; then
        if nft_has_relay_dnat tcp "$entry_port" "$target_ip" "$target_port"; then
          report OK "${name} relay TCP DNAT 正常"
        else
          report FAIL "${name} relay TCP DNAT 缺失：应为 tcp dport ${entry_port} dnat ip to ${target_ip}:${target_port}"
          forward_rule_fix_needed=1
          relay_tcp_missing=1
        fi
        if nft_has_relay_dnat udp "$entry_port" "$target_ip" "$target_port"; then
          report OK "${name} relay UDP DNAT 正常"
        else
          report WARN "${name} relay UDP DNAT 缺失：应为 udp dport ${entry_port} dnat ip to ${target_ip}:${target_port}"
          forward_rule_fix_needed=1
          relay_udp_missing=1
        fi
      fi
    done < <(resolved_rows_usv)
  else
    report FAIL "resolved.tsv 更新失败，请检查 target_host 解析。"
  fi
  if (( nft_table_exists == 1 && forwards > 0 )); then
    if (( table_has_any_dnat == 0 )); then
      forward_rule_fix_needed=1
      forward_rule_fix_reason="empty"
    elif (( relay_tcp_missing == 1 || relay_udp_missing == 1 )); then
      forward_rule_fix_needed=1
      forward_rule_fix_reason="partial"
    fi
  fi
  [[ -n "$forward_rule_fix_reason" ]] || forward_rule_fix_reason="legacy"
  doctor_offer_forward_rule_fix "$forward_rule_fix_needed" "$forward_rule_fix_reason"
  report_entry_ddns_cache_status
  report_pbr_domain_ddns_status
  [[ -f "$NETWORK_PAIRING_FILE" ]] && report OK "relay 网络码：已生成"
}

is_fake_dns_ip() {
  local ip="$1"
  [[ "$ip" == 198.18.* || "$ip" == 198.19.* ]]
}

doctor_dependency_tools() {
  local cmd
  for cmd in curl jq tar unzip; do
    if command -v "$cmd" >/dev/null 2>&1; then
      report OK "依赖命令存在：${cmd}"
    elif [[ "$cmd" == "jq" && -x "$EASYTIER_CORE_BIN" && -x "$EASYTIER_CLI_BIN" ]]; then
      report INFO "jq 缺失只影响 GitHub release metadata 获取，不影响当前已安装 EasyTier 运行。"
    else
      report WARN "依赖命令缺失：${cmd}"
    fi
  done
}

doctor_fake_ip_dns() {
  local host ip found any_fake=0
  command -v getent >/dev/null 2>&1 || { report INFO "未找到 getent，跳过 fake-ip DNS 检查。"; return 0; }
  for host in raw.githubusercontent.com api.github.com cn.archive.ubuntu.com; do
    found=0
    while IFS= read -r ip; do
      [[ -n "$ip" ]] || continue
      found=1
      if is_fake_dns_ip "$ip"; then
        any_fake=1
        report WARN "${host} -> ${ip}，DNS 解析到了 198.18.x.x fake-ip。"
      else
        report OK "${host} -> ${ip}"
      fi
    done < <(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u)
    (( found == 1 )) || report WARN "${host} 未解析到 IPv4。"
  done
  if (( any_fake == 1 )); then
    report WARN "DNS 解析到了 198.18.x.x fake-ip，可能是 OpenClash / Mihomo / sing-box fake-ip DNS。"
    report WARN "如果本机流量没有被透明代理接管，会导致 GitHub / apt 连接超时。"
    report HINT "请改用真实 DNS，例如 223.5.5.5 / 119.29.29.29，或在路由器中让该主机直连 / 正确透明代理。"
  fi
}

doctor_apt_sources() {
  local tmp
  command -v apt-get >/dev/null 2>&1 || { report INFO "未找到 apt-get，跳过 apt 源检查。"; return 0; }
  if (( EUID != 0 )); then
    report INFO "非 root 运行，跳过 apt 源下载检查。"
    return 0
  fi
  tmp="$(mktemp)"
  if apt-get update -o Acquire::Retries=0 >"$tmp" 2>&1; then
    report OK "apt 源更新检查通过。"
  else
    report WARN "apt 源更新检查失败，依赖包可能无法自动安装。"
  fi
  if grep -qi 'mirror sync in progress\|sync in progress\|正在同步' "$tmp"; then
    report WARN "apt 镜像可能正在同步，请稍后重试或换源。"
  fi
  if grep -qi '403[[:space:]]\+Forbidden\|403 Forbidden' "$tmp"; then
    report WARN "apt 源返回 403 Forbidden，请换源或手动安装 deb 包。"
  fi
  rm -f "$tmp"
}

doctor() {
  local role bbr_cc bbr_qdisc
  REPORT_WARN_COUNT=0
  REPORT_FAIL_COUNT=0
  role="$(detect_role)"
  bbr_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  bbr_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  if [[ "$bbr_cc" == "bbr" && "$bbr_qdisc" == "fq" ]]; then report OK "BBR/fq enabled"; else report INFO "BBR=${bbr_cc:-unknown}, qdisc=${bbr_qdisc:-unknown}"; fi
  doctor_dependency_tools
  doctor_fake_ip_dns
  doctor_apt_sources
  case "$role" in
    cloud-entry) doctor_cloud ;;
    leikwan-relay) doctor_relay ;;
    *) report WARN "角色未知，请先执行 EasyTier 快速配对" ;;
  esac
  if (( VERBOSE_DOCTOR == 1 )); then
    report DEBUG "entries.tsv=${ENTRIES_TSV}"
    report DEBUG "forwards.tsv=${FORWARDS_TSV}"
    report DEBUG "network.env=${NETWORK_ENV}"
    report DEBUG "nft=${NFT_RULE_FILE}"
  fi
  write_status_cache doctor "$(status_result_from_counts)"
}

status_mark_result() {
  case "$1" in
    fail) STATUS_OVERVIEW_RESULT="fail" ;;
    warn) [[ "$STATUS_OVERVIEW_RESULT" == "fail" ]] || STATUS_OVERVIEW_RESULT="warn" ;;
  esac
}

status_cache_summary() {
  local kind="$1" file prefix time result
  case "$kind" in
    apply) file="${STATUS_DIR}/last-apply.env"; prefix="LAST_APPLY" ;;
    doctor) file="${STATUS_DIR}/last-doctor.env"; prefix="LAST_DOCTOR" ;;
    status) file="${STATUS_DIR}/last-status.env"; prefix="LAST_STATUS" ;;
    *) return 0 ;;
  esac
  time="$(env_file_get "$file" "${prefix}_TIME")"
  result="$(env_file_get "$file" "${prefix}_RESULT")"
  if [[ -n "$time" && -n "$result" ]]; then
    printf '%s / %s' "$time" "$(status_result_display "$result")"
  elif [[ -n "$time" ]]; then
    printf '%s' "$time"
  else
    printf '-'
  fi
}

named_status_summary() {
  local file="$1" prefix="$2" default_text="${3:-无记录}" time result mode
  time="$(env_file_get "$file" "${prefix}_TIME")"
  result="$(env_file_get "$file" "${prefix}_RESULT")"
  mode="$(env_file_get "$file" "${prefix}_MODE")"
  if [[ -n "$time" ]]; then
    if [[ -n "$mode" ]]; then
      printf '%s / %s' "$time" "$mode"
    elif [[ -n "$result" ]]; then
      printf '%s / %s' "$time" "$(status_result_display "$result")"
    else
      printf '%s' "$time"
    fi
  else
    printf '%s' "$default_text"
  fi
}

status_ddns_entry_summary() {
  local changed failed relay_needed
  changed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_ENTRY_CHANGED)"
  failed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_ENTRY_FAILED)"
  relay_needed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_RELAY_RESTART_NEEDED)"
  if [[ -n "$failed" ]]; then
    status_mark_result warn
    printf 'WARN failed=%s' "$failed"
  elif [[ "${relay_needed,,}" == "true" && -n "$changed" ]]; then
    status_mark_result warn
    printf '%s changed，relay restart needed' "$changed"
  elif [[ -n "$changed" ]]; then
    printf '%s changed' "$changed"
  else
    printf 'OK'
  fi
}

status_ddns_pbr_summary() {
  local changed failed
  changed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_PBR_CHANGED)"
  failed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_PBR_FAILED)"
  if [[ -n "$failed" ]]; then
    status_mark_result warn
    printf 'WARN failed=%s' "$failed"
  elif [[ -n "$changed" ]]; then
    printf '%s changed' "$changed"
  else
    printf 'OK'
  fi
}

status_ddns_forward_summary() {
  local changed failed
  changed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_FORWARD_CHANGED)"
  failed="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_FORWARD_FAILED)"
  if [[ -n "$failed" ]]; then
    status_mark_result warn
    printf 'WARN failed=%s' "$failed"
  elif [[ -n "$changed" ]]; then
    printf '%s changed' "$changed"
  else
    printf 'OK'
  fi
}

report_local_entry_ddns_status() {
  local host resolved public_ip
  host="$(current_entry_configured_public_host)"
  if [[ -z "$host" ]]; then
    report INFO "未配置本机公网入口域名，跳过 DDNS 一致性检查。"
    return 0
  fi
  if ! is_domain_name "$host"; then
    report INFO "本机公网入口地址不是域名，跳过 DDNS 一致性检查：${host}"
    return 0
  fi
  resolved="$(resolve_ipv4_first "$host" 2>/dev/null || true)"
  public_ip="$(detect_public_ipv4 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    report WARN "本机公网入口域名解析失败：${host}"
    return 0
  fi
  if [[ -z "$public_ip" ]]; then
    report WARN "无法获取当前公网 IPv4，跳过本机公网入口 DDNS 对比。"
    report INFO "域名解析：${resolved}"
    return 0
  fi
  if [[ "$resolved" == "$public_ip" ]]; then
    report OK "本机公网入口 DDNS 解析正常：${resolved}"
  else
    report WARN "本机公网入口域名解析与当前公网 IP 不一致。"
    report INFO "域名解析：${resolved}"
    report INFO "当前公网：${public_ip}"
    report INFO "请检查 DDNS 客户端是否正常更新。"
  fi
}

status_local_entry_ddns_line() {
  local host resolved public_ip
  host="$(current_entry_configured_public_host)"
  if [[ -z "$host" ]]; then
    printf 'skipped'
    return 0
  fi
  if ! is_domain_name "$host"; then
    printf 'skipped'
    return 0
  fi
  resolved="$(resolve_ipv4_first "$host" 2>/dev/null || true)"
  public_ip="$(detect_public_ipv4 2>/dev/null || true)"
  if [[ -z "$resolved" || -z "$public_ip" ]]; then
    status_mark_result warn
    printf 'WARN，建议执行 lq --doctor'
  elif [[ "$resolved" == "$public_ip" ]]; then
    printf 'OK %s' "$resolved"
  else
    status_mark_result warn
    printf 'WARN %s != %s' "$resolved" "$public_ip"
  fi
}

report_entry_ddns_cache_status() {
  local name public_host _et_ip _proto _port _weight enabled cached_ip checked=0
  while IFS=$'\t' read -r name public_host _et_ip _proto _port _weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    is_domain_name "$public_host" || continue
    checked=$((checked + 1))
    cached_ip="$(last_resolved_ip_for_entry "$name")"
    if [[ -n "$cached_ip" ]]; then
      report OK "公网入口 ${name} DDNS 缓存：${public_host} -> ${cached_ip}"
    else
      report WARN "公网入口 ${name} 缺少 DDNS 解析缓存，请执行：lq ddns run --scope entries"
    fi
  done < <(entries_rows)
  if (( checked == 0 )); then
    report INFO "未发现 enabled 域名公网入口。"
  fi
  if [[ "$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_RELAY_RESTART_NEEDED)" == "true" ]]; then
    report WARN "公网入口 DDNS 已变化，relay 可能需要重启才能重新解析 peer。"
  fi
}

pbr_domain_rule_matches() {
  local name="$1" cidr="$2" route_table="$3"
  [[ -f "$PBR_STATIC_CONF" ]] || return 1
  awk -v src="pbr-domain:${name}" -v cidr="$cidr" -v table="${route_table#T_}" '
    /^[[:space:]]*($|#)/ { next }
    {
      g=$2
      sub(/^T_/, "", g)
      if ($1 == cidr && g == table && $3 == src) found=1
    }
    END { exit found ? 0 : 1 }
  ' "$PBR_STATIC_CONF"
}

report_pbr_domain_ddns_status() {
  local name host route_table enabled _comment cached_ip current_ip cidr checked=0
  while IFS=$'\t' read -r name host route_table enabled _comment; do
    [[ "$enabled" == "true" ]] || continue
    checked=$((checked + 1))
    if ! is_domain_name "$host"; then
      report WARN "域名 PBR ${name} host 不是域名：${host}"
      continue
    fi
    current_ip="$(resolve_ipv4_first "$host" 2>/dev/null || true)"
    cached_ip="$(last_resolved_ip_for_pbr_domain "$name")"
    if [[ -z "$current_ip" ]]; then
      report WARN "域名 PBR ${name} 解析失败：${host}"
      continue
    fi
    if [[ -n "$cached_ip" && "$cached_ip" != "$current_ip" ]]; then
      report WARN "域名 PBR ${name} 已变化，请执行：lq pbr domain sync"
    else
      report OK "域名 PBR ${name} 解析：${host} -> ${current_ip}"
    fi
    cidr="${current_ip}/32"
    if pbr_domain_rule_matches "$name" "$cidr" "$route_table"; then
      report OK "域名 PBR ${name} 生成规则存在：${cidr} -> ${route_table}"
    elif pbr_rule_key_exists "$PBR_STATIC_CONF" "$cidr" "$route_table"; then
      report INFO "域名 PBR ${name} 对应 CIDR/table 已由其它 PBR 规则覆盖：${cidr} -> ${route_table}"
    else
      report WARN "域名 PBR ${name} 生成规则缺失，请执行：lq pbr domain sync"
    fi
  done < <(pbr_domain_rows)
  if (( checked == 0 )); then
    report INFO "未配置 enabled 域名 PBR。"
  fi
}

systemd_active_state() {
  local service="$1" state
  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'unknown'
    return 1
  fi
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  printf '%s' "${state:-inactive}"
  [[ "$state" == "active" ]]
}

status_nft_summary() {
  local mode="$1" relay_ip="${2:-}" start="${3:-}" end="${4:-}" forwards_enabled="${5:-0}"
  if ! command -v nft >/dev/null 2>&1; then
    printf 'WARN，建议执行 lq --doctor'
    status_mark_result warn
    return 0
  fi
  if ! nft_project_table_exists; then
    printf 'WARN，建议执行 lq --doctor'
    status_mark_result warn
    return 0
  fi
  case "$mode" in
    cloud-entry)
      if [[ -n "$relay_ip" && -n "$start" && -n "$end" ]] &&
        nft_has_cloud_dnat tcp "$relay_ip" "${start}-${end}" &&
        nft_has_cloud_dnat udp "$relay_ip" "${start}-${end}"; then
        printf 'OK'
      else
        printf 'WARN，建议执行 lq --doctor'
        status_mark_result warn
      fi
      ;;
    leikwan-relay)
      if (( forwards_enabled == 0 )) || nft_has_dnat_rules; then
        printf 'OK'
      else
        printf 'WARN，建议执行 lq --doctor'
        status_mark_result warn
      fi
      ;;
    *)
      printf 'OK'
      ;;
  esac
}

status_mss_summary() {
  if ! mss_clamp_enabled; then
    printf 'disabled'
    return 0
  fi
  if nft_has_mss_clamp; then
    printf 'OK'
  else
    printf 'WARN，建议执行 lq forward apply-relay --auto-fix-route'
    status_mark_result warn
  fi
}

status_overview_relay() {
  local service_state relay_ip entries_total entries_enabled forwards_total forwards_enabled
  local primary_row primary_name primary_proto primary_port pbr_count last_apply last_doctor
  local ddns_timer ddns_last_time ddns_last_result ddns_forward_count ddns_entry_count ddns_pbr_count
  local ddns_refresh_forwards ddns_refresh_entries ddns_refresh_pbr
  service_state="$(systemd_active_state "${EASYTIER_RELAY_SERVICE_NAME}.service" || true)"
  [[ "$service_state" == "active" ]] || status_mark_result warn
  relay_ip="$(current_relay_et_ip)"
  entries_total="$(entries_rows | awk 'END{print NR+0}')"
  entries_enabled="$(entries_rows | awk -F'\t' '$7=="true"{c++} END{print c+0}')"
  forwards_total="$(forwards_rows | awk 'END{print NR+0}')"
  forwards_enabled="$(forwards_rows | awk -F'\t' '$7=="true"{c++} END{print c+0}')"
  primary_row="$(enabled_entries_sorted | awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} NR==1 {print $1,$4,$5; exit}')"
  if [[ -n "$primary_row" ]]; then
    IFS=$'\034' read -r primary_name primary_proto primary_port <<<"$primary_row"
  else
    primary_name="无"
    primary_proto="-"
    primary_port="-"
    status_mark_result warn
  fi
  pbr_count="$(pbr_rules_count 2>/dev/null || printf '0')"
  last_apply="$(status_cache_summary apply)"
  last_doctor="$(status_cache_summary doctor)"
  ddns_timer="$(ddns_timer_state)"
  ddns_last_time="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_TIME)"
  ddns_last_result="$(env_file_get "$DDNS_STATUS_FILE" LAST_DDNS_RESULT)"
  ddns_refresh_forwards="$(ddns_config_value DDNS_REFRESH_FORWARDS "$DDNS_REFRESH_FORWARDS_DEFAULT")"
  ddns_refresh_entries="$(ddns_config_value DDNS_REFRESH_ENTRIES "$DDNS_REFRESH_ENTRIES_DEFAULT")"
  ddns_refresh_pbr="$(ddns_config_value DDNS_REFRESH_PBR "$DDNS_REFRESH_PBR_DEFAULT")"
  ddns_forward_count="$(ddns_domain_forward_count 2>/dev/null || printf '0')"
  ddns_entry_count="$(ddns_domain_entry_count 2>/dev/null || printf '0')"
  ddns_pbr_count="$(ddns_domain_pbr_count 2>/dev/null || printf '0')"
  echo "角色: leikwan-relay"
  echo "EasyTier: relay ${service_state}"
  echo "Relay IP: ${relay_ip}"
  echo "公网入口: ${entries_enabled} enabled / ${entries_total} total"
  if [[ "$primary_name" == "无" ]]; then
    echo "主入口: 无"
  else
    echo "主入口: $(entry_label "$primary_name") $(easytier_protocols_display "$primary_proto")/${primary_port}"
  fi
  echo "转发目标: ${forwards_enabled} enabled / ${forwards_total} total"
  echo "PBR 规则: ${pbr_count}"
  echo "nftables: $(status_nft_summary leikwan-relay "" "" "" "$forwards_enabled")"
  echo "MSS clamp: $(status_mss_summary)"
  echo "DDNS 自动刷新: ${ddns_timer}"
  echo "DDNS scopes: forwards=$(bool_yes_no "$ddns_refresh_forwards") entries=$(bool_yes_no "$ddns_refresh_entries") pbr=$(bool_yes_no "$ddns_refresh_pbr")"
  if [[ -n "$ddns_last_time" ]]; then
    echo "最近 DDNS: ${ddns_last_time} / $(status_result_display "$ddns_last_result")"
    echo "后端 DDNS: $(status_ddns_forward_summary)"
    echo "公网入口 DDNS: $(status_ddns_entry_summary)"
    echo "PBR DDNS: $(status_ddns_pbr_summary)"
  else
    echo "最近 DDNS: -"
    echo "后端 DDNS: -"
    echo "公网入口 DDNS: -"
    echo "PBR DDNS: -"
  fi
  if (( (ddns_forward_count + ddns_entry_count + ddns_pbr_count) > 0 )) && [[ "$ddns_timer" != "active" ]]; then
    echo "[INFO] 检测到域名 DDNS 对象，可在 DDNS 菜单中启用自动刷新。"
  fi
  echo "最近应用: ${last_apply}"
  echo "最近诊断: ${last_doctor}"
}

status_overview_entry() {
  local entry_name display_name et_ip proto port service_name service_state start end relay_ip last_doctor
  entry_name="$(env_file_get "$NETWORK_ENV" ENTRY_NAME)"
  [[ -n "$entry_name" ]] || entry_name="$(env_file_get "$ENTRY_PAIRING_FILE" ENTRY_NAME)"
  display_name="$(env_file_get "$NETWORK_ENV" ENTRY_DISPLAY_NAME)"
  [[ -n "$display_name" ]] || display_name="$(env_file_get "$ENTRY_PAIRING_FILE" ENTRY_DISPLAY_NAME)"
  [[ -n "$entry_name" ]] || entry_name="entry"
  [[ -n "$display_name" ]] || display_name="$(entry_label "$entry_name")"
  et_ip="$(current_entry_et_ip)"
  proto="$(easytier_protocols_from_env "$NETWORK_ENV" EASYTIER_PROTOCOLS EASYTIER_PROTOCOL "$EASYTIER_PROTOCOLS_DEFAULT" 2>/dev/null || printf '%s' "$EASYTIER_PROTOCOLS_DEFAULT")"
  port="$(easytier_port_from_env "$NETWORK_ENV" "$proto" EASYTIER_TCP_PORT EASYTIER_UDP_PORT EASYTIER_LISTEN_PORT 2>/dev/null || true)"
  [[ -n "$port" ]] || port="$(easytier_port_from_env "$ENTRY_PAIRING_FILE" "$proto" EASYTIER_TCP_PORT EASYTIER_UDP_PORT EASYTIER_PORT 2>/dev/null || printf '%s' "$EASYTIER_PORT_DEFAULT")"
  service_name="$(entry_service_name "$entry_name").service"
  service_state="$(systemd_active_state "$service_name" || true)"
  [[ "$service_state" == "active" ]] || status_mark_result warn
  start="$(entry_expose_start)"
  end="$(entry_expose_end)"
  relay_ip="$(entry_expose_relay_ip)"
  last_doctor="$(status_cache_summary doctor)"
  echo "角色: cloud-entry"
  echo "入口名称: ${display_name}"
  echo "EasyTier IP: ${et_ip}"
  echo "EasyTier service: ${service_state}"
  echo "监听: $(easytier_protocols_display "$proto")/${port}"
  echo "公网入口端口池: ${start}-${end}"
  echo "本机公网入口 DDNS: $(status_local_entry_ddns_line)"
  echo "nftables: $(status_nft_summary cloud-entry "$relay_ip" "$start" "$end" 0)"
  echo "MSS clamp: $(status_mss_summary)"
  echo "最近诊断: ${last_doctor}"
}

status_overview() {
  local role
  STATUS_OVERVIEW_RESULT="ok"
  role="$(detect_role)"
  echo "Leikwan 状态总览"
  echo "----------------------------------------"
  echo "脚本版本: ${TOOL_VERSION}"
  echo "最近更新: $(update_status_line)"
  case "$role" in
    leikwan-relay) status_overview_relay ;;
    cloud-entry) status_overview_entry ;;
    *)
      echo "角色: unknown"
      echo "nftables: $(status_nft_summary unknown)"
      echo "MSS clamp: $(status_mss_summary)"
      status_mark_result warn
      ;;
  esac
  echo "最近配置导出: $(named_status_summary "${STATUS_DIR}/last-config-export.env" LAST_CONFIG_EXPORT)"
  echo "最近配置导入: $(named_status_summary "${STATUS_DIR}/last-config-import.env" LAST_CONFIG_IMPORT)"
  echo "最近端点输出: $(named_status_summary "${STATUS_DIR}/last-output.env" LAST_OUTPUT)"
  echo "整体状态: $(status_result_display "$STATUS_OVERVIEW_RESULT")"
  write_status_cache status "$STATUS_OVERVIEW_RESULT"
  if [[ "$STATUS_OVERVIEW_RESULT" == "ok" ]]; then
    echo "[OK] 当前状态正常。"
  else
    echo "[INFO] 建议执行：lq --doctor"
  fi
}

port_check_mark() {
  case "$1" in
    fail) PORT_CHECK_RESULT="fail" ;;
    warn) [[ "$PORT_CHECK_RESULT" == "fail" ]] || PORT_CHECK_RESULT="warn" ;;
  esac
}

port_check_line() {
  local level="$1" msg="$2"
  case "$level" in
    OK) printf '[OK] %s\n' "$msg" ;;
    WARN) printf '[WARN] %s\n' "$msg"; port_check_mark warn ;;
    FAIL) printf '[FAIL] %s\n' "$msg"; port_check_mark fail ;;
    INFO) printf '[INFO] %s\n' "$msg" ;;
  esac
}

check_easytier_ports() {
  local any=0 name _public_host _et_ip proto port _weight enabled count conflict
  local pending_name _pending_ip _pending_proto pending_port _pending_created_at
  echo "EasyTier 端口:"
  while IFS=$'\t' read -r name _public_host _et_ip proto port _weight enabled; do
    any=1
    count="$(entries_rows | awk -F'\t' -v p="$port" '$5==p{c++} END{print c+0}')"
    if [[ "$enabled" != "true" ]]; then
      port_check_line WARN "${port} ${name} 已 disabled，但端口仍在历史配置中"
    elif (( count > 1 )); then
      port_check_line WARN "${port} ${name} 与其它公网入口重复"
    elif ! is_fast_port "$port"; then
      port_check_line WARN "${port} ${name} $(easytier_protocols_display "$proto")，不在 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END} 白名单"
    else
      conflict="$(easytier_port_conflict_message "$port" "$name" || true)"
      if [[ -n "$conflict" ]]; then
        port_check_line WARN "${port} ${name} ${conflict}"
      else
        port_check_line OK "${port} ${name} $(easytier_protocols_display "$proto")，位于 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END} 白名单"
      fi
    fi
  done < <(entries_rows)
  while IFS=$'\t' read -r pending_name _pending_ip _pending_proto pending_port _pending_created_at; do
    any=1
    if is_fast_port "$pending_port"; then
      port_check_line WARN "${pending_port} ${pending_name} pending 预占，尚未完成接入"
    else
      port_check_line WARN "${pending_port} ${pending_name} pending 预占且不在白名单"
    fi
  done < <(pending_entries_rows)
  (( any == 1 )) || port_check_line INFO "未发现公网入口或 pending 接入码。"
  echo
}

check_forward_ports() {
  local any=0 name entry_port _target_host _target_port _out_iface _route_table enabled _comment count
  local _kind start end
  IFS=$'\t' read -r _kind start end <<<"$(entry_pool_for_prompt)"
  echo "业务入口端口:"
  while IFS=$'\t' read -r name entry_port _target_host _target_port _out_iface _route_table enabled _comment; do
    any=1
    count="$(forwards_rows | awk -F'\t' -v p="$entry_port" '$2==p{c++} END{print c+0}')"
    if (( count > 1 )); then
      port_check_line WARN "${entry_port} ${name} 与其它转发目标重复"
    elif [[ "$enabled" != "true" ]]; then
      port_check_line WARN "${entry_port} ${name} 已 disabled，但端口仍在历史配置中"
    elif ! port_in_range "$entry_port" "$start" "$end"; then
      port_check_line WARN "${entry_port} ${name} 不在入口端口池 ${start}-${end}"
    else
      port_check_line OK "${entry_port} ${name}"
    fi
  done < <(forwards_rows)
  (( any == 1 )) || port_check_line INFO "未发现转发目标。"
  echo
}

check_listening_conflicts() {
  local name entry_port _target_host _target_port _out_iface _route_table _enabled _comment conflict=0
  echo "本机监听:"
  if ! command -v ss >/dev/null 2>&1; then
    port_check_line INFO "未找到 ss，跳过本机监听检查。"
    echo
    return 0
  fi
  while IFS=$'\t' read -r name entry_port _target_host _target_port _out_iface _route_table _enabled _comment; do
    if port_listening_any "$entry_port"; then
      conflict=1
      port_check_line WARN "${entry_port} ${name} 已被本机监听进程占用"
    fi
  done < <(forwards_rows)
  (( conflict == 1 )) || port_check_line OK "未发现业务入口端口被其它进程监听"
  if ss_port_listening tcp 22; then
    port_check_line INFO "22/tcp ssh 正常，未纳入 leikwan 管理"
  fi
  echo
}

check_nft_port_conflicts() {
  local name entry_port _target_host _target_port _out_iface _route_table enabled _comment
  local any=0 tcp_ok udp_ok
  echo "nftables:"
  if ! command -v nft >/dev/null 2>&1; then
    port_check_line WARN "未找到 nft，跳过 nftables dport 检查。"
    echo
    return 0
  fi
  if ! nft_project_table_exists; then
    port_check_line WARN "未发现项目 nftables 表 inet leikwan_forward"
    echo
    return 0
  fi
  while IFS=$'\t' read -r name entry_port _target_host _target_port _out_iface _route_table enabled _comment; do
    [[ "$enabled" == "true" ]] || continue
    any=1
    tcp_ok=0
    udp_ok=0
    nft_project_has_dport "$entry_port" tcp && tcp_ok=1
    nft_project_has_dport "$entry_port" udp && udp_ok=1
    if (( tcp_ok == 1 && udp_ok == 1 )); then
      port_check_line OK "${entry_port} tcp/udp DNAT 存在"
    elif (( tcp_ok == 1 )); then
      port_check_line WARN "${entry_port} tcp DNAT 存在，udp DNAT 缺失"
    elif (( udp_ok == 1 )); then
      port_check_line WARN "${entry_port} udp DNAT 存在，tcp DNAT 缺失"
    else
      port_check_line WARN "${entry_port} ${name} tcp/udp DNAT 未发现"
    fi
  done < <(forwards_rows)
  (( any == 1 )) || port_check_line INFO "没有 enabled 转发目标需要检查 DNAT。"
  echo
}

port_check() {
  PORT_CHECK_RESULT="ok"
  echo "端口冲突预检"
  echo "----------------------------------------"
  check_easytier_ports
  check_forward_ports
  check_listening_conflicts
  check_nft_port_conflicts
  echo "整体状态: $(status_result_display "$PORT_CHECK_RESULT")"
}

run_doctor_interactive() {
  local old_doctor_interactive_fix="$DOCTOR_INTERACTIVE_FIX"
  DOCTOR_INTERACTIVE_FIX=1
  doctor
  DOCTOR_INTERACTIVE_FIX="$old_doctor_interactive_fix"
}

fix_dns_ipv4_first() {
  need_root_unless_dry_run
  local gai_line
  gai_line='precedence ::ffff:0:0/96  100'
  backup_file /etc/gai.conf
  if grep -q "$gai_line" /etc/gai.conf 2>/dev/null; then
    ok "IPv4 优先规则已存在：/etc/gai.conf"
  elif (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 追加 ${gai_line} 到 /etc/gai.conf"
  elif printf '%s\n' "$gai_line" >>/etc/gai.conf; then
    ok "已启用 IPv4 优先：/etc/gai.conf"
  else
    warn "写入 /etc/gai.conf 失败，请检查文件权限。"
    return 1
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files --no-legend systemd-resolved.service 2>/dev/null | grep -q .; then
    write_file "$DNS_RESOLVED_CONF" $'[Resolve]\nDNS=8.8.8.8 1.1.1.1 8.8.4.4\nFallbackDNS=9.9.9.9 223.5.5.5\nLLMNR=no\nMulticastDNS=no' 644
    systemctl restart systemd-resolved 2>/dev/null || warn "systemd-resolved 重启失败，请稍后手动检查 DNS。"
  else
    warn "未检测到 systemd-resolved，已仅处理 IPv4 优先规则。"
  fi
  if command -v getent >/dev/null 2>&1 && getent ahosts raw.githubusercontent.com >/dev/null; then
    ok "raw.githubusercontent.com 可解析"
  else
    warn "raw.githubusercontent.com 解析失败"
  fi
}

ipv6_lockdown() {
  need_root_unless_dry_run
  install_packages iptables-persistent
  ip6tables -N V6_LOCKDOWN 2>/dev/null || true
  ip6tables -F V6_LOCKDOWN
  ip6tables -A V6_LOCKDOWN -i lo -j ACCEPT
  ip6tables -A V6_LOCKDOWN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A V6_LOCKDOWN -p ipv6-icmp -j ACCEPT
  ip6tables -A V6_LOCKDOWN -p tcp --dport 22 -j ACCEPT
  ip6tables -A V6_LOCKDOWN -j DROP
  ip6tables -C INPUT -j V6_LOCKDOWN 2>/dev/null || ip6tables -I INPUT -j V6_LOCKDOWN
  mkdir -p /etc/iptables
  ip6tables-save >/etc/iptables/rules.v6
  ok "IPv6 入站已收口。"
}

bbr_menu() {
  local choice
  while true; do
    print_menu_header "BBR / 系统优化"
    echo "1. 查看状态"; echo "2. 启用 BBR + fq"; echo "3. 恢复默认"; echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc 2>/dev/null || true; pause_after_action ;;
      2) write_file "$BBR_SYSCTL_CONF" $'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' 644; modprobe tcp_bbr 2>/dev/null || true; sysctl --system; pause_after_action ;;
      3) backup_file "$BBR_SYSCTL_CONF"; rm -f "$BBR_SYSCTL_CONF"; sysctl --system; pause_after_action ;;
      0) return 0 ;;
    esac
  done
}

link_test_menu() {
  local choice
  while true; do
    print_menu_header "链路测试"
    echo "1. ping relay EasyTier IP"; echo "2. ping 所有入口 EasyTier IP"; echo "3. 测入口 EasyTier TCP/UDP"; echo "4. 测后端 target"; echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) ping_entry_et_ip "relay" "$RELAY_ET_IP" plain || true; pause_after_action ;;
      2) entries_rows | while IFS=$'\t' read -r n _h ip _proto _port _w e; do [[ "$e" == "true" ]] && ping_entry_et_ip "$n" "$ip" plain || true; done; pause_after_action ;;
      3)
        ensure_nc_for_test || { pause_after_action; continue; }
        entries_rows | while IFS=$'\t' read -r n h ip proto port _w e; do [[ "$e" == "true" ]] && test_entry_row "$n" "$h" "$ip" "$proto" "$port" "$e" || true; done
        pause_after_action
        ;;
      4)
        ensure_nc_for_test || { pause_after_action; continue; }
        resolved_rows | while IFS=$'\t' read -r n _ep _th ti tp _oi _rt en _ts _comment; do
          [[ "$en" == "true" && -n "$ti" ]] || continue
          nc -vz -w 3 "$ti" "$tp" || true
          case "$(udp_probe_status "$ti" "$tp")" in
            0) ok "${n} target UDP 探测完成：${ti}:${tp}" ;;
            *) warn "${n} target UDP 探测未确认。UDP 无连接探测可能不可靠，请结合业务实际测试。" ;;
          esac
        done
        pause_after_action
        ;;
      0) return 0 ;;
    esac
  done
}

generate_debug_report() {
  need_root_unless_dry_run
  local tmp
  tmp="$(mktemp)"
  {
    echo "leikwan-toolkit debug report ${TOOL_VERSION}"
    bash "$UPDATE_TARGET_SCRIPT" --version 2>&1 || true
    if command -v lq >/dev/null 2>&1; then
      lq --version 2>&1 || true
      readlink -f "$SHORTCUT_LQ" 2>&1 || true
    fi
    ls -lh "$UPDATE_TARGET_SCRIPT" 2>&1 || true
    cat /etc/os-release 2>/dev/null || true
    ip -br addr || true
    ip route || true
    ip rule || true
    systemctl --no-pager --full status "$EASYTIER_RELAY_SERVICE_NAME" 'easytier-entry-*' "$NFT_SERVICE_NAME" "${DDNS_SERVICE_NAME}.service" "${DDNS_SERVICE_NAME}.timer" 2>&1 || true
    ss -lntup || true
    nft list table inet leikwan_forward 2>&1 || true
    "$EASYTIER_CLI_BIN" peer 2>&1 || true
    doctor || true
    echo "ddns.env:"
    [[ -f "$DDNS_CONFIG" ]] && sed -n '1,120p' "$DDNS_CONFIG"
    echo "last-ddns.env:"
    [[ -f "$DDNS_STATUS_FILE" ]] && sed -n '1,120p' "$DDNS_STATUS_FILE"
    echo "last-update.env:"
    [[ -f "$UPDATE_STATUS_FILE" ]] && sed -n '1,120p' "$UPDATE_STATUS_FILE"
    echo "last-config-export.env:"
    [[ -f "${STATUS_DIR}/last-config-export.env" ]] && sed -n '1,120p' "${STATUS_DIR}/last-config-export.env"
    echo "last-config-import.env:"
    [[ -f "${STATUS_DIR}/last-config-import.env" ]] && sed -n '1,120p' "${STATUS_DIR}/last-config-import.env"
    echo "last-output.env:"
    [[ -f "${STATUS_DIR}/last-output.env" ]] && sed -n '1,120p' "${STATUS_DIR}/last-output.env"
    echo "ddns log tail:"
    [[ -f "$DDNS_LOG_FILE" ]] && tail -n 100 "$DDNS_LOG_FILE"
    echo "resolved-entries.tsv:"
    [[ -f "$RESOLVED_ENTRIES_TSV" ]] && sed -n '1,160p' "$RESOLVED_ENTRIES_TSV"
    echo "pbr/domain-routes.tsv:"
    [[ -f "$PBR_DOMAIN_TSV" ]] && sed -n '1,160p' "$PBR_DOMAIN_TSV"
    echo "pbr/resolved-pbr-domains.tsv:"
    [[ -f "$PBR_RESOLVED_DOMAIN_TSV" ]] && sed -n '1,160p' "$PBR_RESOLVED_DOMAIN_TSV"
    echo "outputs:"
    find "$OUTPUT_DIR" -maxdepth 2 -type f -printf '%p\t%s bytes\n' 2>/dev/null || true
    [[ -f "$FORWARD_TSV" ]] && sed -n '1,120p' "$FORWARD_TSV"
    echo "forward-endpoints.json summary:"
    [[ -f "$FORWARD_JSON" ]] && sed -n '1,220p' "$FORWARD_JSON"
  } >"$tmp" 2>&1
  sed -E \
    -e 's/(EASYTIER_NETWORK_SECRET=).*/\1<redacted>/g' \
    -e 's/(PAIRING_CODE_BASE64=).*/\1<redacted>/g' \
    -e 's/(LEIKWAN_[A-Z0-9_]*_BASE64=).*/\1<redacted>/g' \
    -e 's/(([Tt]oken|[Pp]assword)[[:space:]_=-]+)[^[:space:]]+/\1<redacted>/g' \
    -e 's#(LAST_UPDATE_SOURCE=https?://[^?[:space:]]+)\?[^[:space:]]+#\1?<redacted>#g' \
    -e 's/(PrivateKey[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1<redacted>/g' \
    -e 's#(vless|vmess|trojan|ss|hysteria)://[^[:space:]]+#<proxy-link-redacted>#g' \
    "$tmp" >"$REPORT_FILE"
  rm -f "$tmp"
  chmod 600 "$REPORT_FILE"
  ok "已生成脱敏故障报告：${REPORT_FILE}"
  wait_file_output_confirm "脱敏故障报告" "$REPORT_FILE"
}

legacy_cleanup_menu() {
  need_root
  local choice
  while true; do
    print_menu_header "legacy 清理（默认不执行）"
    echo "1. 清理旧内核隧道残留"
    echo "2. 清理旧 UDP 加速残留"
    echo "3. 清理旧端口代理残留"
    echo "4. 清理旧四层转发残留"
    echo "5. 清理旧测试服务残留"
    echo "6. 清理脚本生成的 nftables 规则"
    echo "7. 清理 EasyTier 服务和配置"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1)
        if prompt_yes_no "二次确认清理旧内核隧道残留？" "N"; then
          systemctl disable --now wg-quick@wg0 wg-quick@wg1 2>/dev/null || true
          rm -f /etc/wireguard/wg0.conf /etc/wireguard/wg1.conf /etc/wireguard/wg0_privatekey /etc/wireguard/wg1_privatekey /etc/wireguard/wg0_publickey /etc/wireguard/wg1_publickey
        fi
        ;;
      2)
        if prompt_yes_no "二次确认清理旧 UDP 加速残留？" "N"; then
          systemctl disable --now phantun-server-leikwan 'phantun-client-entry-*' 2>/dev/null || true
          rm -f /etc/systemd/system/phantun-server-leikwan.service /etc/systemd/system/phantun-client-entry-*.service /usr/local/bin/phantun_server /usr/local/bin/phantun_client
        fi
        ;;
      3)
        if prompt_yes_no "二次确认清理旧端口代理残留？" "N"; then
          systemctl disable --now frps-leikwan frpc-leikwan 2>/dev/null || true
          rm -f /etc/systemd/system/frps-leikwan.service /etc/systemd/system/frpc-leikwan.service /etc/frp/frps-leikwan.toml /etc/frp/frpc-leikwan.toml
        fi
        ;;
      4)
        if prompt_yes_no "二次确认清理旧四层转发残留？" "N"; then
          systemctl disable --now realm-leikwan 2>/dev/null || true
          rm -f /etc/systemd/system/realm-leikwan.service
          rm -rf "${STATE_DIR}/realm"
        fi
        ;;
      5)
        if prompt_yes_no "二次确认清理旧测试服务残留？" "N"; then
          systemctl disable --now xray-leikwan 2>/dev/null || true
          rm -f /etc/systemd/system/xray-leikwan.service
          rm -rf /usr/local/etc/xray/leikwan
        fi
        ;;
      6) cleanup_nftables_rules ;;
      7)
        echo "将清理本脚本生成的 EasyTier 服务与配置："
        echo "- ${EASYTIER_RELAY_SERVICE}"
        echo "- /etc/systemd/system/easytier-entry-*.service"
        echo "- ${EASYTIER_DIR}"
        if prompt_yes_no "二次确认清理 EasyTier 服务和配置？" "N"; then
          if command -v systemctl >/dev/null 2>&1; then
            systemctl disable --now "$EASYTIER_RELAY_SERVICE_NAME" 2>/dev/null || true
            systemctl list-unit-files --type=service --no-legend 'easytier-entry-*.service' 2>/dev/null | awk '{print $1}' | while read -r svc; do
              systemctl disable --now "$svc" 2>/dev/null || true
              rm -f "/etc/systemd/system/${svc}"
            done
          else
            warn "未找到 systemctl，跳过 systemd 服务停止。"
          fi
          rm -f "$EASYTIER_RELAY_SERVICE"
          rm -rf "$EASYTIER_DIR"
        fi
        ;;
      0) return 0 ;;
    esac
    command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
    [[ "$choice" =~ ^[1-7]$ ]] && pause_after_action
  done
}

safe_stop_disable_service() {
  local svc="$1"
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl disable --now "$svc" 2>/dev/null || true
}

safe_rm_file() {
  local path
  for path in "$@"; do
    rm -f "$path" 2>/dev/null || true
  done
}

safe_rm_dir() {
  local path
  for path in "$@"; do
    rm -rf "$path" 2>/dev/null || true
  done
}

cleanup_easytier_entry_units() {
  local svc unit
  if command -v systemctl >/dev/null 2>&1; then
    while IFS= read -r svc; do
      [[ -n "$svc" ]] || continue
      safe_stop_disable_service "$svc"
      safe_rm_file "/etc/systemd/system/${svc}"
    done < <(systemctl list-unit-files --type=service --no-legend 'easytier-entry-*.service' 2>/dev/null | awk '{print $1}' || true)
  fi
  for unit in /etc/systemd/system/easytier-entry-*.service; do
    [[ -e "$unit" ]] || continue
    svc="$(basename "$unit")"
    safe_stop_disable_service "$svc"
    safe_rm_file "$unit"
  done
}

cleanup_leikwan_policy_routes() {
  local table table_id pref tmp
  if command -v ip >/dev/null 2>&1; then
    while IFS= read -r pref; do
      [[ -n "$pref" ]] || continue
      ip rule del pref "$pref" 2>/dev/null || true
    done < <(ip rule show 2>/dev/null | awk -v p="$PBR_PRIORITY" '$1 ~ "^"p":" {gsub(":","",$1); print $1}' || true)
  fi
  for table in T_CN2 T_9929; do
    if command -v ip >/dev/null 2>&1; then
      ip route flush table "$table" 2>/dev/null || true
      table_id=""
      if [[ -f "$PBR_RT_TABLES" ]]; then
        table_id="$(awk -v t="$table" '$2==t {print $1; exit}' "$PBR_RT_TABLES" 2>/dev/null || true)"
      fi
      [[ -n "$table_id" ]] && ip route flush table "$table_id" 2>/dev/null || true
      while IFS= read -r pref; do
        [[ -n "$pref" ]] || continue
        ip rule del pref "$pref" table "$table" 2>/dev/null || true
        [[ -n "$table_id" ]] && ip rule del pref "$pref" table "$table_id" 2>/dev/null || true
      done < <(ip rule show 2>/dev/null | awk -v t="$table" '$0 ~ ("lookup " t) {gsub(":","",$1); print $1}' || true)
      if [[ -n "$table_id" ]]; then
        while IFS= read -r pref; do
          [[ -n "$pref" ]] || continue
          ip rule del pref "$pref" table "$table_id" 2>/dev/null || true
        done < <(ip rule show 2>/dev/null | awk -v t="$table_id" '$0 ~ ("lookup " t "($| )") {gsub(":","",$1); print $1}' || true)
      fi
    fi
  done
  if [[ -f "$PBR_RT_TABLES" ]]; then
    tmp="$(mktemp)"
    awk '$2!="T_CN2" && $2!="T_9929" {print}' "$PBR_RT_TABLES" >"$tmp" 2>/dev/null || true
    if [[ -s "$tmp" ]]; then
      cat "$tmp" >"$PBR_RT_TABLES" 2>/dev/null || true
    fi
    rm -f "$tmp" 2>/dev/null || true
  fi
}

systemd_reload_reset_failed() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl daemon-reload 2>/dev/null || true
  systemctl reset-failed 2>/dev/null || true
}

uninstall_check_command_absent() {
  local label="$1" command_name="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    warn "${label}：仍可执行 $(command -v "$command_name" 2>/dev/null)"
  else
    ok "${label}：已清理"
  fi
}

uninstall_check_line() {
  local label="$1" kind="$2" value="$3"
  case "$kind" in
    file)
      if [[ ! -e "$value" ]]; then
        ok "${label}：已清理"
      else
        warn "${label}：仍存在 ${value}"
      fi
      ;;
    dir)
      if [[ ! -e "$value" ]]; then
        ok "${label}：已清理"
      else
        warn "${label}：仍存在 ${value}"
      fi
      ;;
    service)
      if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files --type=service --no-legend "$value" 2>/dev/null | grep -q .; then
        warn "${label}：服务文件仍存在 ${value}"
      else
        ok "${label}：已清理"
      fi
      ;;
    nft)
      if command -v nft >/dev/null 2>&1 && nft list table inet "$value" >/dev/null 2>&1; then
        warn "${label}：nft table 仍存在 inet ${value}"
      else
        ok "${label}：已清理"
      fi
      ;;
  esac
}

uninstall_new_mode() {
  need_root
  echo
  echo "${BOLD}卸载全部说明${RESET}"
  echo "这会删除通过本脚本安装/生成的服务、配置、nftables 规则、EasyTier 文件、快捷命令。"
  echo "不会删除系统本身，也不会删除用户手动部署的业务。"
  echo "将处理的路径："
  echo "- ${STATE_DIR}"
  echo "- ${OLD_STATE_DIR}（历史路径清理）"
  echo "- ${EASYTIER_CORE_BIN} / ${EASYTIER_CLI_BIN}"
  echo "- ${SHORTCUT_LQ} / ${SHORTCUT_LQ_UPPER}"
  echo "- ${NFT_RULE_FILE} / ${NFT_SERVICE}"
  prompt_yes_no "第一次确认：继续卸载全部？" "N" || return 0
  prompt_yes_no "第二次确认：确实删除本脚本生成的组件？" "N" || return 0
  auto_snapshot_or_confirm "uninstall-all" || return 0

  LOG_DISABLED=1
  set +e
  if command -v systemctl >/dev/null 2>&1; then
    safe_stop_disable_service "$EASYTIER_RELAY_SERVICE_NAME"
    safe_stop_disable_service "$NFT_SERVICE_NAME"
    safe_stop_disable_service "${DDNS_SERVICE_NAME}.timer"
    safe_stop_disable_service "${DDNS_SERVICE_NAME}.service"
    safe_stop_disable_service "leikwan-mss-clamp.service"
    cleanup_easytier_entry_units
  else
    warn "未找到 systemctl，跳过 systemd 服务停止。"
  fi
  safe_rm_file "$EASYTIER_RELAY_SERVICE" "$NFT_SERVICE" "$DDNS_SERVICE" "$DDNS_TIMER" "/etc/systemd/system/leikwan-mss-clamp.service"
  if command -v nft >/dev/null 2>&1; then
    nft delete table inet leikwan_forward 2>/dev/null || true
    nft delete table inet lq_mss 2>/dev/null || true
  fi
  cleanup_leikwan_policy_routes
  safe_rm_file "$EASYTIER_CORE_BIN" "$EASYTIER_CLI_BIN" "$SHORTCUT_LQ" "$SHORTCUT_LQ_UPPER" \
    "/root/leikwan-toolkit.sh" "$OLD_ROOT_SCRIPT" "$FORWARD_SYSCTL" "$BBR_SYSCTL_CONF" "$DNS_RESOLVED_CONF" "$LOG_FILE" "$OLD_LOG_FILE" "$DDNS_LOG_FILE"
  rm -rf /tmp/leikwan-update.* 2>/dev/null || true
  safe_rm_dir "$STATE_DIR" "$OLD_STATE_DIR" "$BACKUP_DIR" "$OLD_BACKUP_DIR"
  rm -f "$LOG_FILE" "$OLD_LOG_FILE" 2>/dev/null || true
  systemd_reload_reset_failed
  set -e

  echo
  echo "${BOLD}卸载检查结果${RESET}"
  uninstall_check_line "nftables 转发表" nft leikwan_forward
  uninstall_check_line "旧 MSS 临时表" nft lq_mss
  uninstall_check_line "EasyTier relay 服务" service "${EASYTIER_RELAY_SERVICE_NAME}.service"
  uninstall_check_line "nft 持久化服务" service "${NFT_SERVICE_NAME}.service"
  uninstall_check_line "DDNS refresh 服务" service "${DDNS_SERVICE_NAME}.service"
  uninstall_check_line "DDNS refresh timer" file "$DDNS_TIMER"
  uninstall_check_line "MSS clamp 旧服务" service "leikwan-mss-clamp.service"
  uninstall_check_line "EasyTier core" file "$EASYTIER_CORE_BIN"
  uninstall_check_line "EasyTier cli" file "$EASYTIER_CLI_BIN"
  uninstall_check_line "快捷命令 lq" file "$SHORTCUT_LQ"
  uninstall_check_line "快捷命令 LQ" file "$SHORTCUT_LQ_UPPER"
  uninstall_check_command_absent "command -v lq" lq
  uninstall_check_command_absent "command -v LQ" LQ
  uninstall_check_line "主脚本" file "/root/leikwan-toolkit.sh"
  uninstall_check_line "历史主脚本路径" file "$OLD_ROOT_SCRIPT"
  uninstall_check_line "配置目录" dir "$STATE_DIR"
  uninstall_check_line "旧配置目录" dir "$OLD_STATE_DIR"
  uninstall_check_line "备份目录" dir "$BACKUP_DIR"
  uninstall_check_line "旧备份目录" dir "$OLD_BACKUP_DIR"
  uninstall_check_line "日志文件" file "$LOG_FILE"
  uninstall_check_line "旧日志文件" file "$OLD_LOG_FILE"
  uninstall_check_line "DDNS 日志文件" file "$DDNS_LOG_FILE"
  uninstall_check_line "IPv4 转发 sysctl" file "$FORWARD_SYSCTL"
  uninstall_check_line "BBR sysctl" file "$BBR_SYSCTL_CONF"
  uninstall_check_line "DNS resolved 配置" file "$DNS_RESOLVED_CONF"
  ok "卸载流程已完成；如上方有 WARN，表示对应对象仍存在，需要按提示手动检查。"
  rm -f "$LOG_FILE" "$OLD_LOG_FILE" 2>/dev/null || true
}

snapshot_timestamp() {
  date '+%Y%m%d-%H%M%S'
}

snapshot_copy_path() {
  local stage="$1" path="$2" dest
  [[ -e "$path" ]] || return 0
  dest="${stage}${path}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$path" "$dest"
}

snapshot_collect_runtime_info() {
  local stage="$1"
  local info_dir="${stage}${STATE_DIR}/snapshot-info"
  mkdir -p "$info_dir"
  {
    echo "leikwan-toolkit ${TOOL_VERSION}"
    echo "created_at=$(status_now)"
  } >"${info_dir}/manifest.txt"
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset >"${info_dir}/nft-ruleset.txt" 2>&1 || true
  else
    echo "nft command not found" >"${info_dir}/nft-ruleset.txt"
  fi
  if command -v ip >/dev/null 2>&1; then
    ip rule show >"${info_dir}/ip-rule-show.txt" 2>&1 || true
    ip route show table all >"${info_dir}/ip-route-show-table-all.txt" 2>&1 || true
  else
    echo "ip command not found" >"${info_dir}/ip-rule-show.txt"
    echo "ip command not found" >"${info_dir}/ip-route-show-table-all.txt"
  fi
}

create_snapshot_archive() {
  local dest="$1" tmp stage svc
  tmp="$(mktemp -d)"
  stage="${tmp}/root"
  mkdir -p "$stage"
  if [[ -d "$STATE_DIR" ]]; then
    tar --exclude='etc/leikwan-toolkit/snapshots' -C / -cf - etc/leikwan-toolkit 2>/dev/null | tar -C "$stage" -xf - 2>/dev/null || true
  else
    mkdir -p "${stage}${STATE_DIR}"
  fi
  snapshot_copy_path "$stage" "$EASYTIER_RELAY_SERVICE"
  while IFS= read -r svc; do
    snapshot_copy_path "$stage" "$svc"
  done < <(find /etc/systemd/system -maxdepth 1 -type f -name 'easytier-entry-*.service' 2>/dev/null || true)
  snapshot_copy_path "$stage" "$NFT_SERVICE"
  snapshot_copy_path "$stage" "$FORWARD_SYSCTL"
  snapshot_copy_path "$stage" "$BBR_SYSCTL_CONF"
  snapshot_copy_path "$stage" "$PBR_RT_TABLES"
  snapshot_collect_runtime_info "$stage"
  mkdir -p "$(dirname "$dest")"
  tar -czf "$dest" -C "$stage" .
  rm -rf "$tmp"
}

create_snapshot() {
  need_root_unless_dry_run
  local dest
  echo "[WARN] 快照可能包含 EasyTier network secret，请妥善保存。"
  dest="${SNAPSHOT_DIR}/snapshot-$(snapshot_timestamp).tar.gz"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] create snapshot ${dest}"
    return 0
  fi
  ensure_base_dirs
  create_snapshot_archive "$dest"
  ok "已创建配置快照：${dest}"
}

snapshot_files() {
  {
    find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name 'snapshot-*.tar.gz' 2>/dev/null || true
    find "$AUTO_SNAPSHOT_DIR" -maxdepth 1 -type f -name 'auto-before-*.tar.gz' 2>/dev/null || true
  } | sort
}

latest_snapshot_file() {
  {
    find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name 'snapshot-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null || true
    find "$AUTO_SNAPSHOT_DIR" -maxdepth 1 -type f -name 'auto-before-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null || true
  } | sort -nr | awk 'NR==1 {sub(/^[^ ]+ /, ""); print}'
}

list_snapshots() {
  local files=() i file size
  mapfile -t files < <(snapshot_files)
  if (( ${#files[@]} == 0 )); then
    warn "当前没有快照。"
    return 0
  fi
  echo "配置快照列表"
  echo "----------------------------------------"
  i=0
  for file in "${files[@]}"; do
    i=$((i + 1))
    size="$(du -h "$file" 2>/dev/null | awk '{print $1}')"
    printf '%d. %s (%s)\n' "$i" "$file" "${size:-unknown}"
  done
}

select_snapshot_by_number() {
  local prompt="${1:-请输入快照编号，直接回车返回}" files=() choice
  mapfile -t files < <(snapshot_files)
  if (( ${#files[@]} == 0 )); then
    warn "当前没有快照。"
    return 1
  fi
  list_snapshots
  choice="$(prompt_value "$prompt")"
  [[ -n "$choice" ]] || return 1
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
    printf '%s' "${files[$((choice - 1))]}"
    return 0
  fi
  warn "快照编号无效：${choice}"
  return 1
}

restart_restored_services() {
  local svc
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "未找到 systemctl，跳过服务重启。"
    return 0
  fi
  systemctl daemon-reload || warn "systemd daemon-reload 失败。"
  [[ -f "$EASYTIER_RELAY_SERVICE" ]] && systemctl restart "${EASYTIER_RELAY_SERVICE_NAME}.service" || true
  while IFS= read -r svc; do
    systemctl restart "$(basename "$svc")" || warn "重启 $(basename "$svc") 失败。"
  done < <(find /etc/systemd/system -maxdepth 1 -type f -name 'easytier-entry-*.service' 2>/dev/null || true)
  [[ -f "$NFT_SERVICE" ]] && systemctl restart "${NFT_SERVICE_NAME}.service" || true
}

restore_snapshot() {
  need_root_unless_dry_run
  local path="${1:-}"
  [[ -n "$path" ]] || path="$(select_snapshot_by_number "请输入要恢复的快照编号")" || return 0
  if [[ ! -f "$path" ]]; then
    [[ "$path" == *.tar.gz ]] || { warn "快照不存在：${path}"; return 0; }
  fi
  [[ -f "$path" ]] || { warn "文件不存在：${path}"; return 0; }
  echo "[WARN] 恢复快照会覆盖当前 leikwan 配置和相关 systemd/nftables 状态。"
  prompt_yes_no "确认恢复？" "N" || return 0
  auto_snapshot_or_confirm "restore-snapshot" || return 0
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] tar -xzf ${path} -C /"
    return 0
  fi
  tar -xzf "$path" -C /
  ok "快照已恢复：${path}"
  if prompt_yes_no "是否立即重新加载 systemd 并重启相关服务？" "N"; then
    restart_restored_services
  else
    info "已跳过服务重启。请按需手动执行 systemctl daemon-reload / restart。"
  fi
}

delete_snapshot() {
  need_root_unless_dry_run
  local path
  path="$(select_snapshot_by_number "请输入要删除的快照编号")" || return 0
  prompt_yes_no "确认删除快照 ${path}？" "N" || return 0
  (( DRY_RUN == 1 )) && { echo "[DRY-RUN] rm -f ${path}"; return 0; }
  rm -f "$path"
  ok "已删除快照：${path}"
}

export_latest_snapshot() {
  need_root_unless_dry_run
  local latest dest ts
  latest="$(latest_snapshot_file)"
  [[ -n "$latest" && -f "$latest" ]] || { warn "当前没有可导出的快照。"; return 0; }
  ts="$(snapshot_timestamp)"
  dest="/root/leikwan-snapshot-${ts}.tar.gz"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] cp -a ${latest} ${dest}"
    return 0
  fi
  cp -a "$latest" "$dest"
  ok "已导出最新快照：${dest}"
}

prune_auto_snapshots() {
  local old=() file
  mapfile -t old < <(find "$AUTO_SNAPSHOT_DIR" -maxdepth 1 -type f -name 'auto-before-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR>10 {sub(/^[^ ]+ /, ""); print}')
  for file in "${old[@]}"; do
    rm -f "$file" 2>/dev/null || true
  done
}

auto_snapshot_or_confirm() {
  local action="$1" safe_action dest
  need_root_unless_dry_run
  safe_action="$(safe_name "$action")"
  dest="${AUTO_SNAPSHOT_DIR}/auto-before-${safe_action}-$(snapshot_timestamp).tar.gz"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] create auto snapshot ${dest}"
    return 0
  fi
  ensure_base_dirs
  if create_snapshot_archive "$dest"; then
    ok "已创建自动快照：${dest}"
    prune_auto_snapshots
    return 0
  fi
  warn "自动快照失败，建议先手动创建快照。"
  prompt_yes_no "是否继续？" "N"
}

snapshot_menu() {
  local choice
  while true; do
    print_menu_header "配置快照 / 回滚"
    echo "1. 创建当前完整快照"
    echo "2. 查看快照列表"
    echo "3. 恢复指定快照"
    echo "4. 删除旧快照"
    echo "5. 导出最新快照到 /root"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause create_snapshot ;;
      2) run_menu_action_pause list_snapshots ;;
      3) run_menu_action_pause restore_snapshot ;;
      4) run_menu_action_pause delete_snapshot ;;
      5) run_menu_action_pause export_latest_snapshot ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

backup_snapshot() {
  create_snapshot "$@"
}

snapshot_restore_legacy() {
  restore_snapshot "$@"
}

backup_restore_menu() {
  snapshot_menu "$@"
}

easytier_menu() {
  local choice
  while true; do
    print_menu_header "EasyTier 组网管理"
    echo "1. 安装 / 修复 EasyTier"; echo "2. B 生成网络码"; echo "3. A 粘贴网络码并部署入口"; echo "4. B 粘贴入口码并完成接入"; echo "5. 启动 / 重启 entry 服务"; echo "6. 启动 / 重启 relay 服务"; echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action install_easytier_binary repair ;;
      2) run_menu_action quick_generate_network_pairing ;;
      3) run_menu_action quick_deploy_entry_from_network_pairing ;;
      4) run_menu_action quick_deploy_relay_from_entry_pairing ;;
      5) run_menu_action apply_easytier_entry_services ;;
      6) run_menu_action apply_easytier_relay_service ;;
      0) return 0 ;;
    esac
  done
}

entries_menu() {
  local choice
  while true; do
    print_menu_header "公网入口列表管理（B 侧）"
    echo "1. 生成新公网入口接入码"
    echo "2. 粘贴公网入口返回码并接入"
    echo "3. 手动添加公网入口（高级）"
    echo "4. 修改公网入口详情"
    echo "5. 删除公网入口"
    echo "6. 启用 / 禁用公网入口"
    echo "7. 修改公网入口权重"
    echo "8. 查看所有公网入口"
    echo "9. 测试公网入口"
    echo "10. 切换主公网入口"
    echo "11. 批量启用 / 禁用公网入口"
    echo "12. 查看 / 清理未完成接入码"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action quick_generate_network_pairing ;;
      2) run_menu_action quick_deploy_relay_from_entry_pairing ;;
      3) run_menu_action_pause add_entry ;;
      4) run_menu_action_pause edit_entry ;;
      5) run_menu_action_pause delete_entry ;;
      6) run_menu_action_pause set_entry_enabled ;;
      7) run_menu_action_pause set_entry_weight ;;
      8) run_menu_action_pause list_entries ;;
      9) run_menu_action_pause test_entries ;;
      10) run_menu_action_pause switch_primary_entry ;;
      11) bulk_entry_enable_menu ;;
      12) pending_entries_menu ;;
      13|0) return 0 ;;
    esac
  done
}

forwards_menu() {
  local choice
  while true; do
    print_menu_header "转发目标管理"
    echo "1. 添加转发目标"
    echo "2. 修改转发目标"
    echo "3. 删除转发目标"
    echo "4. 查看转发目标"
    echo "5. 启用 / 禁用转发目标"
    echo "6. 重新应用利群转发规则"
    echo "7. 解析 target_host"
    echo "8. 测试单个转发目标"
    echo "9. 导入 forwards.tsv（高级）"
    echo "10. 导出 forwards.tsv"
    echo "11. 生成转发入口输出"
    echo "12. DDNS 后端自动刷新"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause add_forward ;;
      2) run_menu_action_pause edit_forward ;;
      3) run_menu_action_pause delete_forward ;;
      4) run_menu_action_pause list_forwards ;;
      5) run_menu_action_pause set_forward_enabled ;;
      6) apply_relay_rules_menu ;;
      7) run_menu_action_pause resolve_forward_targets_action ;;
      8) run_menu_action_pause test_forward ;;
      9) run_menu_action_pause import_forwards_tsv ;;
      10) run_menu_action_pause export_forwards_tsv ;;
      11) run_menu_action generate_forward_outputs ;;
      12) ddns_menu ;;
      0) return 0 ;;
    esac
  done
}

pbr_menu() {
  local choice
  while true; do
    print_menu_header "IPv4 多出口策略路由 / PBR"
    echo "1. 添加静态 PBR"
    echo "2. 从现有转发目标添加 PBR"
    echo "3. 删除 PBR 规则"
    echo "4. 应用 PBR"
    echo "5. 查看 PBR"
    echo "6. 域名 PBR 管理"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action_pause pbr_add_static ;;
      2) run_menu_action_pause pbr_add_from_forward ;;
      3) run_menu_action_pause delete_pbr_rule ;;
      4) run_menu_action_pause pbr_apply ;;
      5) run_menu_action_pause pbr_show ;;
      6) pbr_domain_menu ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

install_shortcuts() {
  need_root_unless_dry_run
  local script_path content
  if [[ -f /root/leikwan-toolkit.sh ]]; then
    script_path="$(readlink -f /root/leikwan-toolkit.sh 2>/dev/null || printf '%s' /root/leikwan-toolkit.sh)"
  else
    script_path="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
  fi
  content="#!/usr/bin/env bash
# Managed by leikwan-toolkit
exec bash ${script_path@Q} \"\$@\""
  install_shortcut_if_needed "$SHORTCUT_LQ" "$script_path" "$content"
  install_shortcut_if_needed "$SHORTCUT_LQ_UPPER" "$script_path" "$content"
}

shortcut_is_current() {
  local shortcut="$1" script_path="$2" content="$3" tmp rc
  if [[ -L "$shortcut" ]]; then
    [[ "$(readlink -f "$shortcut" 2>/dev/null || true)" == "$script_path" ]]
    return
  fi
  [[ -f "$shortcut" ]] || return 1
  tmp="$(mktemp)"
  printf '%s\n' "$content" >"$tmp"
  cmp -s "$tmp" "$shortcut"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

install_shortcut_if_needed() {
  local shortcut="$1" script_path="$2" content="$3"
  if shortcut_is_current "$shortcut" "$script_path" "$content"; then
    return 0
  fi
  if [[ -L "$shortcut" ]]; then
    backup_file "$shortcut"
    (( DRY_RUN == 1 )) || rm -f "$shortcut"
  fi
  write_file "$shortcut" "$content" 755
}

print_quick_networking_steps() {
  cat <<'EOF'
完整分步说明
----------------------------------------
步骤 0：利群主机先修复 DNS / IPv4 优先
在 B 利群主机执行：
主菜单 -> 快速组网（分步提示） -> 1

步骤 1：利群主机生成网络码
在 B 利群主机执行：
主菜单 -> 快速组网（分步提示） -> 2
脚本会读取 entries.tsv，自动推荐下一个不冲突的公网入口名称、EasyTier IP 和 8000-9000 内监听端口。
复制输出的 NETWORK 网络码。

步骤 2：公网入口加入网络
在 A 公网入口机执行：
主菜单 -> 快速组网（分步提示） -> 3
粘贴 B 生成的 NETWORK 网络码。
完成后复制 A 输出的 ENTRY 入口码。

步骤 3：利群主机完成接入
在 B 利群主机执行：
主菜单 -> 快速组网（分步提示） -> 4
粘贴 A 生成的 ENTRY 入口码。

步骤 4：公网入口配置端口池
在 A 公网入口机执行：
主菜单 -> 快速组网（分步提示） -> 5
小白常用范围可以先填：
10001-10020 -> 10.198.1.1

默认范围仍可使用：
10000-19999 -> 10.198.1.1

步骤 5：如需指定 CN2 / 9929 出口，利群主机先配置 PBR
在 B 利群主机执行：
主菜单 -> 快速组网（分步提示） -> 7
如果不需要 PBR，本步骤可以跳过。

步骤 6：利群主机添加后端转发目标
在 B 利群主机执行：
主菜单 -> 快速组网（分步提示） -> 6
例如：
10001 -> 后端IP:后端端口

如果先添加了转发目标，后添加 PBR，需要重新执行：
lq forward apply-relay --auto-fix-route

步骤 7：A/B 两边执行一键诊断
A 和 B 都执行：
主菜单 -> 一键诊断

步骤 8：外部机器测试公网入口端口
nc -vz -w 5 A_PUBLIC_IP 10001

新增第二台公网入口：
- B 执行第 2 项，脚本会自动推荐新的 EasyTier IP 和监听端口。
- 新 A 执行第 3 项，粘贴网络码。
- 新 A 执行第 5 项，配置端口池。
- B 执行第 4 项，粘贴 A 返回码。
- B 执行 利群主机 -> 公网入口列表管理 查看 / 测试。

确认：
- EasyTier active
- ping 对端成功
- nftables DNAT 存在
- TCP MSS clamp enabled: 1320
----------------------------------------
EOF
}

quick_networking_menu() {
  local choice intro_shown=0
  while true; do
    clear_screen_if_interactive
    if (( intro_shown == 0 )); then
      print_compact_header "快速组网"
      echo "B：利群主机，负责中转和后端转发"
      echo "A：公网入口，可部署多台，用于接入公网流量"
      echo "C：后端目标，支持 TCP/UDP 转发"
      echo "----------------------------------------"
      intro_shown=1
    else
      print_compact_header "快速组网"
    fi
    echo "1. B：修复 DNS / IPv4"
    echo "2. B：生成公网入口网络码"
    echo "3. A：粘贴网络码部署入口"
    echo "4. B：粘贴入口返回码完成接入"
    echo "5. A：配置入口端口池"
    echo "6. B：添加后端转发目标"
    echo "7. B：IPv4 PBR"
    echo "8. 查看完整说明"
    echo "0. 返回"
    echo
    echo "提示：后端需要指定出口时，先配置 PBR，再添加或重应用转发目标。"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action fix_dns_ipv4_first || warn_and_pause "DNS / IPv4 优先修复未完成，请查看上方提示后重试。" ;;
      2) run_menu_action quick_generate_network_pairing || warn_and_pause "生成 EasyTier 网络码未完成，请查看上方提示后重试。" ;;
      3) run_menu_action quick_deploy_entry_from_network_pairing || warn_and_pause "公网入口部署未完成，请查看上方提示后重试。" ;;
      4) run_menu_action quick_deploy_relay_from_entry_pairing || warn_and_pause "利群主机接入未完成，请查看上方提示后重试。" ;;
      5) run_menu_action entry_expose_range || warn_and_pause "公网入口端口池配置未完成，请查看上方提示后重试。" ;;
      6) run_menu_action add_forward || warn_and_pause "后端转发目标添加未完成，请查看上方提示后重试。" ;;
      7) pbr_menu ;;
      8) echo; print_quick_networking_steps; wait_enter_to_return ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

relay_host_menu() {
  local choice
  while true; do
    print_menu_header "利群主机"
    echo "1. EasyTier 组网管理"
    echo "2. 公网入口列表管理"
    echo "3. 转发目标管理"
    echo "4. IPv4 多出口策略路由"
    echo "5. IPv6 入站安全收口"
    echo "6. 查看状态总览"
    echo "7. 一键诊断"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) easytier_menu ;;
      2) entries_menu ;;
      3) forwards_menu ;;
      4) pbr_menu ;;
      5) run_menu_action_pause ipv6_lockdown ;;
      6) run_menu_action_pause status_overview ;;
      7) run_menu_action run_doctor_interactive ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

entry_host_menu() {
  local choice
  while true; do
    print_menu_header "公网入口（A 本机）"
    echo "1. 粘贴利群网络码，部署本机入口"
    echo "2. 配置本机入口端口池"
    echo "3. 查看状态总览"
    echo "4. 一键诊断"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) run_menu_action quick_deploy_entry_from_network_pairing ;;
      2) run_menu_action_pause entry_expose_range ;;
      3) run_menu_action_pause status_overview ;;
      4)
        if [[ "$(detect_role)" == "leikwan-relay" ]]; then
          warn "当前机器检测为利群主机，不是公网入口机。"
          warn "如需管理已接入的公网入口列表，请进入：利群主机 -> 公网入口列表管理"
        else
          run_doctor_interactive
        fi
        wait_enter_to_return
        ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

advanced_menu() {
  local choice
  while true; do
    print_menu_header "高级功能"
    echo "1. nftables 规则管理"
    echo "2. 链路测试"
    echo "3. DNS / IPv4 优先修复"
    echo "4. BBR / 系统优化"
    echo "5. 状态总览"
    echo "6. 一键诊断"
    echo "7. 配置快照 / 回滚"
    echo "8. 配置导入 / 导出"
    echo "9. 端口冲突预检"
    echo "10. 生成脱敏故障报告"
    echo "11. 检查并更新脚本"
    echo "12. legacy 清理"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) nftables_menu ;;
      2) link_test_menu ;;
      3) run_menu_action fix_dns_ipv4_first || warn_and_pause "DNS / IPv4 优先修复未完成，请查看上方提示后重试。" ;;
      4) bbr_menu ;;
      5) run_menu_action_pause status_overview ;;
      6) run_menu_action run_doctor_interactive ;;
      7) snapshot_menu ;;
      8) config_menu ;;
      9) run_menu_action_pause port_check ;;
      10) run_menu_action generate_debug_report ;;
      11) update_menu ;;
      12) legacy_cleanup_menu ;;
      0) return 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

main_menu() {
  need_root_unless_dry_run
  install_shortcuts || true
  ensure_tsv_files
  local choice
  while true; do
    clear_screen_if_interactive
    print_banner
    echo "1. 快速组网（分步提示）"
    echo "2. 利群主机"
    echo "3. 公网入口"
    echo "4. 高级功能"
    echo "5. 状态总览"
    echo "6. 一键诊断"
    echo "7. 卸载全部"
    echo "0. 退出"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) quick_networking_menu ;;
      2) relay_host_menu ;;
      3) entry_host_menu ;;
      4) advanced_menu ;;
      5) run_menu_action_pause status_overview ;;
      6) run_menu_action run_doctor_interactive ;;
      7) uninstall_new_mode ;;
      0) exit 0 ;;
      "") menu_input_required ;;
      *) menu_invalid_choice ;;
    esac
  done
}

main() {
  while [[ "${1:-}" == "--dry-run" ]]; do DRY_RUN=1; shift; done
  case "${1:-}" in
    status)
      status_overview
      ;;
    config)
      case "${2:-}" in
        export) shift 2; config_export "$@" ;;
        import) shift 2; config_import "$@" ;;
        inspect) config_inspect "${3:-}" ;;
        list) config_list ;;
        *) fail "未知 config 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    export-config)
      shift
      config_export "$@"
      ;;
    import-config)
      shift
      config_import "$@"
      ;;
    output)
      case "${2:-}" in
        generate) generate_forward_outputs ;;
        show) output_show ;;
        json) output_json ;;
        html) output_html ;;
        qr) output_qr ;;
        *) fail "未知 output 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    pair)
      case "${2:-}" in
        relay-init) quick_generate_network_pairing ;;
        entry-join) quick_deploy_entry_from_network_pairing "${3:-}" ;;
        relay-join) quick_deploy_relay_from_entry_pairing "${3:-}" ;;
        status) pairing_status ;;
        *) fail "未知 pair 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    forward)
      case "${2:-}" in
        add) add_forward ;;
        edit) edit_forward "${3:-}" ;;
        delete) delete_forward "${3:-}" ;;
        export) export_forward_code_by_name "${3:-}" ;;
        import) warn "forward import 已降级为高级兼容；默认请在 A 执行 lq entry expose-range，一次性配置入口端口池。"; import_forward_code "${3:-}" ;;
        list) list_forwards ;;
        apply-relay)
          if [[ "${3:-}" == "--auto-fix-route" ]]; then
            apply_nft_rules "leikwan-relay" 1
          else
            apply_nft_rules "leikwan-relay"
          fi
          ;;
        *) fail "未知 forward 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    entry)
      case "${2:-}" in
        expose-range) shift 2; entry_expose_range "$@" ;;
        *) fail "未知 entry 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    port)
      case "${2:-}" in
        check) port_check ;;
        *) fail "未知 port 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    pbr)
      case "${2:-}" in
        delete) delete_pbr_rule "${3:-}" ;;
        apply) pbr_apply ;;
        show|list) pbr_show ;;
        sync-from-forwards) shift 2; pbr_sync_from_forwards "$@" ;;
        domain)
          case "${3:-}" in
            add) pbr_domain_add ;;
            list|show) pbr_domain_list ;;
            delete) pbr_domain_delete ;;
            sync) shift 3; pbr_domain_sync "$@" ;;
            *) fail "未知 pbr domain 子命令：${3:-}"; print_help; exit 1 ;;
          esac
          ;;
        *) fail "未知 pbr 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    ddns)
      case "${2:-}" in
        run) shift 2; ddns_refresh_once "$@" ;;
        status) ddns_status ;;
        enable) ddns_enable_timer ;;
        disable) ddns_disable_timer ;;
        logs) ddns_logs ;;
        *) fail "未知 ddns 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    update)
      case "${2:-}" in
        check) update_check || exit $? ;;
        run) update_run || exit $? ;;
        status) update_status || exit $? ;;
        rollback) update_rollback || exit $? ;;
        *) fail "未知 update 子命令：${2:-}"; print_help; exit 1 ;;
      esac
      ;;
    --help|-h) print_help ;;
    --version|-v) echo "${PROJECT_NAME} ${TOOL_VERSION}" ;;
    --status) status_overview ;;
    --port-check) port_check ;;
    --doctor|--validate) [[ "${2:-}" == "--verbose" ]] && VERBOSE_DOCTOR=1; doctor ;;
    --self-update) update_run 1 || exit $? ;;
    --update-check) update_check || exit $? ;;
    --ddns-run) shift; ddns_refresh_once "$@" ;;
    --pbr-apply) pbr_apply ;;
    --pbr-delete) delete_pbr_rule "${2:-}" ;;
    --uninstall) uninstall_new_mode ;;
    "") main_menu ;;
    *) fail "未知参数：$1"; print_help; exit 1 ;;
  esac
}

main "$@"
