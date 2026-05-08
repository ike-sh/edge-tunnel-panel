#!/usr/bin/env bash
set -Eeuo pipefail

TOOL_VERSION="0.4.0-alpha"
PROJECT_NAME="leikwan-toolkit"
PROJECT_TITLE="利群快速组网工具"
PROJECT_AUTHOR="ike-sh"
PROJECT_GITHUB="https://github.com/ike-sh/leikwan-toolkit"

DRY_RUN=0
VERBOSE_DOCTOR=0
DEPS_APT_UPDATED=0
DEPS_INSTALLED_THIS_RUN=""

LOG_FILE="/var/log/leikwan-toolkit.log"
STATE_DIR="/etc/leikwan-toolkit"
BACKUP_DIR="/var/backups/leikwan-toolkit"
OLD_LOG_FILE="/var/log/leikwan-wg-toolkit.log"
OLD_STATE_DIR="/etc/leikwan-wg-toolkit"
OLD_BACKUP_DIR="/var/backups/leikwan-wg-toolkit"
OUTPUT_DIR="${STATE_DIR}/outputs"
NFT_DIR="${STATE_DIR}/nft"
ENTRY_DIR="${STATE_DIR}/entry"
ENTRIES_DIR="${STATE_DIR}/entries"
FORWARDS_DIR="${STATE_DIR}/forwards"
PBR_DIR="${STATE_DIR}/pbr"
EASYTIER_DIR="${STATE_DIR}/easytier"
REPORT_FILE="/root/leikwan-debug-report.txt"

ENTRIES_TSV="${ENTRIES_DIR}/entries.tsv"
FORWARDS_TSV="${FORWARDS_DIR}/forwards.tsv"
RESOLVED_TSV="${FORWARDS_DIR}/resolved.tsv"
FORWARD_TXT="${OUTPUT_DIR}/forward-endpoints.txt"
FORWARD_TSV="${OUTPUT_DIR}/forward-endpoints.tsv"
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
EASYTIER_RELAY_SERVICE_NAME="easytier-relay"
EASYTIER_RELAY_SERVICE="/etc/systemd/system/${EASYTIER_RELAY_SERVICE_NAME}.service"

NFT_RULE_FILE="${NFT_DIR}/leikwan-forward.nft"
MSS_CONFIG="${NFT_DIR}/mss.env"
NFT_SERVICE_NAME="leikwan-nft-forward"
NFT_SERVICE="/etc/systemd/system/${NFT_SERVICE_NAME}.service"
FORWARD_SYSCTL="/etc/sysctl.d/99-leikwan-forward.conf"

PBR_STATIC_CONF="${PBR_DIR}/static-routes.conf"
PBR_RT_TABLES="/etc/iproute2/rt_tables"
PBR_PRIORITY="15000"

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
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "请输入 y 或 n。" ;;
    esac
  done
}

is_interactive() {
  [[ -t 0 && -t 1 ]]
}

is_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
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
  name="${name// /-}"
  name="$(printf '%s' "$name" | sed -E 's/[^A-Za-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$name" ]] || name="default"
  printf '%s' "$name"
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
╔════════════════════════════════════════════════════════════════════╗
║ Leikwan Toolkit                                                   ║
║ ${PROJECT_TITLE}                                                  ║
║ Author : ${PROJECT_AUTHOR}                                                   ║
║ Version: ${TOOL_VERSION}                                              ║
║ GitHub : ${PROJECT_GITHUB}             ║
╚════════════════════════════════════════════════════════════════════╝
EOF
}

print_help() {
  cat <<EOF
${PROJECT_NAME} ${TOOL_VERSION}

用法：
  sudo bash leikwan-toolkit.sh
  sudo bash leikwan-toolkit.sh --doctor
  sudo bash leikwan-toolkit.sh --doctor --verbose
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
  sudo bash leikwan-toolkit.sh --pbr-apply
  sudo bash leikwan-toolkit.sh --uninstall
  bash leikwan-toolkit.sh --help
  bash leikwan-toolkit.sh --version

定位：
  公网入口 + 利群主机 + 后端目标的三段 TCP 转发组网工具。
  传输层使用 EasyTier，转发层使用 nftables。
  默认 EasyTier 虚拟网段：${ET_NET}，relay：${RELAY_ET_IP}。
  默认 EasyTier TCP 端口：${DEFAULT_EASYTIER_PORT}，位于利群推荐白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}。
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
    install -d -m 700 "$STATE_DIR" "$ENTRY_DIR" "$ENTRIES_DIR" "$FORWARDS_DIR" "$OUTPUT_DIR" "$NFT_DIR" "$PBR_DIR" "$EASYTIER_DIR"
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
    apt-get update
    DEPS_APT_UPDATED=1
  fi
  apt-get install -y "${missing[@]}"
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
  [[ -f "$FORWARDS_TSV" ]] || write_file "$FORWARDS_TSV" $'# name\tentry_port\ttarget_host\ttarget_port\tout_iface\troute_table\tenabled\tcomment' 600
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

archive_integrity_ok() {
  local archive="$1"
  unzip -tqq "$archive" >/dev/null 2>&1 || tar -tzf "$archive" >/dev/null 2>&1
}

download_large_archive_checked() {
  local raw_url="$1" dest_file="$2" candidate part size_mb
  part="${dest_file}.part"
  rm -f "$part"
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
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
      if ! archive_integrity_ok "$part"; then
        dl_warn "压缩包完整性校验失败，继续尝试下一个地址。"
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
  while IFS= read -r path; do
    [[ -f "$path" ]] && files+=("$path")
  done < <(find /root . -maxdepth 1 -type f \( -name 'easytier*.tar.gz' -o -name 'easytier*.zip' \) 2>/dev/null | sort -u)
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
      if ! archive_integrity_ok "$path"; then
        fail "本地 EasyTier 包完整性校验失败：${path}"
        return 1
      fi
      cp -a "$path" "$dest"
      return 0
    fi
  fi
  path="$(prompt_value "请输入本地 EasyTier zip/tar.gz 路径，留空取消" "")"
  [[ -n "$path" && -f "$path" ]] || return 1
  if (( $(wc -c <"$path") < 10485760 )); then
    fail "本地 EasyTier 包小于 10MB，疑似半截文件：${path}"
    return 1
  fi
  if ! archive_integrity_ok "$path"; then
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
  printf '%s\n' "- 手动下载 EasyTier zip 后输入本地路径" >&2
  choose_local_easytier_archive "$dest" || { fail "未提供可用 EasyTier 安装包。"; return 1; }
}

extract_archive() {
  local archive="$1" dest="$2"
  case "$archive" in
    *.zip) unzip -q "$archive" -d "$dest" ;;
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" ;;
    *) tar -xzf "$archive" -C "$dest" 2>/dev/null || unzip -q "$archive" -d "$dest" ;;
  esac
}

archive_listing() {
  local archive="$1"
  case "$archive" in
    *.zip) unzip -l "$archive" 2>/dev/null | sed -n '1,50p' ;;
    *) tar -tzf "$archive" 2>/dev/null | sed -n '1,50p' || unzip -l "$archive" 2>/dev/null | sed -n '1,50p' ;;
  esac
}

install_easytier_binary() {
  if [[ -x "$EASYTIER_CORE_BIN" && -x "$EASYTIER_CLI_BIN" ]] && easytier_validate_help; then
    if prompt_yes_no "检测到可用 EasyTier 二进制，是否复用？" "Y"; then
      ok "复用已安装 EasyTier。"
      return 0
    fi
  fi
  install_packages curl jq ca-certificates tar unzip
  local tmpdir archive core cli list
  confirm_summary "EasyTier 安装摘要" "版本：${EASYTIER_VERSION}\n目标：${EASYTIER_CORE_BIN} / ${EASYTIER_CLI_BIN}\n下载：LEIKWAN_GITHUB_MIRRORS / 内置镜像 / 官方 GitHub 轮询 + 本地包 fallback" || return 0
  (( DRY_RUN == 1 )) && return 0
  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/easytier.pkg"
  download_easytier_archive "$archive" || { rm -rf "$tmpdir"; return 1; }
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
  local name="$1" et_ip="$2" proto="$3" port="$4" args listener
  args="$(core_common_args "$et_ip")" || return 1
  confirm_easytier_port "$port" || return 1
  easytier_help_has '--listeners' || { fail "当前 easytier-core 不支持 --listeners"; return 1; }
  listener="${proto}://0.0.0.0:${port}"
  cat <<EOF
# Managed by leikwan-toolkit ${TOOL_VERSION}
[Unit]
Description=Leikwan EasyTier Entry ${name}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EASYTIER_CORE_BIN} ${args}--listeners ${listener}
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
    printf '%s://%s:%s\n' "$proto" "$public_host" "$port"
  done < <(entries_rows)
}

render_relay_service() {
  local args peers listener_args
  peers="$(enabled_entry_peers)"
  args="$(core_common_args "$RELAY_ET_IP" "$peers")" || return 1
  if listener_args="$(easytier_disable_listener_arg)"; then
    :
  else
    easytier_help_has '--listeners' || { fail "当前 easytier-core 不支持禁用 listener，也不支持 --listeners，无法避免默认 11010/11011/11012。"; return 1; }
    listener_args="$(printf '%q ' --listeners "${EASYTIER_PROTOCOL_DEFAULT}://0.0.0.0:${DEFAULT_EASYTIER_PORT}")"
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
  local title="$1" begin="$2" end="$3" file="$4" one_line_key="$5"
  echo
  echo "=================================================="
  echo "【${title}】"
  echo "$begin"
  cat "$file"
  echo "$end"
  echo "=================================================="
  echo
  echo "【一行配对码，复制这一行也可以】"
  printf '%s=%s\n' "$one_line_key" "$(pairing_base64 "$file")"
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

machine_has_entry_service() {
  if compgen -G "/etc/systemd/system/easytier-entry-*.service" >/dev/null; then
    return 0
  fi
  systemctl list-unit-files --type=service --no-legend 'easytier-entry-*.service' 2>/dev/null | grep -q .
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
  awk -F'\t' 'NF && $1 !~ /^#/ {print}' "$ENTRIES_TSV"
}

entries_rows_sorted() {
  entries_rows | sort -t$'\t' -k6,6nr -k1,1
}

forwards_rows() {
  [[ -f "$FORWARDS_TSV" ]] || return 0
  awk -F'\t' 'NF && $1 !~ /^#/ {print}' "$FORWARDS_TSV"
}

forwards_rows_usv() {
  forwards_rows | awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} NF>=8 {print $1,$2,$3,$4,$5,$6,$7,$8}'
}

last_resolved_ip_for_forward() {
  local name="$1"
  resolved_rows | awk -F'\t' -v n="$name" '$1==n && $4!="" {print $4; exit}'
}

display_entries() {
  ensure_tsv_files
  local only_enabled="${1:-all}"
  printf '%s\n' "编号  名称            公网地址                 EasyTier IP    协议  端口   权重        启用"
  entries_rows_sorted | awk -F'\t' -v only="$only_enabled" '
    only=="enabled" && $7!="true" {next}
    {
      printf "%d) %-12s %-24s %-14s %-5s %-6s weight=%-5s %s\n", ++i, $1, $2, $3, $4, $5, $6, ($7=="true" ? "enabled" : "disabled")
    }
  '
}

select_entry_name() {
  local only_enabled="${1:-all}" choice name count
  ensure_tsv_files
  count="$(entries_rows | awk -F'\t' -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {c++} END{print c+0}')"
  if (( count == 0 )); then
    warn "当前没有公网入口。"
    return 1
  fi
  display_entries "$only_enabled"
  while true; do
    choice="$(prompt_value "请输入编号或名称，直接回车返回")"
    [[ -z "$choice" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      name="$(entries_rows_sorted | awk -F'\t' -v idx="$choice" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {i++} i==idx {print $1; exit}')"
    else
      name="$(entries_rows | awk -F'\t' -v n="$choice" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} $1==n {print $1; exit}')"
    fi
    if [[ -n "$name" ]]; then
      printf '%s' "$name"
      return 0
    fi
    warn "入口不存在或编号无效：${choice}"
  done
}

display_forwards() {
  local only_enabled="${1:-all}" resolved_source="/dev/null"
  ensure_tsv_files
  resolve_forwards >/dev/null 2>&1 || true
  [[ -f "$RESOLVED_TSV" ]] && resolved_source="$RESOLVED_TSV"
  printf '%s\n' "编号  名称        入口端口  后端目标                                      出口接口  路由表     启用       备注"
  awk -F'\t' -v only="$only_enabled" '
    NR==FNR {
      if ($1 !~ /^#/ && NF >= 4) ip[$1]=$4
      next
    }
    $1 ~ /^#/ || NF < 8 {next}
    only=="enabled" && $7!="true" {next}
    {
      target=$3
      if (ip[$1] != "" && ip[$1] != $3) {
        target=sprintf("%s(%s)", $3, ip[$1])
      }
      printf "%d) %-10s %-8s -> %-43s %-8s %-8s %-9s %s\n", ++i, $1, $2, target ":" $4, ($5!="" ? $5 : "-"), ($6!="" ? $6 : "-"), ($7=="true" ? "enabled" : "disabled"), $8
    }
  ' "$resolved_source" "$FORWARDS_TSV"
}

select_forward_name() {
  local only_enabled="${1:-all}" choice name count
  ensure_tsv_files
  count="$(forwards_rows | awk -F'\t' -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {c++} END{print c+0}')"
  if (( count == 0 )); then
    warn "当前没有转发目标。"
    return 1
  fi
  display_forwards "$only_enabled"
  while true; do
    choice="$(prompt_value "请输入编号或名称，直接回车返回")"
    [[ -z "$choice" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      name="$(forwards_rows | awk -F'\t' -v idx="$choice" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} {i++} i==idx {print $1; exit}')"
    else
      name="$(forwards_rows | awk -F'\t' -v n="$choice" -v only="$only_enabled" 'only=="enabled" && $7!="true"{next} $1==n {print $1; exit}')"
    fi
    if [[ -n "$name" ]]; then
      printf '%s' "$name"
      return 0
    fi
    warn "转发目标不存在或编号无效：${choice}"
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
    if ! forwards_rows | awk -F'\t' -v p="$port" '$2==p {found=1} END{exit !found}'; then
      printf '%s' "$port"
      return 0
    fi
  done
  return 1
}

prompt_forward_entry_port() {
  local current_name="${1:-}" current_port="${2:-}" kind start end recommended default prompt value used_by
  IFS=$'\t' read -r kind start end <<<"$(entry_pool_for_prompt)"
  recommended="$(next_available_forward_entry_port "$start" "$end" 2>/dev/null || true)"
  [[ -n "$recommended" ]] || recommended="$start"
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
    used_by="$(forwards_rows | awk -F'\t' -v p="$value" -v n="$current_name" '$2==p && $1!=n {print $1; exit}')"
    if [[ -n "$used_by" ]]; then
      warn "公网入口端口 ${value} 已被转发目标 ${used_by} 使用。"
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
    if [[ "$nf" != "8" ]]; then
      fail "第 ${line_no} 行字段数错误：期望 8 列，实际 ${nf} 列。"
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

nft_has_dnat_rules() {
  nft list table inet leikwan_forward 2>/dev/null | grep -q ' dnat '
}

nft_has_cloud_dnat() {
  local relay_ip="$1" entry_port="$2"
  nft list table inet leikwan_forward 2>/dev/null |
    grep -Fq "tcp dport ${entry_port} dnat ip to ${relay_ip}:${entry_port}"
}

nft_has_relay_dnat() {
  local entry_port="$1" target_ip="$2" target_port="$3"
  nft list table inet leikwan_forward 2>/dev/null |
    grep -Fq "tcp dport ${entry_port} dnat ip to ${target_ip}:${target_port}"
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
  nft list table inet leikwan_forward 2>/dev/null |
    grep -Fq "tcp option maxseg size set ${mss}"
}

entry_exists() {
  local name="$1"
  entries_rows | awk -F'\t' -v n="$name" '$1==n {found=1} END{exit !found}'
}

forward_exists() {
  local name="$1"
  forwards_rows | awk -F'\t' -v n="$name" '$1==n {found=1} END{exit !found}'
}

next_entry_name() {
  local count candidate n
  count="$(entries_rows | awk 'END{print NR+0}')"
  case "$count" in
    0) candidate="aliyun" ;;
    1) candidate="home" ;;
    *) candidate="entry$((count + 1))" ;;
  esac
  if ! entry_exists "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  n=$((count + 1))
  while true; do
    candidate="entry${n}"
    if ! entry_exists "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
    n=$((n + 1))
  done
}

next_entry_et_ip() {
  local prefix="10.198.1" last ip
  for ((last=2; last<=254; last++)); do
    ip="${prefix}.${last}"
    if ! entries_rows | awk -F'\t' -v ip="$ip" '$3==ip {found=1} END{exit !found}'; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

next_entry_easytier_port() {
  local port
  for ((port=DEFAULT_EASYTIER_PORT; port<=FAST_PORT_RANGE_END; port++)); do
    if ! entries_rows | awk -F'\t' -v p="$port" '$5==p {found=1} END{exit !found}'; then
      printf '%s' "$port"
      return 0
    fi
  done
  for ((port=FAST_PORT_RANGE_START; port<DEFAULT_EASYTIER_PORT; port++)); do
    if ! entries_rows | awk -F'\t' -v p="$port" '$5==p {found=1} END{exit !found}'; then
      printf '%s' "$port"
      return 0
    fi
  done
  return 1
}

validate_unique_entry_fields() {
  local name="$1" et_ip="$2" port="$3" current_name="${4:-}"
  [[ -n "$name" ]] || { warn "公网入口名称不能为空。"; return 1; }
  [[ -n "$et_ip" ]] || { warn "EasyTier IP 不能为空。"; return 1; }
  is_ipv4 "$et_ip" || { warn "EasyTier IP 必须是 IPv4：${et_ip}"; return 1; }
  is_fast_port "$port" || { warn "EasyTier 端口必须位于 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}。"; return 1; }
  if entries_rows | awk -F'\t' -v n="$name" -v cur="$current_name" '$1==n && $1!=cur {found=1} END{exit !found}'; then
    warn "公网入口名称已存在：${name}"
    return 1
  fi
  if entries_rows | awk -F'\t' -v ip="$et_ip" -v cur="$current_name" '$3==ip && $1!=cur {found=1} END{exit !found}'; then
    warn "EasyTier IP 已被使用：${et_ip}"
    return 1
  fi
  if entries_rows | awk -F'\t' -v p="$port" -v cur="$current_name" '$5==p && $1!=cur {found=1} END{exit !found}'; then
    warn "EasyTier 端口已被使用：${port}"
    return 1
  fi
  return 0
}

replace_entry_row() {
  local row="$1" name tmp
  name="${row%%$'\t'*}"
  ensure_tsv_files
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$ENTRIES_TSV" >"$tmp"
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
  local network_name network_secret suggested_name suggested_ip suggested_proto suggested_port
  network_name="leikwan-$(random_hex 4)"
  network_secret="$(random_hex 32)"
  suggested_name="$(next_entry_name)"
  suggested_ip="$(next_entry_et_ip 2>/dev/null || printf '%s' "$ENTRY_ET_IP_DEFAULT")"
  suggested_proto="$EASYTIER_PROTOCOL_DEFAULT"
  suggested_port="$(next_entry_easytier_port 2>/dev/null || printf '%s' "$EASYTIER_PORT_DEFAULT")"
  echo
  echo "${BOLD}新增公网入口建议：${RESET}"
  echo "- 名称：${suggested_name}"
  echo "- EasyTier IP：${suggested_ip}"
  echo "- EasyTier 端口：${suggested_port}"
  echo
  if ! prompt_yes_no "是否使用以上推荐？" "Y"; then
    while true; do
      suggested_name="$(safe_name "$(prompt_value "公网入口名称" "$suggested_name")")"
      suggested_ip="$(prompt_value "EasyTier IP" "$suggested_ip")"
      suggested_proto="$(prompt_value "EasyTier 协议" "$suggested_proto")"
      suggested_port="$(prompt_port "EasyTier 监听端口（8000-9000）" "$suggested_port")"
      validate_unique_entry_fields "$suggested_name" "$suggested_ip" "$suggested_port" "" && break
    done
  else
    validate_unique_entry_fields "$suggested_name" "$suggested_ip" "$suggested_port" "" || return 1
  fi
  write_file "$NETWORK_ENV" "ROLE=leikwan-relay
EASYTIER_NETWORK_NAME=${network_name}
EASYTIER_NETWORK_SECRET=${network_secret}
EASYTIER_LISTEN_PORT=${suggested_port}
EASYTIER_PROTOCOL=${suggested_proto}
EASYTIER_RELAY_ET_IP=${RELAY_ET_IP}" 600
  write_file "$NETWORK_PAIRING_FILE" "PAIRING_VERSION=0.4
ROLE=leikwan-relay
EASYTIER_NETWORK_NAME=${network_name}
EASYTIER_NETWORK_SECRET=${network_secret}
RELAY_ET_IP=${RELAY_ET_IP}
SUGGESTED_ENTRY_NAME=${suggested_name}
SUGGESTED_ENTRY_ET_IP=${suggested_ip}
SUGGESTED_EASYTIER_PROTOCOL=${suggested_proto}
SUGGESTED_EASYTIER_PORT=${suggested_port}" 600
  print_pairing_code "复制下面整段到 A 公网入口机" \
    "-----BEGIN LEIKWAN EASYTIER NETWORK-----" \
    "-----END LEIKWAN EASYTIER NETWORK-----" \
    "$NETWORK_PAIRING_FILE" \
    "LEIKWAN_EASYTIER_NETWORK_BASE64"
  info '下一步：去 A 公网入口机，进入"快速组网（分步提示）"，选择第 3 项，粘贴上面的网络码。'
}

quick_deploy_entry_from_network_pairing() {
  need_root_unless_dry_run
  ensure_base_dirs
  guard_entry_join_role || return 0
  local source="${1:-}" tmp role network_name network_secret relay_ip name et_ip proto port public_host detected service service_name
  tmp="$(mktemp)"
  read_pairing_code "$tmp" "B 利群主机" "-----END LEIKWAN EASYTIER NETWORK-----" "LEIKWAN_EASYTIER_NETWORK_BASE64" "$source" || { rm -f "$tmp"; return 1; }
  role="$(env_file_get "$tmp" ROLE)"
  case "$role" in
    leikwan-relay) ;;
    cloud-entry) fail "你粘贴的是入口码，需要在 B 利群主机选择第 4 项。"; rm -f "$tmp"; return 1 ;;
    *) fail "这不是 EasyTier 网络码，请确认粘贴的是 B 生成的那段。"; rm -f "$tmp"; return 1 ;;
  esac
  require_pairing_fields "$tmp" PAIRING_VERSION ROLE EASYTIER_NETWORK_NAME EASYTIER_NETWORK_SECRET RELAY_ET_IP SUGGESTED_ENTRY_NAME SUGGESTED_ENTRY_ET_IP SUGGESTED_EASYTIER_PROTOCOL SUGGESTED_EASYTIER_PORT || { rm -f "$tmp"; return 1; }
  network_name="$(env_file_get "$tmp" EASYTIER_NETWORK_NAME)"
  network_secret="$(env_file_get "$tmp" EASYTIER_NETWORK_SECRET)"
  relay_ip="$(env_file_get "$tmp" RELAY_ET_IP)"
  name="$(safe_name "$(env_file_get "$tmp" SUGGESTED_ENTRY_NAME)")"
  et_ip="$(env_file_get "$tmp" SUGGESTED_ENTRY_ET_IP)"
  proto="$(env_file_get "$tmp" SUGGESTED_EASYTIER_PROTOCOL)"
  port="$(env_file_get "$tmp" SUGGESTED_EASYTIER_PORT)"
  while true; do
    name="$(safe_name "$(prompt_value "本机公网入口名称" "$name")")"
    et_ip="$(prompt_value "本机 EasyTier IP" "$et_ip")"
    proto="$(prompt_value "EasyTier 协议" "$proto")"
    port="$(prompt_port "EasyTier 监听端口（8000-9000）" "$port")"
    validate_unique_entry_fields "$name" "$et_ip" "$port" "$name" && break
  done
  detected="$(detect_public_ipv4 || true)"
  public_host="$(prompt_value "请输入本机公网 IP / 域名，用于 B 连接 EasyTier" "$detected")"
  [[ -n "$public_host" ]] || public_host="$(prompt_host "请输入本机公网 IP / 域名")"
  confirm_summary "entry 快速部署摘要" "入口名称：${name}\n公网地址：${public_host}\nEasyTier IP：${et_ip}\nEasyTier 监听：${proto}/${port}\nRelay EasyTier IP：${relay_ip}" || { rm -f "$tmp"; return 0; }
  write_file "$NETWORK_ENV" "ROLE=cloud-entry
ENTRY_NAME=${name}
ENTRY_ET_IP=${et_ip}
EASYTIER_NETWORK_NAME=${network_name}
EASYTIER_NETWORK_SECRET=${network_secret}
EASYTIER_LISTEN_PORT=${port}
EASYTIER_PROTOCOL=${proto}
EASYTIER_RELAY_ET_IP=${relay_ip}" 600
  install_easytier_binary || { rm -f "$tmp"; return 1; }
  service="$(render_entry_service "$name" "$et_ip" "$proto" "$port")" || { rm -f "$tmp"; return 1; }
  service_name="$(entry_service_name "$name")"
  write_file "$(entry_service_path "$name")" "$service" 644
  start_service_file "$service_name"
  wait_et_ip "$et_ip" 15 || warn "15 秒内未检测到 EasyTier IP：${et_ip}"
  if ss -lntH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}'; then ok "EasyTier TCP ${port} 已监听"; else warn "EasyTier TCP ${port} 未监听"; fi
  replace_entry_row "${name}"$'\t'"${public_host}"$'\t'"${et_ip}"$'\t'"${proto}"$'\t'"${port}"$'\t'"100"$'\t'"true"
  write_file "$ENTRY_PAIRING_FILE" "PAIRING_VERSION=0.4
ROLE=cloud-entry
ENTRY_NAME=${name}
ENTRY_PUBLIC_HOST=${public_host}
ENTRY_ET_IP=${et_ip}
EASYTIER_PROTOCOL=${proto}
EASYTIER_PORT=${port}
WEIGHT=100
ENABLED=true" 600
  rm -f "$tmp"
  print_pairing_code "复制下面整段回 B 利群主机" \
    "-----BEGIN LEIKWAN EASYTIER ENTRY-----" \
    "-----END LEIKWAN EASYTIER ENTRY-----" \
    "$ENTRY_PAIRING_FILE" \
    "LEIKWAN_EASYTIER_ENTRY_BASE64"
  info '下一步：回到 B 利群主机，快速组网 -> 4，粘贴上面的入口码。'
}

quick_deploy_relay_from_entry_pairing() {
  need_root_unless_dry_run
  ensure_base_dirs
  guard_relay_join_role || return 0
  [[ -f "$NETWORK_ENV" ]] || { fail "缺少 ${NETWORK_ENV}，请先在 B 执行 pair relay-init。"; return 1; }
  local source="${1:-}" tmp role name public_host et_ip proto port weight enabled row service
  tmp="$(mktemp)"
  read_pairing_code "$tmp" "A 公网入口机" "-----END LEIKWAN EASYTIER ENTRY-----" "LEIKWAN_EASYTIER_ENTRY_BASE64" "$source" || { rm -f "$tmp"; return 1; }
  role="$(env_file_get "$tmp" ROLE)"
  case "$role" in
    cloud-entry) ;;
    leikwan-relay) fail "你粘贴的是网络码，需要在 A 公网入口选择第 3 项。"; rm -f "$tmp"; return 1 ;;
    *) fail "这不是 EasyTier 入口码，请确认粘贴的是 A 生成的那段。"; rm -f "$tmp"; return 1 ;;
  esac
  require_pairing_fields "$tmp" PAIRING_VERSION ROLE ENTRY_NAME ENTRY_PUBLIC_HOST ENTRY_ET_IP EASYTIER_PROTOCOL EASYTIER_PORT || { rm -f "$tmp"; return 1; }
  name="$(safe_name "$(env_file_get "$tmp" ENTRY_NAME)")"
  public_host="$(env_file_get "$tmp" ENTRY_PUBLIC_HOST)"
  et_ip="$(env_file_get "$tmp" ENTRY_ET_IP)"
  proto="$(env_file_get "$tmp" EASYTIER_PROTOCOL)"
  port="$(env_file_get "$tmp" EASYTIER_PORT)"
  port="$(normalize_easytier_port "$port")" || { rm -f "$tmp"; return 1; }
  weight="$(env_file_get "$tmp" WEIGHT)"; weight="${weight:-100}"
  enabled="$(env_file_get "$tmp" ENABLED)"; enabled="${enabled:-true}"
  confirm_summary "relay 接入入口摘要" "入口名称：${name}\n入口公网：${public_host}:${port}\n入口 EasyTier IP：${et_ip}\nRelay EasyTier IP：${RELAY_ET_IP}" || { rm -f "$tmp"; return 0; }
  row="${name}"$'\t'"${public_host}"$'\t'"${et_ip}"$'\t'"${proto}"$'\t'"${port}"$'\t'"${weight}"$'\t'"${enabled}"
  replace_entry_row "$row"
  install_easytier_binary || { rm -f "$tmp"; return 1; }
  service="$(render_relay_service)" || { rm -f "$tmp"; return 1; }
  write_file "$EASYTIER_RELAY_SERVICE" "$service" 644
  start_service_file "$EASYTIER_RELAY_SERVICE_NAME"
  wait_et_ip "$RELAY_ET_IP" 15 || warn "15 秒内未检测到 Relay EasyTier IP：${RELAY_ET_IP}"
  case "$(tcp_reachable_status "$public_host" "$port")" in
    0) ok "入口 EasyTier TCP 可达：${public_host}:${port}" ;;
    2) warn "未找到 nc，无法测试入口 EasyTier TCP；请安装 netcat-openbsd" ;;
    *) warn "入口 EasyTier TCP 不可达：${public_host}:${port}" ;;
  esac
  if ping -c 2 "$et_ip" >/dev/null 2>&1; then ok "EasyTier ping ${et_ip} 成功"; else warn "EasyTier peer 可能已连接，但 ping ${et_ip} 暂不通。"; fi
  ok "已接入入口 ${name}。"
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
    echo; echo "${BOLD}快速配对${RESET}"
    echo "1. 在 B 运行：生成给 A 的网络码"
    echo "2. 在 A 运行：粘贴 B 的网络码，部署 A"
    echo "3. 在 B 运行：粘贴 A 的入口码，完成接入"
    echo "4. 查看 EasyTier 配对状态"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) quick_generate_network_pairing ;;
      2) quick_deploy_entry_from_network_pairing ;;
      3) quick_deploy_relay_from_entry_pairing ;;
      4) pairing_status ;;
      0) return 0 ;;
      "") echo "请输入选项编号。" ;;
      *) echo "无效选择。" ;;
    esac
  done
}

add_entry() {
  need_root_unless_dry_run
  ensure_tsv_files
  local name public_host et_ip proto port weight enabled row
  name="$(safe_name "$(prompt_value "入口名称，例如 aliyun / tencent / home")")"
  entry_exists "$name" && warn "入口已存在，将覆盖。"
  public_host="$(prompt_host "入口公网 IP 或域名")"
  et_ip="$(prompt_value "入口 EasyTier IP" "$(next_entry_et_ip 2>/dev/null || printf '%s' "$ENTRY_ET_IP_DEFAULT")")"
  proto="$(prompt_value "EasyTier 协议" "$EASYTIER_PROTOCOL_DEFAULT")"
  port="$(prompt_port "EasyTier 监听端口（8000-9000）" "$(next_entry_easytier_port 2>/dev/null || printf '%s' "$EASYTIER_PORT_DEFAULT")")"
  validate_unique_entry_fields "$name" "$et_ip" "$port" "$name" || return 0
  weight="$(prompt_value "权重" "100")"
  enabled="$(prompt_value "是否启用 true/false" "true")"
  row="${name}"$'\t'"${public_host}"$'\t'"${et_ip}"$'\t'"${proto}"$'\t'"${port}"$'\t'"${weight}"$'\t'"${enabled}"
  confirm_summary "添加入口摘要" "name=${name}\npublic_host=${public_host}\net_ip=${et_ip}\nprotocol=${proto}\nport=${port}\nweight=${weight}\nenabled=${enabled}" || return 0
  replace_entry_row "$row"
}

list_entries() {
  display_entries
}

delete_entry() {
  need_root_unless_dry_run
  local name tmp
  name="$(select_entry_name)" || return 0
  prompt_yes_no "确认删除入口 ${name}？" "N" || return 0
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$ENTRIES_TSV" >"$tmp"
  write_file "$ENTRIES_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
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
}

test_entries() {
  local name public_host et_ip proto port _weight enabled
  name="$(select_entry_name)" || return 0
  while IFS=$'\t' read -r name public_host et_ip proto port _weight enabled; do
    echo
    echo "入口：${name}"
    [[ "$enabled" == "true" ]] || warn "该公网入口当前 disabled，仅执行连通性测试。"
    case "$(tcp_reachable_status "$public_host" "$port")" in
      0) ok "${proto} ${public_host}:${port} 可达" ;;
      2) warn "未找到 nc，无法测试 ${proto} ${public_host}:${port}；请安装 netcat-openbsd" ;;
      *) warn "${proto} ${public_host}:${port} 不可达" ;;
    esac
    ping -c 2 "$et_ip" || true
    return 0
  done < <(entries_rows | awk -F'\t' -v n="$name" '$1==n')
}

apply_easytier_entry_services() {
  need_root_unless_dry_run
  install_easytier_binary
  local name public_host et_ip proto port weight enabled service
  while IFS=$'\t' read -r name public_host et_ip proto port weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    service="$(render_entry_service "$name" "$et_ip" "$proto" "$port")" || return 1
    write_file "$(entry_service_path "$name")" "$service" 644
    start_service_file "$(entry_service_name "$name")"
    ok "EasyTier entry 已配置：${name} ${et_ip} ${proto}/${port} weight=${weight}"
  done < <(entries_rows)
}

apply_easytier_relay_service() {
  need_root_unless_dry_run
  install_easytier_binary
  local service
  service="$(render_relay_service)" || return 1
  write_file "$EASYTIER_RELAY_SERVICE" "$service" 644
  start_service_file "$EASYTIER_RELAY_SERVICE_NAME"
  ok "EasyTier relay 已配置。"
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
  entry_port="$(prompt_forward_entry_port "$name")"
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
  confirm_summary "添加转发目标摘要" "name=${name}\nentry_port=${entry_port}\ntarget=${target_host}:${target_port}\nout_iface=${out_iface:-auto}\nroute_table=$(route_table_display "$route_table")\nenabled=${enabled}" || return 0
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
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1==n {next} {print}' "$FORWARDS_TSV" >"$tmp"
  write_file "$FORWARDS_TSV" "$(cat "$tmp")" 600
  rm -f "$tmp"
  apply_nft_rules "leikwan-relay" || warn "relay nftables 未应用成功，请检查后重试。"
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
  apply_nft_rules "leikwan-relay" || warn "relay nftables 未应用成功，请检查后重试。"
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
  entry_port="$(prompt_forward_entry_port "$old_name" "$old_port")"
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
  confirm_summary "修改转发目标摘要" "name=${old_name}\nentry_port=${entry_port}\ntarget=${target_host}:${target_port}\nout_iface=${out_iface:-auto}\nroute_table=$(route_table_display "$route_table")\nenabled=${enabled}" || return 0
  replace_forward_row "$new_row"
  apply_nft_rules "leikwan-relay" || warn "relay nftables 未应用成功，请检查后重试。"
}

test_forward() {
  local name row _entry_port target_host target_ip target_port _out_iface _route_table enabled _last_resolved_at _comment
  name="$(select_forward_name)" || return 0
  resolve_forwards || return 1
  row="$(resolved_rows | awk -F'\t' -v n="$name" '$1==n {print; found=1} END{exit !found}')"
  [[ -n "$row" ]] || { warn "转发不存在。"; return 0; }
  IFS=$'\034' read -r name _entry_port target_host target_ip target_port _out_iface _route_table enabled _last_resolved_at _comment <<<"$(awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} {print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' <<<"$row")"
  [[ "$enabled" == "true" ]] || warn "该转发当前 disabled，仅执行后端可达性测试。"
  [[ -n "$target_ip" ]] || { warn "目标未解析：${target_host}"; return 0; }
  ensure_nc_for_test || true
  case "$(tcp_reachable_status "$target_ip" "$target_port")" in
    0) ok "${target_ip}:${target_port} 可达" ;;
    2) warn "未找到 nc，无法测试 ${target_ip}:${target_port}；请安装 netcat-openbsd" ;;
    *) warn "${target_ip}:${target_port} 不可达" ;;
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
  awk -F'\t' 'NF && $1 !~ /^#/ {print}' "$RESOLVED_TSV"
}

resolved_rows_usv() {
  resolved_rows | awk -F'\t' 'BEGIN{OFS=sprintf("%c", 28)} NF>=9 {print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}'
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
EOF
  cat <<EOF
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr ${relay_ip} tcp dport ${start}-${end} masquerade
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
    else
      printf '    iifname "%s" ip daddr %s tcp dport %s accept\n' "$et_iface" "$target_ip" "$target_port"
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
    else
      printf '    ip daddr %s tcp dport %s masquerade\n' "$target_ip" "$target_port"
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

current_entry_public_host() {
  local host
  host="$(env_file_get "$ENTRY_PAIRING_FILE" ENTRY_PUBLIC_HOST)"
  [[ -n "$host" ]] || host="$(entries_rows | awk -F'\t' '$7=="true"{print $2; exit}')"
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
  is_ipv4 "${relay_ip:-$RELAY_ET_IP}" || { fail "Relay EasyTier IP 非法：${relay_ip:-$RELAY_ET_IP}"; return 1; }
  relay_ip="${relay_ip:-$RELAY_ET_IP}"
  confirm_summary "配置公网入口端口池摘要" "ENTRY_EXPOSE_START=${start}\nENTRY_EXPOSE_END=${end}\nRELAY_ET_IP=${relay_ip}\n动作：A 侧把该端口池 DNAT 到 Relay EasyTier IP，保持原端口不变。" || return 0
  write_file "$ENTRY_EXPOSE_ENV" "ENTRY_EXPOSE_START=${start}
ENTRY_EXPOSE_END=${end}
RELAY_ET_IP=${relay_ip}
ENABLED=true" 600
  if [[ "$apply" != "no" ]]; then
    apply_nft_rules "cloud-entry" || warn "公网入口 nftables 未应用成功，请检查后重试。"
  fi
  info "下一步：回到 B 利群主机，如果需要指定 CN2 / 9929 出口，请先选择第 7 项配置 PBR，再选择第 6 项添加后端转发目标。"
}

apply_nft_rules() {
  local role="$1" auto_fix_route="${2:-0}" content tmp old enabled_count=-1 relay_ip start end
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
      if ! grep -q "tcp dport ${start}-${end} dnat ip to ${relay_ip}" <<<"$content"; then
        fail "入口端口池 ${start}-${end} 未生成 DNAT 规则。"
        return 1
      fi
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
      ;;
    *) fail "无法识别角色：${role}"; return 1 ;;
  esac
  write_file "$NFT_RULE_FILE" "$content" 644
  write_file "$NFT_SERVICE" "$(render_nft_service)" 644
  (( DRY_RUN == 1 )) && return 0
  tmp="$(mktemp)"; old="$(mktemp)"
  printf '%s\n' "$content" >"$tmp"
  if ! nft -c -f "$tmp"; then
    fail "nftables 规则校验失败。"
    rm -f "$tmp" "$old"
    return 1
  fi
  nft list table inet leikwan_forward >"$old" 2>/dev/null || true
  nft delete table inet leikwan_forward 2>/dev/null || true
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
  else
    fail "nftables 应用失败，尝试回滚。"
    [[ -s "$old" ]] && nft -f "$old" || true
    rm -f "$tmp" "$old"
    return 1
  fi
  rm -f "$tmp" "$old"
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
    echo; echo "${BOLD}nftables 规则管理${RESET}"
    echo "1. 查看当前 nftables 规则"
    echo "2. 重新应用公网入口规则"
    echo "3. 重新应用利群转发规则"
    echo "4. 清理脚本生成的 nftables 规则"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) nft_show_rules ;;
      2) apply_nft_rules "cloud-entry" || warn "公网入口 nftables 规则未应用成功。" ;;
      3) apply_nft_rules "leikwan-relay" || warn "利群转发 nftables 规则未应用成功。" ;;
      4) cleanup_nftables_rules ;;
      0) return 0 ;;
      "") echo "请输入选项编号。" ;;
      *) echo "无效选择。" ;;
    esac
  done
}

pbr_init_rt_tables() {
  if [[ ! -f "$PBR_RT_TABLES" ]]; then
    write_file "$PBR_RT_TABLES" $'255 local\n254 main\n253 default\n0 unspec' 644
  fi
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
  pbr_init_rt_tables
  pbr_refresh_dynamic_rules
  [[ -f "$PBR_STATIC_CONF" ]] || { warn "暂无 PBR 静态规则。"; return 0; }
  local cidr group _source_type _source_name _source_host table_id gw table_name normalized
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
        continue
      fi
    fi
    if ! ip rule add to "$cidr" table "$table_id" priority "$PBR_PRIORITY" 2>/dev/null; then
      fail "PBR 应用失败：${cidr} -> ${table_name}"
      continue
    fi
    ok "PBR：${cidr} -> ${table_name}"
  done <"$PBR_STATIC_CONF"
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
  ensure_tsv_files
  local name row target_host target_ip group cidr
  name="$(select_forward_name enabled)" || return 0
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
  pbr_apply
  info "如需同步转发目标 out_iface / route_table 元数据，请执行：lq forward apply-relay --auto-fix-route"
}

generate_forward_outputs() {
  ensure_tsv_files
  validate_forwards_tsv || return 1
  mkdir -p "$OUTPUT_DIR"
  local txt tsv name entry_port target_host target_port out_iface route_table enabled comment
  local e_name public_host et_ip proto port weight e_enabled health
  txt="【转发入口清单】"$'\n'
  tsv=$'target_name\tentry_name\tpublic_host\tentry_port\ttarget_host\ttarget_port\thealth\tweight'
  while IFS=$'\034' read -r name entry_port target_host target_port out_iface route_table enabled comment; do
    [[ "$enabled" == "true" ]] || continue
    txt="${txt}"$'\n'"目标：${name}"$'\n'"后端：${target_host}:${target_port}"$'\n'"入口："$'\n'
    while IFS=$'\t' read -r e_name public_host et_ip proto port weight e_enabled; do
      [[ "$e_enabled" == "true" ]] || continue
      health="UNKNOWN"
      if command -v nc >/dev/null 2>&1; then
        if nc -vz -w 2 "$public_host" "$entry_port" >/dev/null 2>&1; then health="UP"; else health="DOWN"; fi
      fi
      txt="${txt}- ${e_name}  ${public_host}:${entry_port}  状态：${health}  权重：${weight}"$'\n'
      tsv="${tsv}"$'\n'"${name}"$'\t'"${e_name}"$'\t'"${public_host}"$'\t'"${entry_port}"$'\t'"${target_host}"$'\t'"${target_port}"$'\t'"${health}"$'\t'"${weight}"
    done < <(entries_rows | sort -t$'\t' -k6,6nr)
  done < <(forwards_rows_usv)
  write_file "$FORWARD_TXT" "$txt" 644
  write_file "$FORWARD_TSV" "$tsv" 644
  cat "$FORWARD_TXT"
}

report() {
  local status="$1" msg="$2"
  case "$status" in
    OK) echo "${GREEN}[OK]${RESET} ${msg}" ;;
    WARN) echo "${YELLOW}[WARN]${RESET} ${msg}" ;;
    FAIL) echo "${RED}[FAIL]${RESET} ${msg}" ;;
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

doctor_cloud() {
  report OK "角色：cloud-entry"
  local entry_ip port iface service_name relay_ip start end
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
  port="$(env_file_get "$ENTRY_PAIRING_FILE" EASYTIER_PORT)"
  [[ -n "$port" ]] || port="$(env_file_get "$NETWORK_ENV" EASYTIER_LISTEN_PORT)"
  port="${port:-$EASYTIER_PORT_DEFAULT}"
  if is_fast_port "$port"; then report OK "EasyTier 监听端口：tcp/${port}，位于白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}"; else report WARN "EasyTier 监听端口：tcp/${port}，不在白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}"; fi
  if ss -lntH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {found=1} END{exit !found}'; then report OK "EasyTier TCP ${port} 已监听"; else report WARN "EasyTier TCP ${port} 未监听"; fi
  report_ping_quality "$RELAY_ET_IP" "ping relay ${RELAY_ET_IP}" || true
  if nft list table inet leikwan_forward >/dev/null 2>&1; then
    report OK "nftables table inet leikwan_forward 存在"
    if nft_has_dnat_rules; then report OK "nftables DNAT 规则存在"; else report WARN "nftables 表存在，但没有转发 DNAT 规则。"; fi
    report_mss_clamp_status
  else
    report WARN "nftables 项目表不存在"
  fi
  if [[ -f "$ENTRY_EXPOSE_ENV" ]]; then
    start="$(entry_expose_start)"
    end="$(entry_expose_end)"
    relay_ip="$(entry_expose_relay_ip)"
    report OK "入口端口池：${start}-${end} -> ${relay_ip}"
    if nft list table inet leikwan_forward 2>/dev/null | grep -Fq "tcp dport ${start}-${end} dnat ip to ${relay_ip}"; then
      report OK "入口端口池 DNAT 正常"
    else
      report FAIL "入口端口池 DNAT 缺失：应为 tcp dport ${start}-${end} dnat ip to ${relay_ip}"
    fi
  else
    report WARN "公网入口端口池未配置，请执行 lq entry expose-range"
  fi
  [[ -f "$ENTRY_PAIRING_FILE" ]] && report OK "入口配对码：已生成"
}

doctor_relay() {
  report OK "角色：leikwan-relay"
  local iface entries forwards name public_host et_ip proto port _weight enabled peer_text target_ip target_port
  local entry_port target_host out_iface route_table comment
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
  peer_text="$(easytier_cli_peer_text)"
  while IFS=$'\t' read -r name public_host et_ip proto port _weight enabled; do
    [[ "$enabled" == "true" ]] || continue
    if grep -q "$et_ip" <<<"$peer_text"; then report OK "入口 ${name} peer 可见：${et_ip}"; else report WARN "入口 ${name} peer 暂未在 easytier-cli 中出现"; fi
    report INFO "入口 ${name} peer 目标：${proto}://${public_host}:${port}"
    if is_fast_port "$port"; then report OK "入口 ${name} EasyTier 端口 ${port} 位于白名单"; else report WARN "入口 ${name} EasyTier 端口 ${port} 不在白名单 ${FAST_PORT_RANGE_START}-${FAST_PORT_RANGE_END}"; fi
    report_ping_quality "$et_ip" "ping ${name} ${et_ip}" || true
    case "$(tcp_reachable_status "$public_host" "$port")" in
      0) report OK "入口 ${name} TCP 可达：${public_host}:${port}" ;;
      2) report WARN "未找到 nc，无法测试入口 ${name} TCP；请安装 netcat-openbsd" ;;
      *) report WARN "入口 ${name} TCP 不可达：${public_host}:${port}" ;;
    esac
  done < <(entries_rows)
  if sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -qx 1; then report OK "net.ipv4.ip_forward=1"; else report WARN "net.ipv4.ip_forward 未启用"; fi
  if nft list table inet leikwan_forward >/dev/null 2>&1; then
    report OK "nftables table inet leikwan_forward 存在"
    if nft_has_dnat_rules; then report OK "nftables DNAT 规则存在"; else report WARN "nftables 表存在，但没有转发 DNAT 规则。"; fi
    report_mss_clamp_status
  else
    report WARN "nftables 项目表不存在"
  fi
  if forwards="$(enabled_forwards_count 2>/dev/null)"; then
    report INFO "enabled forwards：${forwards}"
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
      fi
      if [[ -n "$target_ip" ]]; then
        if nft_has_relay_dnat "$entry_port" "$target_ip" "$target_port"; then
          report OK "${name} relay DNAT 正常"
        else
          report FAIL "${name} relay DNAT 缺失：应为 tcp dport ${entry_port} dnat ip to ${target_ip}:${target_port}"
        fi
      fi
    done < <(resolved_rows_usv)
  else
    report FAIL "resolved.tsv 更新失败，请检查 target_host 解析。"
  fi
  [[ -f "$NETWORK_PAIRING_FILE" ]] && report OK "relay 网络码：已生成"
}

doctor() {
  local role bbr_cc bbr_qdisc
  role="$(detect_role)"
  bbr_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  bbr_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  if [[ "$bbr_cc" == "bbr" && "$bbr_qdisc" == "fq" ]]; then report OK "BBR/fq enabled"; else report INFO "BBR=${bbr_cc:-unknown}, qdisc=${bbr_qdisc:-unknown}"; fi
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
    echo; echo "${BOLD}BBR / 系统优化${RESET}"
    echo "1. 查看状态"; echo "2. 启用 BBR + fq"; echo "3. 恢复默认"; echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc 2>/dev/null || true ;;
      2) write_file "$BBR_SYSCTL_CONF" $'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' 644; modprobe tcp_bbr 2>/dev/null || true; sysctl --system ;;
      3) backup_file "$BBR_SYSCTL_CONF"; rm -f "$BBR_SYSCTL_CONF"; sysctl --system ;;
      0) return 0 ;;
    esac
  done
}

link_test_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}链路测试${RESET}"
    echo "1. ping relay EasyTier IP"; echo "2. ping 所有入口 EasyTier IP"; echo "3. 测入口 EasyTier TCP"; echo "4. 测后端 target"; echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) ping -c 4 "$RELAY_ET_IP" || true ;;
      2) entries_rows | while IFS=$'\t' read -r _n _h ip _proto _port _w e; do [[ "$e" == "true" ]] && ping -c 2 "$ip" || true; done ;;
      3)
        ensure_nc_for_test || continue
        entries_rows | while IFS=$'\t' read -r _n h _ip _proto port _w e; do [[ "$e" == "true" ]] && nc -vz -w 3 "$h" "$port" || true; done
        ;;
      4)
        ensure_nc_for_test || continue
        resolved_rows | while IFS=$'\t' read -r _n _ep _th ti tp _oi _rt en _c; do [[ "$en" == "true" && -n "$ti" ]] && nc -vz -w 3 "$ti" "$tp" || true; done
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
    cat /etc/os-release 2>/dev/null || true
    ip -br addr || true
    ip route || true
    ip rule || true
    systemctl --no-pager --full status "$EASYTIER_RELAY_SERVICE_NAME" 'easytier-entry-*' "$NFT_SERVICE_NAME" 2>&1 || true
    ss -lntup || true
    nft list table inet leikwan_forward 2>&1 || true
    "$EASYTIER_CLI_BIN" peer 2>&1 || true
    doctor || true
    echo "outputs:"
    [[ -f "$FORWARD_TSV" ]] && sed -n '1,120p' "$FORWARD_TSV"
  } >"$tmp" 2>&1
  sed -E \
    -e 's/(EASYTIER_NETWORK_SECRET=).*/\1<redacted>/g' \
    -e 's/(PrivateKey[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1<redacted>/g' \
    -e 's#(vless|vmess|trojan|ss|hysteria)://[^[:space:]]+#<proxy-link-redacted>#g' \
    "$tmp" >"$REPORT_FILE"
  rm -f "$tmp"
  chmod 600 "$REPORT_FILE"
  ok "已生成脱敏故障报告：${REPORT_FILE}"
}

legacy_cleanup_menu() {
  need_root
  local choice
  while true; do
    echo; echo "${BOLD}legacy 清理（默认不执行）${RESET}"
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
  echo "- ${OLD_STATE_DIR}（旧名称兼容清理）"
  echo "- ${EASYTIER_CORE_BIN} / ${EASYTIER_CLI_BIN}"
  echo "- ${SHORTCUT_LQ} / ${SHORTCUT_LQ_UPPER}"
  echo "- ${NFT_RULE_FILE} / ${NFT_SERVICE}"
  prompt_yes_no "第一次确认：继续卸载全部？" "N" || return 0
  prompt_yes_no "第二次确认：确实删除本脚本生成的组件？" "N" || return 0

  set +e
  if command -v systemctl >/dev/null 2>&1; then
    safe_stop_disable_service "$EASYTIER_RELAY_SERVICE_NAME"
    safe_stop_disable_service "$NFT_SERVICE_NAME"
    safe_stop_disable_service "leikwan-mss-clamp.service"
    cleanup_easytier_entry_units
  else
    warn "未找到 systemctl，跳过 systemd 服务停止。"
  fi
  safe_rm_file "$EASYTIER_RELAY_SERVICE" "$NFT_SERVICE" "/etc/systemd/system/leikwan-mss-clamp.service"
  if command -v nft >/dev/null 2>&1; then
    nft delete table inet leikwan_forward 2>/dev/null || true
    nft delete table inet lq_mss 2>/dev/null || true
  fi
  cleanup_leikwan_policy_routes
  safe_rm_file "$EASYTIER_CORE_BIN" "$EASYTIER_CLI_BIN" "$SHORTCUT_LQ" "$SHORTCUT_LQ_UPPER" \
    "/root/leikwan-toolkit.sh" "/root/wg-toolkit.sh" "$FORWARD_SYSCTL" "$BBR_SYSCTL_CONF" "$DNS_RESOLVED_CONF" "$LOG_FILE" "$OLD_LOG_FILE"
  safe_rm_dir "$STATE_DIR" "$OLD_STATE_DIR" "$BACKUP_DIR" "$OLD_BACKUP_DIR"
  command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
  set -e

  echo
  echo "${BOLD}卸载检查结果${RESET}"
  uninstall_check_line "nftables 转发表" nft leikwan_forward
  uninstall_check_line "旧 MSS 临时表" nft lq_mss
  uninstall_check_line "EasyTier relay 服务" service "${EASYTIER_RELAY_SERVICE_NAME}.service"
  uninstall_check_line "nft 持久化服务" service "${NFT_SERVICE_NAME}.service"
  uninstall_check_line "MSS clamp 旧服务" service "leikwan-mss-clamp.service"
  uninstall_check_line "EasyTier core" file "$EASYTIER_CORE_BIN"
  uninstall_check_line "EasyTier cli" file "$EASYTIER_CLI_BIN"
  uninstall_check_line "快捷命令 lq" file "$SHORTCUT_LQ"
  uninstall_check_line "快捷命令 LQ" file "$SHORTCUT_LQ_UPPER"
  uninstall_check_line "主脚本" file "/root/leikwan-toolkit.sh"
  uninstall_check_line "旧主脚本兼容入口" file "/root/wg-toolkit.sh"
  uninstall_check_line "配置目录" dir "$STATE_DIR"
  uninstall_check_line "旧配置目录" dir "$OLD_STATE_DIR"
  uninstall_check_line "备份目录" dir "$BACKUP_DIR"
  uninstall_check_line "旧备份目录" dir "$OLD_BACKUP_DIR"
  uninstall_check_line "日志文件" file "$LOG_FILE"
  uninstall_check_line "旧日志文件" file "$OLD_LOG_FILE"
  uninstall_check_line "IPv4 转发 sysctl" file "$FORWARD_SYSCTL"
  uninstall_check_line "BBR sysctl" file "$BBR_SYSCTL_CONF"
  uninstall_check_line "DNS resolved 配置" file "$DNS_RESOLVED_CONF"
  ok "卸载流程已完成；如上方有 WARN，表示对应对象仍存在，需要按提示手动检查。"
}

backup_snapshot() {
  need_root_unless_dry_run
  local dest
  dest="${BACKUP_DIR}/leikwan-v0.4-snapshot.$(date '+%Y%m%d-%H%M%S').tar.gz"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] tar -czf ${dest} ${STATE_DIR} ${FORWARD_SYSCTL}"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  tar -czf "$dest" "$STATE_DIR" "$FORWARD_SYSCTL" 2>/dev/null || true
  ok "已生成备份：${dest}"
}

restore_snapshot() {
  need_root_unless_dry_run
  local path
  path="$(prompt_value "请输入备份 tar.gz 路径")"
  [[ -f "$path" ]] || { warn "文件不存在：${path}"; return 0; }
  confirm_summary "恢复备份摘要" "来源：${path}\n动作：解包到 /，覆盖本项目配置；不删除用户其它规则。" || return 0
  (( DRY_RUN == 1 )) && return 0
  tar -xzf "$path" -C /
  systemctl daemon-reload || true
  ok "备份已恢复。请按需重启 EasyTier/nft 服务。"
}

backup_restore_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}备份 / 恢复${RESET}"
    echo "1. 生成配置快照"; echo "2. 从快照恢复"; echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) backup_snapshot ;;
      2) restore_snapshot ;;
      0) return 0 ;;
    esac
  done
}

easytier_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}EasyTier 组网管理${RESET}"
    echo "1. 安装 / 修复 EasyTier"; echo "2. B 生成网络码"; echo "3. A 粘贴网络码并部署入口"; echo "4. B 粘贴入口码并完成接入"; echo "5. 启动 / 重启 entry 服务"; echo "6. 启动 / 重启 relay 服务"; echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) install_easytier_binary ;;
      2) quick_generate_network_pairing ;;
      3) quick_deploy_entry_from_network_pairing ;;
      4) quick_deploy_relay_from_entry_pairing ;;
      5) apply_easytier_entry_services ;;
      6) apply_easytier_relay_service ;;
      0) return 0 ;;
    esac
  done
}

entries_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}公网入口列表管理（B 侧）${RESET}"
    echo "1. 生成新公网入口接入码"
    echo "2. 粘贴公网入口返回码并接入"
    echo "3. 手动添加公网入口（高级）"
    echo "4. 删除公网入口"
    echo "5. 启用 / 禁用公网入口"
    echo "6. 修改公网入口权重"
    echo "7. 查看所有公网入口"
    echo "8. 测试公网入口"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) quick_generate_network_pairing ;;
      2) quick_deploy_relay_from_entry_pairing ;;
      3) add_entry ;;
      4) delete_entry ;;
      5) set_entry_enabled ;;
      6) set_entry_weight ;;
      7) list_entries ;;
      8) test_entries ;;
      0) return 0 ;;
    esac
  done
}

forwards_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}转发目标管理${RESET}"
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
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) add_forward ;;
      2) edit_forward ;;
      3) delete_forward ;;
      4) list_forwards ;;
      5) set_forward_enabled ;;
      6) apply_nft_rules "leikwan-relay" || warn "利群转发 nftables 规则未应用成功。" ;;
      7) resolve_forwards ;;
      8) test_forward ;;
      9) import_forwards_tsv ;;
      10) export_forwards_tsv ;;
      11) generate_forward_outputs ;;
      0) return 0 ;;
    esac
  done
}

pbr_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}IPv4 多出口策略路由 / PBR${RESET}"
    echo "1. 添加静态 PBR"
    echo "2. 从现有转发目标添加 PBR"
    echo "3. 应用 PBR"
    echo "4. 查看 PBR"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) pbr_add_static ;;
      2) pbr_add_from_forward ;;
      3) pbr_apply ;;
      4) [[ -f "$PBR_STATIC_CONF" ]] && cat "$PBR_STATIC_CONF" || true; ip rule show | grep "$PBR_PRIORITY" || true ;;
      0) return 0 ;;
    esac
  done
}

install_shortcuts() {
  need_root_unless_dry_run
  local script_path content
  script_path="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
  if [[ "$(basename "$script_path")" == "wg-toolkit.sh" && -f "$(dirname "$script_path")/leikwan-toolkit.sh" ]]; then
    script_path="$(dirname "$script_path")/leikwan-toolkit.sh"
  fi
  content="#!/usr/bin/env bash
# Managed by leikwan-toolkit
exec bash ${script_path@Q} \"\$@\""
  write_file "$SHORTCUT_LQ" "$content" 755
  write_file "$SHORTCUT_LQ_UPPER" "$content" 755
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
  local choice
  while true; do
    echo; echo "${BOLD}快速组网（分步提示）${RESET}"
    echo "----------------------------------------"
    echo "本向导用于帮助你按顺序完成："
    echo
    echo "A：公网入口机"
    echo "B：利群主机"
    echo "C：后端 TCP 目标"
    echo
    echo "推荐链路："
    echo "外部客户端 -> A 公网入口端口 -> EasyTier -> B 利群主机 -> 后端目标"
    echo "----------------------------------------"
    echo
    echo "${BOLD}[重要提示]${RESET}"
    echo "如果当前机器是利群主机，请先执行："
    echo "高级功能 -> DNS / IPv4 优先修复"
    echo
    echo "原因："
    echo "部分利群主机 IPv6 / DNS 默认环境可能导致 GitHub、raw.githubusercontent.com、GitHub release 下载失败。"
    echo "先修复 IPv4 优先和 DNS，可以显著减少 EasyTier、release 包、脚本更新下载失败的问题。"
    echo
    echo "1. 我现在在利群主机：先执行 DNS / IPv4 优先修复"
    echo "2. 我现在在利群主机：生成 / 新增公网入口网络码"
    echo "3. 我现在在公网入口：粘贴利群网络码，部署本机入口"
    echo "4. 我现在在利群主机：粘贴公网入口返回码，完成接入"
    echo "5. 我现在在公网入口：配置入口端口池"
    echo "6. 我现在在利群主机：添加后端转发目标"
    echo "7. IPv4 多出口策略路由 / PBR"
    echo "8. 查看完整分步说明"
    echo "0. 返回"
    echo
    echo "提示：如果后端目标需要走 CN2 / 9929 等指定出口，请先执行第 7 项添加 PBR，再执行第 6 项添加后端转发目标。"
    echo "如果已经先执行第 6 项添加了后端转发，之后又添加 PBR，请重新执行：lq forward apply-relay --auto-fix-route"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) fix_dns_ipv4_first || warn "DNS / IPv4 优先修复未完成，请查看上方提示后重试。" ;;
      2) quick_generate_network_pairing || warn "生成 EasyTier 网络码未完成，请查看上方提示后重试。" ;;
      3) quick_deploy_entry_from_network_pairing || warn "公网入口部署未完成，请查看上方提示后重试。" ;;
      4) quick_deploy_relay_from_entry_pairing || warn "利群主机接入未完成，请查看上方提示后重试。" ;;
      5) entry_expose_range || warn "公网入口端口池配置未完成，请查看上方提示后重试。" ;;
      6) add_forward || warn "后端转发目标添加未完成，请查看上方提示后重试。" ;;
      7) pbr_menu ;;
      8) echo; print_quick_networking_steps ;;
      0) return 0 ;;
      "") echo "请输入选项编号。" ;;
      *) echo "无效选择。" ;;
    esac
  done
}

relay_host_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}利群主机${RESET}"
    echo "1. EasyTier 组网管理"
    echo "2. 公网入口列表管理"
    echo "3. 转发目标管理"
    echo "4. IPv4 多出口策略路由"
    echo "5. IPv6 入站安全收口"
    echo "6. 查看利群主机状态"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) easytier_menu ;;
      2) entries_menu ;;
      3) forwards_menu ;;
      4) pbr_menu ;;
      5) ipv6_lockdown ;;
      6) doctor ;;
      0) return 0 ;;
      "") echo "请输入选项编号。" ;;
      *) echo "无效选择。" ;;
    esac
  done
}

entry_host_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}公网入口（A 本机）${RESET}"
    echo "1. 粘贴利群网络码，部署本机入口"
    echo "2. 配置本机入口端口池"
    echo "3. 查看本机公网入口状态"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) quick_deploy_entry_from_network_pairing ;;
      2) entry_expose_range ;;
      3)
        if [[ "$(detect_role)" == "leikwan-relay" ]]; then
          warn "当前机器检测为利群主机，不是公网入口机。"
          warn "如需管理已接入的公网入口列表，请进入：利群主机 -> 公网入口列表管理"
        else
          doctor
        fi
        ;;
      0) return 0 ;;
      "") echo "请输入选项编号。" ;;
      *) echo "无效选择。" ;;
    esac
  done
}

advanced_menu() {
  local choice
  while true; do
    echo; echo "${BOLD}高级功能${RESET}"
    echo "1. nftables 规则管理"
    echo "2. 链路测试"
    echo "3. DNS / IPv4 优先修复"
    echo "4. BBR / 系统优化"
    echo "5. 查看全部状态"
    echo "6. 备份 / 恢复"
    echo "7. 生成脱敏故障报告"
    echo "8. legacy 清理"
    echo "0. 返回"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) nftables_menu ;;
      2) link_test_menu ;;
      3) fix_dns_ipv4_first || warn "DNS / IPv4 优先修复未完成，请查看上方提示后重试。" ;;
      4) bbr_menu ;;
      5) doctor ;;
      6) backup_restore_menu ;;
      7) generate_debug_report ;;
      8) legacy_cleanup_menu ;;
      0) return 0 ;;
      "") echo "请输入选项编号。" ;;
      *) echo "无效选择。" ;;
    esac
  done
}

main_menu() {
  need_root_unless_dry_run
  install_shortcuts || true
  ensure_tsv_files
  local choice
  while true; do
    echo; print_banner; echo
    echo "1. 快速组网（分步提示）"
    echo "2. 利群主机"
    echo "3. 公网入口"
    echo "4. 高级功能"
    echo "5. 一键诊断"
    echo "6. 卸载全部"
    echo "0. 退出"
    choice="$(prompt_menu_choice "请选择：")"
    case "$choice" in
      1) quick_networking_menu ;;
      2) relay_host_menu ;;
      3) entry_host_menu ;;
      4) advanced_menu ;;
      5) doctor ;;
      6) uninstall_new_mode ;;
      0) exit 0 ;;
      "") echo "请输入选项编号。" ;;
      *) echo "无效选择。" ;;
    esac
  done
}

main() {
  while [[ "${1:-}" == "--dry-run" ]]; do DRY_RUN=1; shift; done
  case "${1:-}" in
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
    --help|-h) print_help ;;
    --version|-v) echo "${PROJECT_NAME} ${TOOL_VERSION}" ;;
    --doctor|--validate) [[ "${2:-}" == "--verbose" ]] && VERBOSE_DOCTOR=1; doctor ;;
    --pbr-apply) pbr_apply ;;
    --uninstall) uninstall_new_mode ;;
    "") main_menu ;;
    *) fail "未知参数：$1"; print_help; exit 1 ;;
  esac
}

main "$@"
