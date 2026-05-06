#!/usr/bin/env bash
set -Eeuo pipefail

TOOL_VERSION="0.2.1-alpha"
PROJECT_NAME="leikwan-wg-toolkit"
PROJECT_TITLE="利群三机链式代理部署工具"
DRY_RUN=0
REBUILD_ROLE_OVERRIDE=""
REBUILD_VLESSENC_ENCRYPTION=""
REBUILD_CLOUD_ENDPOINT=""
REBUILD_CLIENT_ENTRY_PORT=""
REBUILD_LANDING_ADDRESS=""
REBUILD_LANDING_PORT=""
OUTPUTS_REBUILD_NOTICE_SHOWN=0

LOG_FILE="/var/log/leikwan-wg-toolkit.log"
OUTPUT_FILE="/root/leikwan-wg-toolkit-output.txt"
BACKUP_DIR="/var/backups/leikwan-wg-toolkit"
STATE_DIR="/etc/leikwan-wg-toolkit"
OUTPUT_DIR="${STATE_DIR}/outputs"
CLOUD_OUTPUT_FILE="${OUTPUT_DIR}/cloud-entry.env"
LANDING_OUTPUT_FILE="${OUTPUT_DIR}/landing-server.env"
RELAY_OUTPUT_FILE="${OUTPUT_DIR}/leikwan-relay.env"
CLIENT_LINK_FILE="${OUTPUT_DIR}/client-link.txt"
LEIKWAN_PEER_FILE="${OUTPUT_DIR}/leikwan-peer.env"
REALM_DIR="${STATE_DIR}/realm"
PBR_DIR="${STATE_DIR}/pbr"
PBR_STATE_DIR="/var/lib/leikwan-wg-toolkit/pbr"
PBR_STATIC_CONF="${PBR_DIR}/static-routes.conf"
PBR_DOMAIN_CONF="${PBR_DIR}/domain-routes.conf"
PBR_GROUP_CONF="${PBR_DIR}/route-groups.conf"
PBR_DOMAIN_STATE="${PBR_STATE_DIR}/domain-state.conf"
PBR_RT_TABLES="/etc/iproute2/rt_tables"
PBR_STATIC_PRIORITY="15000"
PBR_DOMAIN_PRIORITY="15005"
PBR_SERVICE_NAME="leikwan-pbr"
PBR_SERVICE="/etc/systemd/system/${PBR_SERVICE_NAME}.service"
PBR_DDNS_SERVICE_NAME="leikwan-pbr-ddns"
PBR_DDNS_SERVICE="/etc/systemd/system/${PBR_DDNS_SERVICE_NAME}.service"
PBR_DDNS_TIMER="/etc/systemd/system/${PBR_DDNS_SERVICE_NAME}.timer"

WG_NET_DEFAULT="10.198.1.0/24"
LEIKWAN_WG_CONF="/etc/wireguard/wg0.conf"
CLOUD_WG_CONF="/etc/wireguard/wg1.conf"
LEIKWAN_WG_PRIVATE_FILE="/etc/wireguard/wg0_privatekey"
LEIKWAN_WG_PUBLIC_FILE="/etc/wireguard/wg0_publickey"
CLOUD_WG_PRIVATE_FILE="/etc/wireguard/wg1_privatekey"
CLOUD_WG_PUBLIC_FILE="/etc/wireguard/wg1_publickey"
LEIKWAN_WG_ADDR="10.198.1.1/24"
CLOUD_WG_ADDR="10.198.1.2/24"
LEIKWAN_WG_IP="10.198.1.1"
CLOUD_WG_IP="10.198.1.2"
CLOUD_WG_PORT_DEFAULT="8301"
WG_MTU_DEFAULT="1280"
WG_KEEPALIVE_DEFAULT="25"

CLIENT_ENTRY_PORT_DEFAULT="30000"
LANDING_PORT_DEFAULT="30004"
LANDING_SERVER_NAME_DEFAULT="www.microsoft.com"
LANDING_TARGET_DEFAULT="www.microsoft.com:443"
LANDING_FLOW_DEFAULT="xtls-rprx-vision"

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/leikwan/config.json"
XRAY_LEIKWAN_SERVICE_NAME="xray-leikwan"
XRAY_LEIKWAN_SERVICE="/etc/systemd/system/${XRAY_LEIKWAN_SERVICE_NAME}.service"
XRAY_SYSTEM_SERVICE_NAME="xray"
XRAY_SYSTEM_SERVICE="/etc/systemd/system/${XRAY_SYSTEM_SERVICE_NAME}.service"
ACTIVE_XRAY_SERVICE_NAME="${XRAY_LEIKWAN_SERVICE_NAME}"
ACTIVE_XRAY_SERVICE="${XRAY_LEIKWAN_SERVICE}"
XRAY_MARKER_DIR="${STATE_DIR}/xray"
XRAY_VLESSENC_LAST="${XRAY_MARKER_DIR}/vlessenc-last.txt"
VLESSENC_DECRYPTION_RESULT=""
VLESSENC_ENCRYPTION_RESULT=""
WG_IDENTITY_PRIVATE=""
WG_IDENTITY_PUBLIC=""

REALM_ENTRY_STEM="realm-leikwan"
REALM_ENTRY_CONF="${REALM_DIR}/${REALM_ENTRY_STEM}.toml"
REALM_ENTRY_SERVICE="/etc/systemd/system/${REALM_ENTRY_STEM}.service"

if [[ -t 1 ]]; then
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  BOLD=""
  RESET=""
fi

on_error() {
  local rc=$?
  local line=${1:-unknown}
  log "错误：脚本在第 ${line} 行退出，退出码 ${rc}"
  echo "${RED}发生错误，已写入日志：${LOG_FILE}${RESET}" >&2
  exit "$rc"
}
trap 'on_error "$LINENO"' ERR

init_log() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE" || true
  fi
}

log() {
  local msg="$*"
  if [[ -e "$LOG_FILE" && -w "$LOG_FILE" ]]; then
    printf '[%s] %s\n' "$(date '+%F %T')" "$msg" >>"$LOG_FILE"
  fi
}

info() {
  echo "${BLUE}==>${RESET} $*"
  log "INFO $*"
}

ok() {
  echo "${GREEN}[OK]${RESET} $*"
  log "OK $*"
}

warn() {
  echo "${YELLOW}注意：${RESET}$*"
  log "WARN $*"
}

fail() {
  echo "${RED}错误：${RESET}$*" >&2
  log "ERROR $*"
}

run_cmd() {
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 跳过执行：$*"
    log "DRY-RUN skip command: $*"
    return 0
  fi

  log "执行：$*"
  local output
  if output="$("$@" 2>&1)"; then
    [[ -n "$output" ]] && log "$output"
    return 0
  fi
  local rc=$?
  [[ -n "$output" ]] && {
    log "$output"
    echo "$output" >&2
  }
  return "$rc"
}

print_help() {
  cat <<EOF
${PROJECT_NAME} ${TOOL_VERSION}
${PROJECT_TITLE}

用法：
  sudo bash wg-toolkit.sh
  bash wg-toolkit.sh --dry-run
  bash wg-toolkit.sh --validate
  bash wg-toolkit.sh --doctor
  sudo bash wg-toolkit.sh --uninstall
  bash wg-toolkit.sh --help
  bash wg-toolkit.sh --version

定位：
  公网入口机 <原生 WireGuard UDP> 利群中转机 <Xray VLESS/Reality> 海外落地机

限制：
  本项目只允许使用原生 WireGuard UDP 作为公网入口机到利群主机的传输层。
  不实现 FRP、UoT/Phantun、WireGuard over WSS、OpenVPN TCP、SoftEther、gost、udp2raw 等 TCP/fake TCP 隧道。

默认：
  WG 网段：${WG_NET_DEFAULT}
  公网入口机 wg1：${CLOUD_WG_ADDR}，监听 ${CLOUD_WG_PORT_DEFAULT}/udp
  利群中转机 wg0：${LEIKWAN_WG_ADDR}
  客户端入口端口：${CLIENT_ENTRY_PORT_DEFAULT}
  海外落地 Reality 端口：${LANDING_PORT_DEFAULT}

子命令：
  --dry-run    进入菜单，但角色部署只生成配置预览，不安装、不写入、不启动服务
  --validate   输出详细诊断报告
  --doctor     输出简洁诊断摘要
  --doctor --verbose     输出详细诊断报告
  --show-wg-identity     查看/生成本机 WireGuard 身份，不启动 wg，不写 Peer
  --show-wg-identity --role leikwan|cloud
  --rebuild-outputs      从当前已运行配置重建 outputs 和 /root 输出
  --vlessenc-encryption VALUE   配合 --rebuild-outputs 补充客户端 encryption
  --cloud-endpoint VALUE        配合 --rebuild-outputs 指定 CLOUD_ENDPOINT
  --client-entry-port VALUE     配合 --rebuild-outputs 指定 CLIENT_ENTRY_PORT
  --landing-address VALUE       配合 --rebuild-outputs 指定 LANDING_ADDRESS
  --landing-port VALUE          配合 --rebuild-outputs 指定 LANDING_PORT
  --pbr-apply             应用本项目保存的 IPv4 PBR 静态和域名规则
  --pbr-refresh-domains   刷新域名 A 记录并更新本项目 IPv4 PBR 域名规则
  --pbr-show              查看本项目 IPv4 PBR 配置和当前规则
  --pbr-audit             审计当前 IPv4 PBR 规则，不修改系统
  --pbr-import-existing   导入已有 priority 15000/15005 IPv4 PBR 规则
EOF
}

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "请使用 root 运行，例如：sudo bash wg-toolkit.sh"
    exit 1
  fi
}

need_root_unless_dry_run() {
  if (( DRY_RUN == 1 )); then
    warn "当前为 --dry-run，仅生成预览，不写入系统。"
    return 0
  fi
  need_root
}

ensure_supported_os() {
  if [[ ! -r /etc/os-release ]]; then
    fail "无法识别系统版本，仅支持 Debian 12/13、Ubuntu 22.04/24.04。"
    exit 1
  fi

  local os_id os_version pretty_name
  os_id="$(awk -F= '$1=="ID" {gsub(/"/, "", $2); print $2; exit}' /etc/os-release)"
  os_version="$(awk -F= '$1=="VERSION_ID" {gsub(/"/, "", $2); print $2; exit}' /etc/os-release)"
  pretty_name="$(awk -F= '$1=="PRETTY_NAME" {gsub(/"/, "", $2); print $2; exit}' /etc/os-release)"

  case "${os_id}:${os_version}" in
    debian:12|debian:13|ubuntu:22.04|ubuntu:24.04)
      ok "系统检查通过：${pretty_name:-${os_id} ${os_version}}"
      ;;
    *)
      fail "当前系统为 ${pretty_name:-unknown}，仅支持 Debian 12/13、Ubuntu 22.04/24.04。"
      exit 1
      ;;
  esac
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-N}"
  local suffix answer

  if [[ "$default" =~ ^[Yy]$ ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  while true; do
    read -r -p "${prompt} ${suffix} " answer
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "请输入 y 或 n。" ;;
    esac
  done
}

prompt_value() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "${prompt} [${default}]: " value
    printf '%s' "${value:-$default}"
  else
    read -r -p "${prompt}: " value
    printf '%s' "$value"
  fi
}

is_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

prompt_port() {
  local prompt="$1"
  local default="$2"
  local value
  while true; do
    value="$(prompt_value "$prompt" "$default")"
    if is_port "$value"; then
      printf '%s' "$value"
      return 0
    fi
    echo "端口必须是 1-65535 的数字。"
  done
}

validate_wg_key() {
  [[ "$1" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

prompt_wg_key() {
  local prompt="$1"
  local key
  while true; do
    key="$(prompt_value "$prompt")"
    if validate_wg_key "$key"; then
      printf '%s' "$key"
      return 0
    fi
    echo "WireGuard 公钥格式不正确，请确认复制完整。"
  done
}

prompt_wg_key_default() {
  local prompt="$1"
  local default="${2:-}"
  local key
  while true; do
    key="$(prompt_value "$prompt" "$default")"
    if validate_wg_key "$key"; then
      printf '%s' "$key"
      return 0
    fi
    echo "WireGuard 公钥格式不正确，请确认复制完整。"
  done
}

validate_endpoint_host() {
  [[ -n "$1" && ! "$1" =~ [[:space:]/] ]]
}

prompt_endpoint_host() {
  local prompt="$1"
  local default="${2:-}"
  local host
  while true; do
    host="$(prompt_value "$prompt" "$default")"
    if validate_endpoint_host "$host"; then
      printf '%s' "$host"
      return 0
    fi
    echo "请输入公网 IP 或域名，不要包含协议、端口或空格。"
  done
}

prompt_endpoint_host_default() {
  local prompt="$1"
  local default="${2:-}"
  prompt_endpoint_host "$prompt" "$default"
}

prompt_non_empty() {
  local prompt="$1"
  local default="${2:-}"
  local value
  while true; do
    value="$(prompt_value "$prompt" "$default")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
    echo "该项不能为空。"
  done
}

trim_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

script_self_path() {
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$0" 2>/dev/null || printf '%s' "$0"
  else
    printf '%s' "$0"
  fi
}

is_ipv4() {
  local ip="$1"
  local o1 o2 o3 o4
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r o1 o2 o3 o4 <<<"$ip"
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    (( octet >= 0 && octet <= 255 )) || return 1
  done
}

normalize_ipv4_cidr() {
  local value="$1"
  local ip prefix
  value="$(trim_spaces "$value")"
  [[ -n "$value" ]] || return 1
  if is_ipv4 "$value"; then
    printf '%s/32' "$value"
    return 0
  fi
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
  ip="${value%/*}"
  prefix="${value#*/}"
  is_ipv4 "$ip" || return 1
  (( prefix >= 0 && prefix <= 32 )) || return 1
  printf '%s' "$value"
}

backup_file() {
  local path="$1"
  [[ -e "$path" ]] || return 0

  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将备份：${path}"
    log "DRY-RUN backup ${path}"
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  local safe="${path#/}"
  safe="${safe//\//__}"
  local dest
  dest="${BACKUP_DIR}/${safe}.$(date '+%Y%m%d-%H%M%S').bak"

  cp -a "$path" "$dest"
  ok "已备份 ${path} -> ${dest}"
}

write_text_file() {
  local path="$1"
  local content="$2"
  local mode="${3:-600}"
  local tmp

  if (( DRY_RUN == 1 )); then
    echo
    echo "${BOLD}[DRY-RUN] 配置预览：${path} (mode ${mode})${RESET}"
    echo "----------------------------------------"
    printf '%s\n' "$content"
    echo "----------------------------------------"
    log "DRY-RUN preview file ${path}"
    return 0
  fi

  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp)"
  printf '%s\n' "$content" >"$tmp"

  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    ok "${path} 已是目标状态，跳过写入。"
    return 1
  fi

  backup_file "$path"
  install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
  ok "已写入 ${path}"
  return 0
}

write_output_file() {
  local role="$1"
  local content="$2"
  local final_content role_file=""

  final_content="$(cat <<EOF
# Generated by leikwan-wg-toolkit ${TOOL_VERSION}
# Role: ${role}
# Time: $(date '+%F %T %z')

${content}
EOF
)"

  case "$role" in
    cloud-entry) role_file="$CLOUD_OUTPUT_FILE" ;;
    landing-server) role_file="$LANDING_OUTPUT_FILE" ;;
    leikwan-relay) role_file="$RELAY_OUTPUT_FILE" ;;
    client-link) role_file="$CLIENT_LINK_FILE" ;;
  esac

  if (( DRY_RUN == 1 )); then
    echo
    echo "${BOLD}[DRY-RUN] 部署输出文件预览：${OUTPUT_FILE}${RESET}"
    echo "----------------------------------------"
    printf '%s\n' "$final_content"
    echo "----------------------------------------"
    if [[ -n "$role_file" ]]; then
      echo
      echo "${BOLD}[DRY-RUN] 角色输出文件预览：${role_file}${RESET}"
      echo "----------------------------------------"
      printf '%s\n' "$final_content"
      echo "----------------------------------------"
    fi
    return 0
  fi

  install -d -m 755 "$OUTPUT_DIR"
  if [[ -n "$role_file" ]]; then
    write_text_file "$role_file" "$final_content" 600 || true
    ok "角色输出已保存：${role_file}"
  fi
  write_text_file "$OUTPUT_FILE" "$final_content" 600 || true
  ok "部署输出已保存：${OUTPUT_FILE}"
}

print_copy_block() {
  local title="$1"
  local content="$2"
  local next="${3:-}"
  echo
  echo "=================================================="
  if (( DRY_RUN == 1 )); then
    echo "【DRY-RUN 预览参数，不能用于真实部署】"
    echo "【${title}】"
  else
    echo "【${title}】"
  fi
  printf '%s\n' "$content"
  echo "=================================================="
  if [[ -n "$next" ]]; then
    echo
    echo "下一步："
    printf '%s\n' "$next"
    echo "=================================================="
  fi
}

env_file_get() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  awk -F= -v k="$key" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

saved_param() {
  local key="$1"
  shift
  local file value
  for file in "$@"; do
    value="$(env_file_get "$file" "$key" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

rebuild_cli_param() {
  local key="$1"
  case "$key" in
    VLESSENC_ENCRYPTION) printf '%s' "$REBUILD_VLESSENC_ENCRYPTION" ;;
    CLOUD_ENDPOINT) printf '%s' "$REBUILD_CLOUD_ENDPOINT" ;;
    CLIENT_ENTRY_PORT) printf '%s' "$REBUILD_CLIENT_ENTRY_PORT" ;;
    LANDING_ADDRESS) printf '%s' "$REBUILD_LANDING_ADDRESS" ;;
    LANDING_PORT) printf '%s' "$REBUILD_LANDING_PORT" ;;
    *) return 1 ;;
  esac
}

saved_param_with_cli() {
  local key="$1"
  shift
  local value
  value="$(rebuild_cli_param "$key" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi
  saved_param "$key" "$@"
}

client_link_query_value() {
  local link="$1"
  local key="$2"
  local query pair k v
  local -a pairs
  query="${link#*\?}"
  [[ "$query" != "$link" ]] || return 1
  query="${query%%#*}"
  IFS='&' read -ra pairs <<<"$query"
  for pair in "${pairs[@]}"; do
    k="${pair%%=*}"
    v="${pair#*=}"
    if [[ "$k" == "$key" ]]; then
      printf '%s' "$v"
      return 0
    fi
  done
  return 1
}

urldecode() {
  local value="$1"
  printf '%b' "${value//%/\\x}"
}

parse_client_link_fields() {
  local link="$1"
  local rest authority uuid hostport endpoint port encryption
  [[ "$link" == vless://* ]] || return 1
  rest="${link#vless://}"
  rest="${rest%%#*}"
  if [[ "$rest" == *\?* ]]; then
    authority="${rest%%\?*}"
  else
    authority="$rest"
  fi
  [[ "$authority" == *@* ]] || return 1
  uuid="${authority%%@*}"
  hostport="${authority#*@}"
  endpoint="${hostport%:*}"
  port="${hostport##*:}"
  encryption="$(client_link_query_value "$link" encryption 2>/dev/null || true)"
  if [[ -n "$encryption" ]]; then
    encryption="$(urldecode "$encryption")"
  fi
  [[ -n "$uuid" ]] && printf 'ENTRY_UUID=%s\n' "$uuid"
  [[ -n "$endpoint" && "$endpoint" != "$hostport" ]] && printf 'CLOUD_ENDPOINT=%s\n' "$endpoint"
  [[ -n "$port" && "$port" != "$hostport" ]] && printf 'CLIENT_ENTRY_PORT=%s\n' "$port"
  [[ -n "$encryption" ]] && printf 'VLESSENC_ENCRYPTION=%s\n' "$encryption"
}

client_link_field() {
  local link="$1"
  local key="$2"
  parse_client_link_fields "$link" | awk -F= -v k="$key" '$1 == k {sub(/^[^=]*=/, ""); print; exit}'
}

migrate_legacy_client_link_output() {
  [[ -f "$OUTPUT_FILE" ]] || return 1
  local link content parsed key value
  link="$(env_file_get "$OUTPUT_FILE" CLIENT_LINK 2>/dev/null || true)"
  [[ -n "$link" ]] || return 1
  parsed="$(parse_client_link_fields "$link" 2>/dev/null || true)"
  content=""
  for key in ENTRY_UUID VLESSENC_ENCRYPTION CLOUD_ENDPOINT CLIENT_ENTRY_PORT LANDING_ADDRESS LANDING_PORT; do
    value="$(env_file_get "$OUTPUT_FILE" "$key" 2>/dev/null || true)"
    if [[ -z "$value" ]]; then
      value="$(awk -F= -v k="$key" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' <<<"$parsed")"
    fi
    printf -v content '%s%s=%s\n' "$content" "$key" "$value"
  done
  printf -v content '%sCLIENT_LINK=%s' "$content" "$link"
  write_output_file "client-link" "$content"
  ok "已从 ${OUTPUT_FILE} 迁移 CLIENT_LINK 到 ${CLIENT_LINK_FILE}"
}

infer_env_role() {
  local content="$1"
  if grep -q '^CLIENT_LINK=' <<<"$content"; then
    printf '%s' "leikwan-relay"
  elif grep -q '^CLOUD_PUBLIC_KEY=' <<<"$content"; then
    printf '%s' "cloud-entry"
  elif grep -q '^LANDING_ADDRESS=' <<<"$content"; then
    printf '%s' "landing-server"
  else
    printf '%s' "unknown"
  fi
}

validate_env_content() {
  local role="$1"
  local content="$2"
  local missing="" key
  case "$role" in
    cloud-entry)
      for key in CLOUD_PUBLIC_KEY CLOUD_ENDPOINT CLOUD_WG_PORT CLIENT_ENTRY_PORT; do
        grep -q "^${key}=" <<<"$content" || missing="${missing}${key} "
      done
      ;;
    landing-server)
      for key in LANDING_ADDRESS LANDING_PORT LANDING_UUID LANDING_PUBLIC_KEY LANDING_SHORT_ID LANDING_SERVER_NAME LANDING_FLOW; do
        grep -q "^${key}=" <<<"$content" || missing="${missing}${key} "
      done
      ;;
    leikwan-relay)
      grep -q '^CLIENT_LINK=' <<<"$content" || missing="CLIENT_LINK "
      ;;
    *)
      missing="无法识别参数文件角色 "
      ;;
  esac
  if [[ -n "$missing" ]]; then
    fail "参数文件缺少：${missing}"
    return 1
  fi
}

import_params_file() {
  need_root_unless_dry_run
  init_log
  local input content role target summary line
  echo
  echo "请输入 env 文件路径，或直接粘贴 KEY=value 内容。"
  input="$(prompt_non_empty "路径或第一行")"
  if [[ -f "$input" ]]; then
    content="$(grep -E '^[A-Z0-9_]+=' "$input" || true)"
  else
    content="$input"
    echo "继续粘贴，每行 KEY=value；输入空行结束。"
    while IFS= read -r line; do
      [[ -z "$line" ]] && break
      content="${content}"$'\n'"${line}"
    done
    content="$(printf '%s\n' "$content" | grep -E '^[A-Z0-9_]+=' || true)"
  fi
  role="$(infer_env_role "$content")"
  validate_env_content "$role" "$content" || return 1
  case "$role" in
    cloud-entry) target="$CLOUD_OUTPUT_FILE" ;;
    landing-server) target="$LANDING_OUTPUT_FILE" ;;
    leikwan-relay) target="$RELAY_OUTPUT_FILE" ;;
    *) return 1 ;;
  esac
  summary="识别角色：${role}\n写入：${target}\n内容：\n${content}"
  if ! confirm_summary "导入参数文件摘要" "$summary"; then
    return 0
  fi
  write_output_file "$role" "$content"
  if [[ "$role" == "leikwan-relay" ]] && grep -q '^CLIENT_LINK=' <<<"$content"; then
    write_output_file "client-link" "$content"
  fi
}

cloud_import_leikwan_public_key() {
  need_root_unless_dry_run
  init_log
  local key content summary
  key="$(prompt_wg_key "请粘贴利群中转机 LEIKWAN_PUBLIC_KEY")"
  content="LEIKWAN_PUBLIC_KEY=${key}"
  summary="写入：${LEIKWAN_PEER_FILE}\n用途：公网入口机部署 wg1 时自动填入利群 Peer PublicKey。\n\n${content}"
  if ! confirm_summary "导入 LEIKWAN_PUBLIC_KEY 摘要" "$summary"; then
    return 0
  fi
  write_text_file "$LEIKWAN_PEER_FILE" "$content" 600 || true
  print_copy_block "已保存利群 PublicKey" "$content"
}

view_client_link() {
  local link=""
  link="$(env_file_get "$CLIENT_LINK_FILE" CLIENT_LINK 2>/dev/null || true)"
  [[ -z "$link" ]] && link="$(env_file_get "$RELAY_OUTPUT_FILE" CLIENT_LINK 2>/dev/null || true)"
  [[ -z "$link" ]] && link="$(env_file_get "$OUTPUT_FILE" CLIENT_LINK 2>/dev/null || true)"
  if [[ -z "$link" ]]; then
    migrate_legacy_client_link_output >/dev/null 2>&1 || true
    link="$(env_file_get "$CLIENT_LINK_FILE" CLIENT_LINK 2>/dev/null || true)"
  elif [[ ! -s "$CLIENT_LINK_FILE" && -f "$OUTPUT_FILE" ]]; then
    migrate_legacy_client_link_output || true
  fi
  if [[ -z "$link" ]]; then
    warn "未找到 CLIENT_LINK。缺少 VLESSENC_ENCRYPTION 时无法生成链接。"
    echo "请运行：bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption 'mlkem...'"
    return 1
  fi
  print_copy_block "客户端导入链接" "CLIENT_LINK=${link}"
}

parse_wg_listen_port() {
  local conf="$1"
  [[ -f "$conf" ]] || return 1
  awk -F= 'tolower($1) ~ /^[[:space:]]*listenport[[:space:]]*$/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$conf"
}

parse_wg_endpoint_host() {
  local conf="$1"
  [[ -f "$conf" ]] || return 1
  awk -F= 'tolower($1) ~ /^[[:space:]]*endpoint[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); sub(/:[0-9]+$/, "", $2); print $2; exit}' "$conf"
}

parse_wg_endpoint_port() {
  local conf="$1"
  [[ -f "$conf" ]] || return 1
  awk -F= 'tolower($1) ~ /^[[:space:]]*endpoint[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); n=split($2, a, ":"); print a[n]; exit}' "$conf"
}

parse_realm_listen_port() {
  [[ -f "$REALM_ENTRY_CONF" ]] || return 1
  awk -F= '/^[[:space:]]*listen[[:space:]]*=/ {
    gsub(/["[:space:]]/, "", $2)
    n=split($2, a, ":")
    print a[n]
    exit
  }' "$REALM_ENTRY_CONF"
}

xray_public_from_private() {
  local private_key="$1"
  local output public_key
  [[ -x "$XRAY_BIN" ]] || return 1
  output="$("$XRAY_BIN" x25519 -i "$private_key" 2>/dev/null || true)"
  public_key="$(printf '%s\n' "$output" | awk -F': *' 'tolower($1) ~ /public/ {print $2; exit}')"
  [[ -n "$public_key" ]] || return 1
  printf '%s' "$public_key"
}

xray_relay_inbound_field() {
  local field="$1"
  [[ -f "$XRAY_CONFIG" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  case "$field" in
    port)
      jq -r '.inbounds[]? | select(.protocol=="vless") | select((.settings.decryption // "") != "none") | .port // empty' "$XRAY_CONFIG" | head -n 1
      ;;
    id)
      jq -r '.inbounds[]? | select(.protocol=="vless") | select((.settings.decryption // "") != "none") | .settings.clients[0].id // empty' "$XRAY_CONFIG" | head -n 1
      ;;
    decryption)
      jq -r '.inbounds[]? | select(.protocol=="vless") | select((.settings.decryption // "") != "none") | .settings.decryption // empty' "$XRAY_CONFIG" | head -n 1
      ;;
  esac
}

xray_relay_outbound_field() {
  local field="$1"
  [[ -f "$XRAY_CONFIG" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  case "$field" in
    address)
      jq -r '.outbounds[]? | select(.tag=="proxy" or .tag=="landing-reality-out" or .protocol=="vless") | .settings.vnext[0].address // empty' "$XRAY_CONFIG" | head -n 1
      ;;
    port)
      jq -r '.outbounds[]? | select(.tag=="proxy" or .tag=="landing-reality-out" or .protocol=="vless") | .settings.vnext[0].port // empty' "$XRAY_CONFIG" | head -n 1
      ;;
    id)
      jq -r '.outbounds[]? | select(.tag=="proxy" or .tag=="landing-reality-out" or .protocol=="vless") | .settings.vnext[0].users[0].id // empty' "$XRAY_CONFIG" | head -n 1
      ;;
    publicKey)
      jq -r '.outbounds[]? | select(.tag=="proxy" or .tag=="landing-reality-out" or .protocol=="vless") | .streamSettings.realitySettings.publicKey // empty' "$XRAY_CONFIG" | head -n 1
      ;;
    shortId)
      jq -r '.outbounds[]? | select(.tag=="proxy" or .tag=="landing-reality-out" or .protocol=="vless") | .streamSettings.realitySettings.shortId // empty' "$XRAY_CONFIG" | head -n 1
      ;;
    serverName)
      jq -r '.outbounds[]? | select(.tag=="proxy" or .tag=="landing-reality-out" or .protocol=="vless") | .streamSettings.realitySettings.serverName // empty' "$XRAY_CONFIG" | head -n 1
      ;;
  esac
}

rebuild_cloud_output() {
  local public_key="" endpoint="" wg_port="" entry_port="" content=""
  public_key="$(wg show wg1 public-key 2>/dev/null || true)"
  if [[ -z "$public_key" ]]; then
    ensure_wg_identity "wg1" || return 1
    public_key="$WG_IDENTITY_PUBLIC"
  fi
  endpoint="$(saved_param_with_cli CLOUD_ENDPOINT "$CLOUD_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$endpoint" ]] && endpoint="$(detect_public_ipv4)"
  [[ -z "$endpoint" ]] && endpoint="$(prompt_endpoint_host "请输入公网入口机 CLOUD_ENDPOINT")"
  wg_port="$(parse_wg_listen_port "$CLOUD_WG_CONF" 2>/dev/null || true)"
  wg_port="${wg_port:-$CLOUD_WG_PORT_DEFAULT}"
  entry_port="$(saved_param_with_cli CLIENT_ENTRY_PORT "$CLOUD_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$entry_port" ]] && entry_port="$(parse_realm_listen_port 2>/dev/null || true)"
  entry_port="${entry_port:-$CLIENT_ENTRY_PORT_DEFAULT}"
  content="$(cat <<EOF
CLOUD_PUBLIC_KEY=${public_key}
CLOUD_ENDPOINT=${endpoint}
CLOUD_WG_PORT=${wg_port}
CLIENT_ENTRY_PORT=${entry_port}
EOF
)"
  write_output_file "cloud-entry" "$content"
  print_copy_block "复制回利群中转机" "$content"
}

rebuild_landing_output() {
  local landing_address="" landing_port="" landing_uuid="" landing_public_key="" landing_short_id="" landing_server_name="" landing_flow="" private_key="" content=""
  [[ -f "$XRAY_CONFIG" ]] || {
    fail "未找到 ${XRAY_CONFIG}，无法重建落地机输出。"
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    fail "需要 jq 解析 Xray 配置。"
    return 1
  }
  landing_address="$(saved_param_with_cli LANDING_ADDRESS "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_address" ]] && landing_address="$(detect_public_ipv4)"
  [[ -z "$landing_address" ]] && landing_address="$(prompt_endpoint_host "请输入海外落地机 LANDING_ADDRESS")"
  landing_port="$(saved_param_with_cli LANDING_PORT "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_port" ]] && landing_port="$(jq -r '.inbounds[]? | select(.streamSettings.security=="reality") | .port // empty' "$XRAY_CONFIG" | head -n 1)"
  landing_uuid="$(jq -r '.inbounds[]? | select(.streamSettings.security=="reality") | .settings.clients[0].id // empty' "$XRAY_CONFIG" | head -n 1)"
  landing_flow="$(jq -r '.inbounds[]? | select(.streamSettings.security=="reality") | .settings.clients[0].flow // empty' "$XRAY_CONFIG" | head -n 1)"
  landing_short_id="$(jq -r '.inbounds[]? | select(.streamSettings.security=="reality") | .streamSettings.realitySettings.shortIds[0] // empty' "$XRAY_CONFIG" | head -n 1)"
  landing_server_name="$(jq -r '.inbounds[]? | select(.streamSettings.security=="reality") | .streamSettings.realitySettings.serverNames[0] // empty' "$XRAY_CONFIG" | head -n 1)"
  private_key="$(jq -r '.inbounds[]? | select(.streamSettings.security=="reality") | .streamSettings.realitySettings.privateKey // empty' "$XRAY_CONFIG" | head -n 1)"
  landing_public_key="$(saved_param LANDING_PUBLIC_KEY "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_public_key" && -n "$private_key" ]] && landing_public_key="$(xray_public_from_private "$private_key" 2>/dev/null || true)"
  [[ -z "$landing_public_key" ]] && landing_public_key="$(prompt_non_empty "无法从配置反推 LANDING_PUBLIC_KEY，请输入 LANDING_PUBLIC_KEY")"
  landing_flow="${landing_flow:-$LANDING_FLOW_DEFAULT}"
  content="$(cat <<EOF
LANDING_ADDRESS=${landing_address}
LANDING_PORT=${landing_port:-$LANDING_PORT_DEFAULT}
LANDING_UUID=${landing_uuid}
LANDING_PUBLIC_KEY=${landing_public_key}
LANDING_SHORT_ID=${landing_short_id}
LANDING_SERVER_NAME=${landing_server_name:-$LANDING_SERVER_NAME_DEFAULT}
LANDING_FLOW=${landing_flow}
EOF
)"
  write_output_file "landing-server" "$content"
  print_copy_block "复制到利群中转机" "$content"
}

rebuild_relay_output() {
  local wg_public="" cloud_endpoint="" cloud_port="" client_entry_port="" entry_uuid=""
  local vless_decryption="" vless_encryption="" landing_address="" landing_port=""
  local landing_uuid="" landing_public_key="" landing_short_id="" landing_server_name=""
  local encoded_encryption="" client_link="" relay_content="" link_content="" old_client_link="" missing_link_fields=""
  local prefer_existing_link=1
  wg_public="$(wg show wg0 public-key 2>/dev/null || true)"
  if [[ -z "$wg_public" ]]; then
    ensure_wg_identity "wg0" || return 1
    wg_public="$WG_IDENTITY_PUBLIC"
  fi
  command -v jq >/dev/null 2>&1 || {
    fail "需要 jq 解析 Xray 配置。"
    return 1
  }
  [[ -f "$XRAY_CONFIG" ]] || {
    fail "未找到 ${XRAY_CONFIG}，无法重建利群输出。"
    return 1
  }
  old_client_link="$(saved_param CLIENT_LINK "$CLIENT_LINK_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  if [[ -n "$old_client_link" && ! -s "$CLIENT_LINK_FILE" ]]; then
    migrate_legacy_client_link_output || true
  fi
  if [[ -n "$REBUILD_VLESSENC_ENCRYPTION$REBUILD_CLOUD_ENDPOINT$REBUILD_CLIENT_ENTRY_PORT" ]]; then
    prefer_existing_link=0
  fi

  cloud_endpoint="$(saved_param_with_cli CLOUD_ENDPOINT "$CLOUD_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$cloud_endpoint" && -n "$old_client_link" ]] && cloud_endpoint="$(client_link_field "$old_client_link" CLOUD_ENDPOINT 2>/dev/null || true)"
  [[ -z "$cloud_endpoint" ]] && cloud_endpoint="$(parse_wg_endpoint_host "$LEIKWAN_WG_CONF" 2>/dev/null || true)"
  [[ -z "$cloud_endpoint" ]] && cloud_endpoint="$(prompt_endpoint_host "请输入 CLOUD_ENDPOINT")"
  cloud_port="$(saved_param CLOUD_WG_PORT "$CLOUD_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$cloud_port" ]] && cloud_port="$(parse_wg_endpoint_port "$LEIKWAN_WG_CONF" 2>/dev/null || true)"
  cloud_port="${cloud_port:-$CLOUD_WG_PORT_DEFAULT}"
  client_entry_port="$(saved_param_with_cli CLIENT_ENTRY_PORT "$CLIENT_LINK_FILE" "$CLOUD_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$client_entry_port" && -n "$old_client_link" ]] && client_entry_port="$(client_link_field "$old_client_link" CLIENT_ENTRY_PORT 2>/dev/null || true)"
  [[ -z "$client_entry_port" ]] && client_entry_port="$(xray_relay_inbound_field port 2>/dev/null || true)"
  client_entry_port="${client_entry_port:-$CLIENT_ENTRY_PORT_DEFAULT}"
  entry_uuid="$(saved_param ENTRY_UUID "$CLIENT_LINK_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$entry_uuid" && -n "$old_client_link" ]] && entry_uuid="$(client_link_field "$old_client_link" ENTRY_UUID 2>/dev/null || true)"
  [[ -z "$entry_uuid" ]] && entry_uuid="$(xray_relay_inbound_field id 2>/dev/null || true)"
  vless_decryption="$(saved_param VLESSENC_DECRYPTION "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$vless_decryption" ]] && vless_decryption="$(xray_relay_inbound_field decryption 2>/dev/null || true)"
  landing_address="$(saved_param_with_cli LANDING_ADDRESS "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_address" ]] && landing_address="$(xray_relay_outbound_field address 2>/dev/null || true)"
  landing_port="$(saved_param_with_cli LANDING_PORT "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_port" ]] && landing_port="$(xray_relay_outbound_field port 2>/dev/null || true)"
  landing_uuid="$(saved_param LANDING_UUID "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_uuid" ]] && landing_uuid="$(xray_relay_outbound_field id 2>/dev/null || true)"
  landing_public_key="$(saved_param LANDING_PUBLIC_KEY "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_public_key" ]] && landing_public_key="$(xray_relay_outbound_field publicKey 2>/dev/null || true)"
  landing_short_id="$(saved_param LANDING_SHORT_ID "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_short_id" ]] && landing_short_id="$(xray_relay_outbound_field shortId 2>/dev/null || true)"
  landing_server_name="$(saved_param LANDING_SERVER_NAME "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -z "$landing_server_name" ]] && landing_server_name="$(xray_relay_outbound_field serverName 2>/dev/null || true)"
  vless_encryption="$(saved_param_with_cli VLESSENC_ENCRYPTION "$CLIENT_LINK_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  if [[ -z "$vless_encryption" && -n "$old_client_link" ]]; then
    vless_encryption="$(client_link_field "$old_client_link" VLESSENC_ENCRYPTION 2>/dev/null || true)"
  fi

  if (( prefer_existing_link == 1 )) && [[ -n "$old_client_link" ]]; then
    client_link="$old_client_link"
  elif [[ -n "$vless_encryption" ]]; then
    encoded_encryption="$(urlencode "$vless_encryption")"
    [[ -z "$entry_uuid" ]] && missing_link_fields="${missing_link_fields} ENTRY_UUID"
    [[ -z "$cloud_endpoint" ]] && missing_link_fields="${missing_link_fields} CLOUD_ENDPOINT"
    [[ -z "$client_entry_port" ]] && missing_link_fields="${missing_link_fields} CLIENT_ENTRY_PORT"
    if [[ -z "$missing_link_fields" ]]; then
      client_link="vless://${entry_uuid}@${cloud_endpoint}:${client_entry_port}?type=raw&security=none&encryption=${encoded_encryption}#Leikwan-WG-Xray-Reality"
    fi
  fi

  relay_content="$(cat <<EOF
ENTRY_UUID=${entry_uuid}
VLESSENC_DECRYPTION=${vless_decryption}
VLESSENC_ENCRYPTION=${vless_encryption}
CLOUD_ENDPOINT=${cloud_endpoint}
CLOUD_WG_PORT=${cloud_port}
CLIENT_ENTRY_PORT=${client_entry_port}
LANDING_ADDRESS=${landing_address}
LANDING_PORT=${landing_port}
LANDING_UUID=${landing_uuid}
LANDING_PUBLIC_KEY=${landing_public_key}
LANDING_SHORT_ID=${landing_short_id}
LANDING_SERVER_NAME=${landing_server_name}
LEIKWAN_PUBLIC_KEY=${wg_public}
CLIENT_LINK=${client_link}
EOF
)"
  write_output_file "leikwan-relay" "$relay_content"

  if [[ -n "$client_link" ]]; then
    link_content="$(cat <<EOF
ENTRY_UUID=${entry_uuid}
VLESSENC_ENCRYPTION=${vless_encryption}
CLOUD_ENDPOINT=${cloud_endpoint}
CLIENT_ENTRY_PORT=${client_entry_port}
LANDING_ADDRESS=${landing_address}
LANDING_PORT=${landing_port}
CLIENT_LINK=${client_link}
EOF
)"
    write_output_file "client-link" "$link_content"
    print_copy_block "客户端导入链接" "CLIENT_LINK=${client_link}"
  elif [[ -z "$vless_encryption" ]]; then
    warn "缺少 VLESSENC_ENCRYPTION，无法生成 CLIENT_LINK。"
    echo "请运行：bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption 'mlkem...'"
  else
    warn "缺少生成 CLIENT_LINK 的必要字段：${missing_link_fields}"
  fi
}

rebuild_outputs() {
  need_root_unless_dry_run
  init_log
  local role="${1:-${REBUILD_ROLE_OVERRIDE:-$(detect_current_role)}}"
  case "$role" in
    cloud-entry) rebuild_cloud_output ;;
    landing-server) rebuild_landing_output ;;
    leikwan-relay) rebuild_relay_output ;;
    multiple:*)
      role_has "$role" "cloud-entry" && rebuild_cloud_output || true
      role_has "$role" "landing-server" && rebuild_landing_output || true
      role_has "$role" "leikwan-relay" && rebuild_relay_output || true
      ;;
    *)
      fail "无法识别当前角色，请先部署或使用高级功能。"
      return 1
      ;;
  esac
}

parse_rebuild_cli_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role)
        REBUILD_ROLE_OVERRIDE="${2:-}"
        [[ -n "$REBUILD_ROLE_OVERRIDE" ]] || { fail "--role 需要参数"; return 1; }
        shift 2
        ;;
      --vlessenc-encryption)
        REBUILD_VLESSENC_ENCRYPTION="${2:-}"
        [[ -n "$REBUILD_VLESSENC_ENCRYPTION" ]] || { fail "--vlessenc-encryption 需要参数"; return 1; }
        shift 2
        ;;
      --cloud-endpoint)
        REBUILD_CLOUD_ENDPOINT="${2:-}"
        [[ -n "$REBUILD_CLOUD_ENDPOINT" ]] || { fail "--cloud-endpoint 需要参数"; return 1; }
        shift 2
        ;;
      --client-entry-port)
        REBUILD_CLIENT_ENTRY_PORT="${2:-}"
        [[ -n "$REBUILD_CLIENT_ENTRY_PORT" ]] || { fail "--client-entry-port 需要参数"; return 1; }
        shift 2
        ;;
      --landing-address)
        REBUILD_LANDING_ADDRESS="${2:-}"
        [[ -n "$REBUILD_LANDING_ADDRESS" ]] || { fail "--landing-address 需要参数"; return 1; }
        shift 2
        ;;
      --landing-port)
        REBUILD_LANDING_PORT="${2:-}"
        [[ -n "$REBUILD_LANDING_PORT" ]] || { fail "--landing-port 需要参数"; return 1; }
        shift 2
        ;;
      *)
        fail "未知 --rebuild-outputs 参数：$1"
        return 1
        ;;
    esac
  done
}

maybe_offer_rebuild_outputs() {
  local role="$1"
  local missing=0
  if (( OUTPUTS_REBUILD_NOTICE_SHOWN == 1 )); then
    return 0
  fi
  case "$role" in
    cloud-entry) [[ -s "$CLOUD_OUTPUT_FILE" ]] || missing=1 ;;
    landing-server) [[ -s "$LANDING_OUTPUT_FILE" ]] || missing=1 ;;
    leikwan-relay) [[ -s "$CLIENT_LINK_FILE" || -s "$RELAY_OUTPUT_FILE" ]] || missing=1 ;;
    *) return 0 ;;
  esac
  if (( missing == 1 )); then
    OUTPUTS_REBUILD_NOTICE_SHOWN=1
    warn "检测到已有可用链路或配置，但缺少 outputs。"
    if prompt_yes_no "是否从当前配置重建输出文件？" "Y"; then
      rebuild_outputs "$role" || true
    fi
  fi
}

outputs_missing_for_role() {
  local role="$1"
  if role_has "$role" "cloud-entry" && [[ ! -s "$CLOUD_OUTPUT_FILE" ]]; then
    return 0
  fi
  if role_has "$role" "landing-server" && [[ ! -s "$LANDING_OUTPUT_FILE" ]]; then
    return 0
  fi
  if role_has "$role" "leikwan-relay" && [[ ! -s "$CLIENT_LINK_FILE" ]]; then
    return 0
  fi
  return 1
}

notice_outputs_missing() {
  local role="$1"
  if (( OUTPUTS_REBUILD_NOTICE_SHOWN == 1 )); then
    return 0
  fi
  outputs_missing_for_role "$role" || return 0
  OUTPUTS_REBUILD_NOTICE_SHOWN=1
  validate_report warn "outputs 缺失，可运行：bash wg-toolkit.sh --rebuild-outputs"
  if role_has "$role" "leikwan-relay"; then
    validate_report warn "如需生成 CLIENT_LINK，请补充：bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption 'mlkem...'"
  fi
}

show_copy_params() {
  local role
  role="$(detect_current_role)"
  maybe_offer_rebuild_outputs "$role"
  echo
  echo "${BOLD}查看复制参数 / 客户端链接${RESET}"
  echo "当前角色：${role}"
  case "$role" in
    landing-server)
      if [[ -s "$LANDING_OUTPUT_FILE" ]]; then
        print_copy_block "复制到利群中转机" "$(grep -E '^[A-Z0-9_]+=' "$LANDING_OUTPUT_FILE")"
      else
        rebuild_landing_output || true
      fi
      ;;
    cloud-entry)
      if [[ -s "$CLOUD_OUTPUT_FILE" ]]; then
        print_copy_block "复制回利群中转机" "$(grep -E '^[A-Z0-9_]+=' "$CLOUD_OUTPUT_FILE")"
      else
        rebuild_cloud_output || true
      fi
      ;;
    leikwan-relay)
      show_wg_identity_for_iface "wg0" "card" || true
      if [[ -s "$CLOUD_OUTPUT_FILE" ]]; then
        ok "CLOUD 参数已导入：${CLOUD_OUTPUT_FILE}"
      else
        warn "CLOUD 参数未导入。"
      fi
      if [[ -s "$LANDING_OUTPUT_FILE" ]]; then
        ok "LANDING 参数已导入：${LANDING_OUTPUT_FILE}"
      else
        warn "LANDING 参数未导入。"
      fi
      view_client_link || true
      ;;
    *)
      warn "未知角色。可在高级功能中手动导入参数，或运行 --rebuild-outputs。"
      ;;
  esac
}

confirm_summary() {
  local title="$1"
  local summary="$2"
  echo
  if (( DRY_RUN == 1 )); then
    echo "${BOLD}${title}（DRY-RUN，仅生成预览，不写入系统）${RESET}"
  else
    echo "${BOLD}${title}${RESET}"
  fi
  echo "----------------------------------------"
  printf '%b\n' "$summary"
  echo "----------------------------------------"
  if (( DRY_RUN == 1 )); then
    prompt_yes_no "确认继续生成配置预览吗？" "Y"
  else
    prompt_yes_no "确认继续写入/执行以上配置吗？" "N"
  fi
}

install_packages() {
  local packages=("$@")
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将安装依赖：${packages[*]}"
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  info "安装依赖：${packages[*]}"
  run_cmd apt-get update
  run_cmd apt-get install -y "${packages[@]}"
}

ensure_wireguard_dir() {
  install -d -m 700 /etc/wireguard
}

install_wireguard_deps() {
  ensure_supported_os
  install_packages wireguard-tools curl wget jq qrencode iptables iproute2 ca-certificates
}

install_xray_deps() {
  ensure_supported_os
  install_packages curl wget jq unzip ca-certificates openssl
}

extract_private_key() {
  local conf="$1"
  [[ -f "$conf" ]] || return 1
  grep -Eim1 '^[[:space:]]*PrivateKey[[:space:]]*=' "$conf" \
    | sed -E 's/^[^=]+=//; s/^[[:space:]]+//; s/[[:space:]]+$//' || true
}

public_from_private() {
  if [[ "$1" == DRYRUN_PRIVATE_KEY_PLACEHOLDER_* ]]; then
    printf '%s\n' "DRYRUN_PUBLIC_KEY_PLACEHOLDER_0000000000000="
    return 0
  fi
  printf '%s' "$1" | wg pubkey
}

wg_conf_for_iface() {
  case "$1" in
    wg0) printf '%s' "$LEIKWAN_WG_CONF" ;;
    wg1) printf '%s' "$CLOUD_WG_CONF" ;;
    *) return 1 ;;
  esac
}

wg_private_file_for_iface() {
  case "$1" in
    wg0) printf '%s' "$LEIKWAN_WG_PRIVATE_FILE" ;;
    wg1) printf '%s' "$CLOUD_WG_PRIVATE_FILE" ;;
    *) return 1 ;;
  esac
}

wg_public_file_for_iface() {
  case "$1" in
    wg0) printf '%s' "$LEIKWAN_WG_PUBLIC_FILE" ;;
    wg1) printf '%s' "$CLOUD_WG_PUBLIC_FILE" ;;
    *) return 1 ;;
  esac
}

wg_address_for_iface() {
  case "$1" in
    wg0) printf '%s' "$LEIKWAN_WG_ADDR" ;;
    wg1) printf '%s' "$CLOUD_WG_ADDR" ;;
    *) return 1 ;;
  esac
}

wg_role_for_iface() {
  case "$1" in
    wg0) printf '%s' "leikwan-relay" ;;
    wg1) printf '%s' "cloud-entry" ;;
    *) printf '%s' "unknown" ;;
  esac
}

read_key_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  sed -n '1p' "$file" | tr -d '[:space:]'
}

write_wg_key_files() {
  local private_file="$1"
  local public_file="$2"
  local private_key="$3"
  local public_key="$4"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将写入 WireGuard key 文件：${private_file} / ${public_file}"
    return 0
  fi
  ensure_wireguard_dir
  write_text_file "$private_file" "$private_key" 600 || true
  write_text_file "$public_file" "$public_key" 644 || true
}

ensure_wg_identity() {
  local iface="$1"
  local conf private_file public_file key_private="" conf_private="" selected="" public_key="" choice
  if (( DRY_RUN == 0 )) && ! command -v wg >/dev/null 2>&1; then
    install_wireguard_deps
  fi
  conf="$(wg_conf_for_iface "$iface")" || return 1
  private_file="$(wg_private_file_for_iface "$iface")" || return 1
  public_file="$(wg_public_file_for_iface "$iface")" || return 1

  key_private="$(read_key_file "$private_file" 2>/dev/null || true)"
  conf_private="$(extract_private_key "$conf" 2>/dev/null || true)"

  if [[ -n "$key_private" ]] && ! validate_wg_key "$key_private"; then
    fail "${private_file} 存在但格式不正确。为避免静默重置，请手动检查或使用重置菜单。"
    return 1
  fi
  if [[ -n "$conf_private" ]] && ! validate_wg_key "$conf_private"; then
    fail "${conf} 中 PrivateKey 格式不正确。"
    return 1
  fi

  if [[ -n "$key_private" && -n "$conf_private" && "$key_private" != "$conf_private" ]]; then
    warn "检测到 WireGuard key 冲突：${private_file} 与 ${conf} 中 PrivateKey 不一致。"
    echo "1. 使用 key 文件：${private_file}" >&2
    echo "2. 使用 conf 文件：${conf}" >&2
    echo "3. 取消（默认）" >&2
    read -r -p "请选择 [3]: " choice
    choice="${choice:-3}"
    case "$choice" in
      1) selected="$key_private" ;;
      2) selected="$conf_private" ;;
      3) fail "已取消，未修改 WireGuard key。"; return 1 ;;
      *) fail "选择无效，已取消。"; return 1 ;;
    esac
  elif [[ -n "$key_private" ]]; then
    selected="$key_private"
    log "复用 WireGuard key 文件：${private_file}"
  elif [[ -n "$conf_private" ]]; then
    selected="$conf_private"
    echo "从 ${conf} 提取 PrivateKey，并补写 key 文件。" >&2
    log "从 ${conf} 提取 PrivateKey，并补写 key 文件。"
  else
    if (( DRY_RUN == 1 )) && ! command -v wg >/dev/null 2>&1; then
      selected="DRYRUN_PRIVATE_KEY_PLACEHOLDER_000000000000="
    else
      selected="$(wg genkey)"
    fi
    echo "已生成新的 WireGuard key：${iface}" >&2
    log "已生成新的 WireGuard key：${iface}"
  fi

  public_key="$(public_from_private "$selected")"
  if [[ -z "$(read_key_file "$private_file" 2>/dev/null || true)" || "$(read_key_file "$private_file" 2>/dev/null || true)" != "$selected" ]]; then
    write_wg_key_files "$private_file" "$public_file" "$selected" "$public_key"
  elif [[ "$(read_key_file "$public_file" 2>/dev/null || true)" != "$public_key" ]]; then
    write_wg_key_files "$private_file" "$public_file" "$selected" "$public_key"
  fi

  WG_IDENTITY_PRIVATE="$selected"
  WG_IDENTITY_PUBLIC="$public_key"
}

get_or_generate_private_key() {
  local iface="$1"
  ensure_wg_identity "$iface" || return 1
  printf '%s' "$WG_IDENTITY_PRIVATE"
}

show_wg_identity_for_iface() {
  local iface="$1"
  local card_mode="${2:-card}"
  local conf private_file public_file address role public_key started="no" exists="no"
  conf="$(wg_conf_for_iface "$iface")" || return 1
  private_file="$(wg_private_file_for_iface "$iface")" || return 1
  public_file="$(wg_public_file_for_iface "$iface")" || return 1
  address="$(wg_address_for_iface "$iface")" || return 1
  role="$(wg_role_for_iface "$iface")"
  ensure_wg_identity "$iface" || return 1
  public_key="$WG_IDENTITY_PUBLIC"
  [[ -f "$conf" ]] && exists="yes"
  ip addr show "$iface" >/dev/null 2>&1 && started="yes"

  cat <<EOF
ROLE_HINT=${role}
WG_INTERFACE=${iface}
WG_ADDRESS=${address}
WG_PUBLIC_KEY=${public_key}
$(if [[ "$iface" == "wg0" ]]; then printf 'LEIKWAN_PUBLIC_KEY=%s\n' "$public_key"; elif [[ "$iface" == "wg1" ]]; then printf 'CLOUD_PUBLIC_KEY=%s\n' "$public_key"; fi)
PRIVATE_KEY_FILE=${private_file}
PUBLIC_KEY_FILE=${public_file}
CONFIG_FILE=${conf}
CONFIG_EXISTS=${exists}
INTERFACE_STARTED=${started}
EOF

  if [[ "$card_mode" == "card" ]]; then
    if [[ "$iface" == "wg0" ]]; then
      print_copy_block "复制到公网入口机" "LEIKWAN_PUBLIC_KEY=${public_key}" $'去公网入口机运行：\nbash wg-toolkit.sh\n选择：极速部署向导\n并粘贴上面的 LEIKWAN_PUBLIC_KEY'
    elif [[ "$iface" == "wg1" ]]; then
      print_copy_block "复制回利群中转机" "CLOUD_PUBLIC_KEY=${public_key}" $'去利群中转机运行：\nbash wg-toolkit.sh\n选择：极速部署向导\n并导入 CLOUD 参数'
    fi
  fi
}

show_wg_identity_cli() {
  local role_filter="${1:-auto}"
  local shown=0
  case "$role_filter" in
    leikwan|leikwan-relay)
      show_wg_identity_for_iface "wg0" "plain"
      return
      ;;
    cloud|cloud-entry)
      show_wg_identity_for_iface "wg1" "plain"
      return
      ;;
    auto|"")
      ;;
    *)
      fail "未知 --role：${role_filter}，可用值：leikwan / cloud"
      return 1
      ;;
  esac

  if ip addr show wg0 >/dev/null 2>&1 || [[ -f "$LEIKWAN_WG_CONF" ]]; then
    show_wg_identity_for_iface "wg0" "plain"
    shown=1
  fi
  if ip addr show wg1 >/dev/null 2>&1 || [[ -f "$CLOUD_WG_CONF" ]]; then
    (( shown == 1 )) && echo
    show_wg_identity_for_iface "wg1" "plain"
    shown=1
  fi
  if (( shown == 0 )); then
    cat <<EOF
未检测到 wg0/wg1 或 WireGuard 配置。
可用参数：
  bash wg-toolkit.sh --show-wg-identity --role leikwan
  bash wg-toolkit.sh --show-wg-identity --role cloud
EOF
  fi
}

reset_wg_identity() {
  need_root
  init_log
  local iface="$1"
  local private_file public_file conf summary private_key public_key
  private_file="$(wg_private_file_for_iface "$iface")" || return 1
  public_file="$(wg_public_file_for_iface "$iface")" || return 1
  conf="$(wg_conf_for_iface "$iface")" || return 1
  summary="接口：${iface}\nPrivateKey 文件：${private_file}\nPublicKey 文件：${public_file}\n配置文件：${conf}\n警告：重置 WireGuard Key 会导致对端 Peer 失效，必须把新的 PublicKey 复制到对端重新配置。"
  if ! confirm_summary "重置本机 WireGuard Key 摘要" "$summary"; then
    return 0
  fi
  if ! prompt_yes_no "二次确认：确定重置 ${iface} Key，并接受对端 Peer 失效风险？" "N"; then
    warn "已取消重置。"
    return 0
  fi
  private_key="$(wg genkey)"
  public_key="$(public_from_private "$private_key")"
  write_wg_key_files "$private_file" "$public_file" "$private_key" "$public_key"
  warn "已重置 ${iface} Key。请立刻更新对端 Peer。"
  show_wg_identity_for_iface "$iface"
}

show_wg_identity_menu() {
  need_root_unless_dry_run
  init_log
  while true; do
    echo
    echo "${BOLD}查看 / 生成本机 WireGuard 身份${RESET}"
    echo "1. 利群中转机 wg0（输出 LEIKWAN_PUBLIC_KEY）"
    echo "2. 公网入口机 wg1（输出 CLOUD_PUBLIC_KEY）"
    echo "3. 重置本机 WireGuard Key"
    echo "0. 返回"
    local choice reset_choice
    read -r -p "请选择：" choice
    case "$choice" in
      1) show_wg_identity_for_iface "wg0" || true ;;
      2) show_wg_identity_for_iface "wg1" || true ;;
      3)
        echo "1. 重置 wg0（利群中转机）"
        echo "2. 重置 wg1（公网入口机）"
        echo "0. 取消"
        read -r -p "请选择：" reset_choice
        case "$reset_choice" in
          1) reset_wg_identity "wg0" || true ;;
          2) reset_wg_identity "wg1" || true ;;
          0) ;;
          *) echo "无效选择。" ;;
        esac
        ;;
      0) return 0 ;;
      *) echo "无效选择。" ;;
    esac
  done
}

enable_wg_quick() {
  local iface="$1"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 跳过启动 wg-quick@${iface}.service"
    return 0
  fi
  info "启动并启用 wg-quick@${iface}"
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable "wg-quick@${iface}.service"
  if run_cmd systemctl restart "wg-quick@${iface}.service"; then
    ok "wg-quick@${iface} 已启动。"
  else
    fail "wg-quick@${iface} 启动失败，请查看：journalctl -u wg-quick@${iface} -e --no-pager"
    return 1
  fi
}

detect_public_ipv4() {
  local ip=""
  ip="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "$ip"
}

download_github_asset() {
  local url="$1"
  local dest="$2"
  local local_path=""
  local candidates=(
    "$url"
    "https://ghfast.top/${url}"
    "https://ghproxy.net/${url}"
  )
  local candidate

  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将尝试下载：直连 -> ghfast -> ghproxy -> 本地文件路径"
    return 0
  fi

  if [[ "$url" == file://* ]]; then
    local_path="${url#file://}"
    if [[ -f "$local_path" ]]; then
      cp -a "$local_path" "$dest"
      ok "已使用本地文件：${local_path}"
      return 0
    fi
    fail "本地文件不存在：${local_path}"
    return 1
  fi

  for candidate in "${candidates[@]}"; do
    info "尝试下载：${candidate}"
    if curl -fL --retry 2 --connect-timeout 15 "$candidate" -o "$dest"; then
      ok "下载成功：${candidate}"
      return 0
    fi
    warn "下载失败：${candidate}"
  done

  warn "直连、ghfast、ghproxy 均失败。"
  local_path="$(prompt_value "请输入本地安装包路径，留空取消")"
  if [[ -n "$local_path" && -f "$local_path" ]]; then
    cp -a "$local_path" "$dest"
    ok "已使用本地文件：${local_path}"
    return 0
  fi

  fail "未提供可用本地文件，下载失败。"
  return 1
}

render_cloud_wg_config() {
  local private_key="$1"
  local listen_port="$2"
  local leikwan_public_key="$3"
  cat <<EOF
# Managed by leikwan-wg-toolkit
# Role: cloud-entry 公网入口机
[Interface]
PrivateKey = ${private_key}
Address = ${CLOUD_WG_ADDR}
ListenPort = ${listen_port}
MTU = ${WG_MTU_DEFAULT}
SaveConfig = false

[Peer]
# 利群中转机
PublicKey = ${leikwan_public_key}
AllowedIPs = ${LEIKWAN_WG_IP}/32
EOF
}

render_leikwan_wg_config() {
  local private_key="$1"
  local cloud_public_key="$2"
  local cloud_endpoint="$3"
  local cloud_port="$4"
  cat <<EOF
# Managed by leikwan-wg-toolkit
# Role: leikwan-relay 利群中转机
[Interface]
PrivateKey = ${private_key}
Address = ${LEIKWAN_WG_ADDR}
MTU = ${WG_MTU_DEFAULT}
SaveConfig = false

[Peer]
# 公网入口机
PublicKey = ${cloud_public_key}
Endpoint = ${cloud_endpoint}:${cloud_port}
AllowedIPs = ${CLOUD_WG_IP}/32
PersistentKeepalive = ${WG_KEEPALIVE_DEFAULT}
EOF
}

realm_is_forwarder() {
  command -v realm >/dev/null 2>&1 || return 1
  realm --help 2>&1 | grep -Eiq 'listen|remote|endpoint|proxy|config' || return 1
}

install_realm() {
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将检查/安装 realm，实际运行时按直连、ghfast、ghproxy、本地文件路径 fallback。"
    return 0
  fi

  if realm_is_forwarder; then
    ok "已检测到 realm：$(command -v realm)"
    return 0
  fi

  warn "未检测到可用的 realm 转发程序。"
  if ! prompt_yes_no "是否从 zhboner/realm GitHub Release 安装 realm？" "Y"; then
    return 1
  fi

  install_packages curl jq ca-certificates tar

  local arch asset_re api url tmpdir archive binary summary find_list
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) asset_re='x86_64.*linux.*gnu.*tar.*gz$' ;;
    aarch64|arm64) asset_re='aarch64.*linux.*gnu.*tar.*gz$' ;;
    armv7l|armv7*) asset_re='armv7.*linux.*gnueabihf.*tar.*gz$' ;;
    *)
      fail "暂不支持自动安装此架构：${arch}"
      return 1
      ;;
  esac

  api="https://api.github.com/repos/zhboner/realm/releases/latest"
  url="$(curl -fsSL "$api" | jq -r --arg re "$asset_re" '.assets[] | select(.name | test($re)) | .browser_download_url' | head -n 1)"
  if [[ -z "$url" || "$url" == "null" ]]; then
    warn "无法从 GitHub Release 匹配 realm 安装包。"
    local local_asset
    local_asset="$(prompt_value "请输入本地 realm tar.gz 安装包路径，留空取消")"
    if [[ -z "$local_asset" || ! -f "$local_asset" ]]; then
      fail "未提供可用本地文件。可手动安装 /usr/local/bin/realm 后重试。"
      return 1
    fi
    url="file://${local_asset}"
  fi

  summary="来源：${url}\n目标：/usr/local/bin/realm\n动作：下载并安装 realm 转发程序。"
  if ! confirm_summary "realm 安装摘要" "$summary"; then
    warn "已取消 realm 安装。"
    return 1
  fi

  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/realm.tar.gz"
  download_github_asset "$url" "$archive"
  tar -xzf "$archive" -C "$tmpdir"
  binary="$(find "$tmpdir" -type f -name realm | head -n 1)"
  if [[ -z "$binary" ]]; then
    binary="$(find "$tmpdir" -type f -name realm-slim | head -n 1)"
  fi
  if [[ -z "$binary" ]]; then
    binary="$(find "$tmpdir" -type f -name 'realm*' | head -n 1)"
  fi
  if [[ -z "$binary" ]]; then
    fail "下载包中未找到 realm / realm-slim / realm* 可执行文件。"
    find_list="$(find "$tmpdir" -maxdepth 4 -type f -printf '%m %p\n' 2>/dev/null || find "$tmpdir" -maxdepth 4 -type f)"
    printf '%s\n' "$find_list" >&2
    rm -rf "$tmpdir"
    return 1
  fi
  install -d -m 755 /usr/local/bin
  backup_file /usr/local/bin/realm
  install -m 755 "$binary" /usr/local/bin/realm
  rm -rf "$tmpdir"
  if /usr/local/bin/realm -v >/dev/null 2>&1; then
    /usr/local/bin/realm -v | head -n 1 || true
  elif /usr/local/bin/realm --version >/dev/null 2>&1; then
    /usr/local/bin/realm --version | head -n 1 || true
  else
    fail "realm 已安装但版本验证失败：/usr/local/bin/realm -v / --version"
    return 1
  fi
  ok "realm 已安装到 /usr/local/bin/realm"
}

realm_network_flags() {
  local proto="$1"
  case "$proto" in
    tcp) printf 'no_tcp = false\nuse_udp = false\n' ;;
    udp) printf 'no_tcp = true\nuse_udp = true\n' ;;
    both) printf 'no_tcp = false\nuse_udp = true\n' ;;
  esac
}

render_realm_entry_config() {
  local proto="$1"
  cat <<EOF
# Managed by leikwan-wg-toolkit
[log]
level = "info"
output = "/var/log/${REALM_ENTRY_STEM}.log"

[network]
$(realm_network_flags "$proto")
[[endpoints]]
listen = "0.0.0.0:${CLIENT_ENTRY_PORT_DEFAULT}"
remote = "${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT}"
EOF
}

render_realm_service() {
  local stem="$1"
  local conf="$2"
  local realm_bin="$3"
  cat <<EOF
# Managed by leikwan-wg-toolkit
[Unit]
Description=Leikwan chain realm forward ${stem}
Wants=network-online.target
After=network-online.target wg-quick@wg1.service

[Service]
Type=simple
ExecStart=${realm_bin} -c ${conf}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

configure_realm_entry_forward() {
  local proto="$1"
  local realm_bin config_content service_content summary
  realm_bin="$(command -v realm)"
  if [[ -z "$realm_bin" && $DRY_RUN -eq 1 ]]; then
    realm_bin="/usr/local/bin/realm"
  fi
  config_content="$(render_realm_entry_config "$proto")"
  service_content="$(render_realm_service "$REALM_ENTRY_STEM" "$REALM_ENTRY_CONF" "$realm_bin")"

  summary="服务：${REALM_ENTRY_STEM}.service\n规则：0.0.0.0:${CLIENT_ENTRY_PORT_DEFAULT} -> ${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT}\n协议：${proto}\n配置：${REALM_ENTRY_CONF}\n动作：创建/更新 realm systemd 服务并启动。"
  if ! confirm_summary "公网入口机 realm 转发摘要" "$summary"; then
    warn "已取消 realm 转发配置。"
    return 0
  fi

  if (( DRY_RUN == 0 )); then
    install -d -m 755 "$REALM_DIR"
  fi
  write_text_file "$REALM_ENTRY_CONF" "$config_content" 644 || true
  write_text_file "$REALM_ENTRY_SERVICE" "$service_content" 644 || true
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 跳过启动 ${REALM_ENTRY_STEM}.service"
    return 0
  fi
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable "${REALM_ENTRY_STEM}.service"
  if run_cmd systemctl restart "${REALM_ENTRY_STEM}.service"; then
    ok "realm 转发服务已启动：${REALM_ENTRY_STEM}.service"
  else
    fail "realm 服务启动失败，请查看：journalctl -u ${REALM_ENTRY_STEM}.service -e --no-pager"
    return 1
  fi
}

deploy_cloud_entry() {
  need_root_unless_dry_run
  init_log
  if (( DRY_RUN == 0 )); then
    install_wireguard_deps
    ensure_wireguard_dir
  fi

  echo
  warn "公网入口机部署需要利群中转机的 PublicKey。若还没有，请先在利群中转机执行菜单 2，复制 LEIKWAN_PUBLIC_KEY。"

  local leikwan_public_key wg_port private_key public_key wg_content endpoint summary proto
  local saved_leikwan_public_key
  saved_leikwan_public_key="$(saved_param LEIKWAN_PUBLIC_KEY "$LEIKWAN_PEER_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -n "$saved_leikwan_public_key" ]] && ok "已读取 LEIKWAN_PUBLIC_KEY。"
  leikwan_public_key="$(prompt_wg_key_default "请输入利群中转机 PublicKey" "$saved_leikwan_public_key")"
  wg_port="$(prompt_port "请输入公网入口机 WireGuard UDP 监听端口" "$CLOUD_WG_PORT_DEFAULT")"
  ensure_wg_identity "wg1" || return 1
  private_key="$WG_IDENTITY_PRIVATE"
  public_key="$WG_IDENTITY_PUBLIC"
  endpoint="$(detect_public_ipv4)"
  wg_content="$(render_cloud_wg_config "$private_key" "$wg_port" "$leikwan_public_key")"

  summary="角色：公网入口机\n文件：${CLOUD_WG_CONF}\n接口：wg1\n地址：${CLOUD_WG_ADDR}\n监听：${wg_port}/udp\nPeer 利群：${leikwan_public_key}\nAllowedIPs：${LEIKWAN_WG_IP}/32\n动作：写入 WireGuard 配置并启用 wg-quick@wg1。"
  if confirm_summary "公网入口机 WireGuard 部署摘要" "$summary"; then
    write_text_file "$CLOUD_WG_CONF" "$wg_content" 600 || true
    if (( DRY_RUN == 0 )); then
      chmod 600 "$CLOUD_WG_CONF"
    fi
    enable_wg_quick "wg1"
  else
    warn "已取消公网入口机 WireGuard 部署。"
    return 0
  fi

  install_realm || return 1
  while true; do
    proto="$(prompt_value "请选择公网入口 30000 转发协议：tcp / udp / both" "tcp")"
    case "$proto" in
      tcp|udp|both) break ;;
      *) echo "协议只能是 tcp、udp 或 both。" ;;
    esac
  done
  configure_realm_entry_forward "$proto"

  local cloud_output
  cloud_output="$(cat <<EOF
CLOUD_PUBLIC_KEY=${public_key}
CLOUD_ENDPOINT=${endpoint:-请填写公网入口机 IPv4 或域名}
CLOUD_WG_PORT=${wg_port}
CLIENT_ENTRY_PORT=${CLIENT_ENTRY_PORT_DEFAULT}
EOF
)"
  print_copy_block "请复制回利群中转机" "$cloud_output" $'去利群中转机运行：\nbash wg-toolkit.sh\n选择：推荐部署向导 -> 利群中转机：导入 CLOUD + LANDING 参数并完成链式部署'
  write_output_file "cloud-entry" "$cloud_output"
  print_cloud_acceptance_commands
}

render_xray_service() {
  local description="$1"
  local service_content
  service_content="$(cat <<EOF
# Managed by leikwan-wg-toolkit
[Unit]
Description=${description}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
)"
  printf '%s' "$service_content"
}

select_xray_service_target() {
  ACTIVE_XRAY_SERVICE_NAME="${XRAY_LEIKWAN_SERVICE_NAME}"
  ACTIVE_XRAY_SERVICE="${XRAY_LEIKWAN_SERVICE}"

  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将使用独立服务：${XRAY_LEIKWAN_SERVICE_NAME}.service，配置：${XRAY_CONFIG}"
    return 0
  fi

  if [[ -f "$XRAY_SYSTEM_SERVICE" ]] || systemctl list-unit-files --type=service --no-legend xray.service 2>/dev/null | grep -q '^xray\.service'; then
    warn "检测到已有 xray.service。为避免污染用户已有服务，推荐创建独立 ${XRAY_LEIKWAN_SERVICE_NAME}.service。"
    echo "1. 备份并覆盖 xray.service"
    echo "2. 创建独立 xray-leikwan.service（推荐）"
    echo "3. 取消"
    local choice
    read -r -p "请选择 [2]: " choice
    choice="${choice:-2}"
    case "$choice" in
      1)
        ACTIVE_XRAY_SERVICE_NAME="${XRAY_SYSTEM_SERVICE_NAME}"
        ACTIVE_XRAY_SERVICE="${XRAY_SYSTEM_SERVICE}"
        ;;
      2)
        ACTIVE_XRAY_SERVICE_NAME="${XRAY_LEIKWAN_SERVICE_NAME}"
        ACTIVE_XRAY_SERVICE="${XRAY_LEIKWAN_SERVICE}"
        ;;
      3)
        fail "已取消 Xray 服务配置。"
        return 1
        ;;
      *)
        fail "选择无效。"
        return 1
        ;;
    esac
  fi
}

install_xray_service_if_needed() {
  select_xray_service_target

  local service_content description
  description="Leikwan Xray Chain Service"
  service_content="$(render_xray_service "$description")"

  if [[ "$ACTIVE_XRAY_SERVICE" == "$XRAY_SYSTEM_SERVICE" ]]; then
    backup_file "$XRAY_SYSTEM_SERVICE"
  fi

  write_text_file "$ACTIVE_XRAY_SERVICE" "$service_content" 644 || true
  run_cmd systemctl daemon-reload
}

install_xray() {
  if (( DRY_RUN == 1 )); then
    if command -v xray >/dev/null 2>&1; then
      XRAY_BIN="$(command -v xray)"
      ok "DRY-RUN：检测到 Xray：${XRAY_BIN}"
    else
      warn "DRY-RUN：未检测到 xray，将使用占位密钥/UUID 生成配置预览。"
    fi
    install_xray_service_if_needed
    return 0
  fi

  if command -v xray >/dev/null 2>&1; then
    XRAY_BIN="$(command -v xray)"
    ok "已检测到 Xray：${XRAY_BIN}"
    install_xray_service_if_needed
    return 0
  fi

  install_xray_deps

  local arch asset_re api url tmpdir archive summary binary
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) asset_re='Xray-linux-64\.zip$' ;;
    aarch64|arm64) asset_re='Xray-linux-arm64-v8a\.zip$' ;;
    armv7l|armv7*) asset_re='Xray-linux-arm32-v7a\.zip$' ;;
    *)
      fail "暂不支持自动安装此架构：${arch}"
      return 1
      ;;
  esac

  api="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
  url="$(curl -fsSL "$api" | jq -r --arg re "$asset_re" '.assets[] | select(.name | test($re)) | .browser_download_url' | head -n 1)"
  if [[ -z "$url" || "$url" == "null" ]]; then
    warn "无法从 Xray-core Release 匹配安装包。"
    local local_asset
    local_asset="$(prompt_value "请输入本地 Xray zip 安装包路径，留空取消")"
    if [[ -z "$local_asset" || ! -f "$local_asset" ]]; then
      fail "未提供可用本地文件。可手动安装 xray 后重试。"
      return 1
    fi
    url="file://${local_asset}"
  fi

  summary="来源：${url}\n目标：${XRAY_BIN}\n动作：下载并安装 Xray-core，并创建/更新带 leikwan 标识的 systemd 服务。\nFallback：直连、ghfast、ghproxy、本地文件路径。"
  if ! confirm_summary "Xray 安装摘要" "$summary"; then
    warn "已取消 Xray 安装。"
    return 1
  fi

  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/xray.zip"
  download_github_asset "$url" "$archive"
  unzip -q "$archive" -d "$tmpdir"
  binary="${tmpdir}/xray"
  if [[ ! -f "$binary" ]]; then
    fail "下载包中未找到 xray 可执行文件。"
    rm -rf "$tmpdir"
    return 1
  fi

  install -d -m 755 /usr/local/bin
  backup_file "$XRAY_BIN"
  install -m 755 "$binary" "$XRAY_BIN"

  if [[ -f "${tmpdir}/geoip.dat" || -f "${tmpdir}/geosite.dat" ]]; then
    install -d -m 755 /usr/local/share/xray
    [[ -f "${tmpdir}/geoip.dat" ]] && install -m 644 "${tmpdir}/geoip.dat" /usr/local/share/xray/geoip.dat
    [[ -f "${tmpdir}/geosite.dat" ]] && install -m 644 "${tmpdir}/geosite.dat" /usr/local/share/xray/geosite.dat
  fi

  rm -rf "$tmpdir"
  install_xray_service_if_needed
  ok "Xray 已安装。"
}

xray_uuid() {
  if (( DRY_RUN == 1 )) && [[ ! -x "$XRAY_BIN" ]] && ! command -v xray >/dev/null 2>&1; then
    printf '%s\n' "00000000-0000-4000-8000-000000000000"
    return 0
  fi
  if "$XRAY_BIN" uuid >/dev/null 2>&1; then
    "$XRAY_BIN" uuid
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

xray_x25519_pair() {
  local output private_key public_key
  if (( DRY_RUN == 1 )) && [[ ! -x "$XRAY_BIN" ]] && ! command -v xray >/dev/null 2>&1; then
    printf '%s\n%s\n' "DRYRUN_REALITY_PRIVATE_KEY" "DRYRUN_REALITY_PUBLIC_KEY"
    return 0
  fi
  output="$("$XRAY_BIN" x25519 2>&1)"
  private_key="$(printf '%s\n' "$output" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}')"
  public_key="$(printf '%s\n' "$output" | awk -F': *' 'tolower($1) ~ /public/ {print $2; exit}')"
  if [[ -z "$private_key" || -z "$public_key" ]]; then
    fail "无法解析 xray x25519 输出："
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n%s\n' "$private_key" "$public_key"
}

random_hex() {
  local bytes="$1"
  openssl rand -hex "$bytes"
}

render_landing_xray_config() {
  local port="$1"
  local uuid="$2"
  local private_key="$3"
  local short_id="$4"
  local server_name="$5"
  local target="$6"

  cat <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray-leikwan-access.log",
    "error": "/var/log/xray-leikwan-error.log"
  },
  "inbounds": [
    {
      "tag": "leikwan-landing-reality-in",
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${target}",
          "serverNames": [ "${server_name}" ],
          "privateKey": "${private_key}",
          "shortIds": [ "${short_id}" ]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "protocol": [ "bittorrent" ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
}

json_escape() {
  local value="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$value" | jq -Rsa .
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<<"$value"
  else
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '"%s"' "$value"
  fi
}

xray_test_config() {
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 跳过 Xray 配置测试：${XRAY_CONFIG}"
    return 0
  fi
  "$XRAY_BIN" run -test -config "$XRAY_CONFIG"
}

show_xray_config_context() {
  local file="${1:-$XRAY_CONFIG}"
  [[ -f "$file" ]] || return 0
  echo
  echo "${BOLD}Xray 配置排错片段：${file}${RESET}"
  if grep -nE 'decryption|encryption|realitySettings|vnext|inbounds|outbounds' "$file" >/dev/null 2>&1; then
    grep -nE -C 3 'decryption|encryption|realitySettings|vnext|inbounds|outbounds' "$file" | head -n 160
  else
    nl -ba "$file" | sed -n '1,160p'
  fi
}

restart_xray() {
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 跳过启动 ${ACTIVE_XRAY_SERVICE_NAME}.service"
    return 0
  fi
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable "${ACTIVE_XRAY_SERVICE_NAME}.service"
  if run_cmd systemctl restart "${ACTIVE_XRAY_SERVICE_NAME}.service"; then
    ok "${ACTIVE_XRAY_SERVICE_NAME}.service 已启动。"
  else
    fail "${ACTIVE_XRAY_SERVICE_NAME}.service 启动失败，请查看：journalctl -u ${ACTIVE_XRAY_SERVICE_NAME} -e --no-pager"
    return 1
  fi
}

print_cloud_acceptance_commands() {
  cat <<EOF

${BOLD}公网入口机验收命令：${RESET}
wg show
ping -c 3 ${LEIKWAN_WG_IP}
nc -vz ${LEIKWAN_WG_IP} ${CLIENT_ENTRY_PORT_DEFAULT}
ss -lntup | grep ${CLIENT_ENTRY_PORT_DEFAULT}
systemctl status ${REALM_ENTRY_STEM} --no-pager
EOF
}

print_landing_acceptance_commands() {
  local landing_port="$1"
  cat <<EOF

${BOLD}海外落地机验收命令：${RESET}
systemctl status ${ACTIVE_XRAY_SERVICE_NAME} --no-pager
ss -lntup | grep ${landing_port}
${XRAY_BIN} run -test -config ${XRAY_CONFIG}
EOF
}

print_relay_acceptance_commands() {
  local landing_address="$1"
  local landing_port="$2"
  cat <<EOF

${BOLD}利群中转机验收命令：${RESET}
wg show
ss -lntup | grep ${CLIENT_ENTRY_PORT_DEFAULT}
ip route get ${landing_address}
nc -vz ${landing_address} ${landing_port}
systemctl status ${ACTIVE_XRAY_SERVICE_NAME} --no-pager
EOF
}

deploy_landing_server() {
  need_root_unless_dry_run
  init_log
  install_xray

  local landing_port landing_address uuid pair private_key public_key short_id server_name target config summary
  landing_port="$(prompt_port "请输入海外落地机 Reality 入站端口" "$LANDING_PORT_DEFAULT")"
  landing_address="$(prompt_endpoint_host "请输入海外落地机公网地址，用于输出给利群中转机" "$(detect_public_ipv4)")"
  server_name="$(prompt_non_empty "请输入 Reality serverName" "$LANDING_SERVER_NAME_DEFAULT")"
  target="$(prompt_non_empty "请输入 Reality target" "$LANDING_TARGET_DEFAULT")"
  uuid="$(xray_uuid)"
  pair="$(xray_x25519_pair)"
  private_key="$(printf '%s\n' "$pair" | sed -n '1p')"
  public_key="$(printf '%s\n' "$pair" | sed -n '2p')"
  short_id="$(random_hex 8)"
  config="$(render_landing_xray_config "$landing_port" "$uuid" "$private_key" "$short_id" "$server_name" "$target")"

  summary="角色：海外落地机\n文件：${XRAY_CONFIG}\nReality inbound：0.0.0.0:${landing_port}\nprotocol：vless\nnetwork：raw\nsecurity：reality\ntarget：${target}\nserverNames：[${server_name}]\nflow：${LANDING_FLOW_DEFAULT}\n动作：写入 Xray Reality 配置，执行 xray run -test，通过后启动 ${ACTIVE_XRAY_SERVICE_NAME}.service。\n注意：Reality PrivateKey 只写入落地机配置，不会作为复制参数输出。"
  if ! confirm_summary "海外落地机部署摘要" "$summary"; then
    warn "已取消海外落地机部署。"
    return 0
  fi

  if (( DRY_RUN == 0 )); then
    install -d -m 755 "$(dirname "$XRAY_CONFIG")"
    install -d -m 755 "$XRAY_MARKER_DIR"
  fi
  write_text_file "$XRAY_CONFIG" "$config" 644 || true
  if (( DRY_RUN == 0 )); then
    printf 'landing\n' >"${XRAY_MARKER_DIR}/role"
  fi

  if xray_test_config; then
    ok "Xray 配置测试通过。"
    restart_xray
  else
    fail "Xray 配置测试失败，未启动服务。请检查 ${XRAY_CONFIG}。"
    show_xray_config_context "$XRAY_CONFIG"
    return 1
  fi

  local landing_output
  landing_output="$(cat <<EOF
LANDING_ADDRESS=${landing_address}
LANDING_PORT=${landing_port}
LANDING_UUID=${uuid}
LANDING_PUBLIC_KEY=${public_key}
LANDING_SHORT_ID=${short_id}
LANDING_SERVER_NAME=${server_name}
LANDING_FLOW=${LANDING_FLOW_DEFAULT}
EOF
)"
  print_copy_block "请复制到利群中转机" "$landing_output" $'下一步去利群中转机：\nbash wg-toolkit.sh\n选择：查看 / 生成本机 WireGuard 身份\n拿到 LEIKWAN_PUBLIC_KEY 后去公网入口机部署'
  write_output_file "landing-server" "$landing_output"
  print_landing_acceptance_commands "$landing_port"
}

parse_vlessenc_value() {
  local output="$1"
  local key="$2"
  printf '%s\n' "$output" \
    | awk -v key="$key" '
        {
          line=$0
          lower=tolower(line)
          if (lower ~ "\"" key "\"" || lower ~ key "[[:space:]]*:") {
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
          }
        }' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/,$//; s/^"//; s/"$//'
}

clean_vlessenc_value() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/,$//; s/^"//; s/"$//'
}

get_vlessenc_pair() {
  local output decryption encryption
  if (( DRY_RUN == 0 )); then
    install -d -m 755 "$XRAY_MARKER_DIR"
  fi

  if (( DRY_RUN == 1 )) && [[ ! -x "$XRAY_BIN" ]] && ! command -v xray >/dev/null 2>&1; then
    output=$'DRY-RUN VLESS Encryption preview\nDecryption: DRYRUN_VLESSENC_DECRYPTION\nEncryption: DRYRUN_VLESSENC_ENCRYPTION'
  else
    output="$("$XRAY_BIN" vlessenc 2>&1 || true)"
  fi

  if (( DRY_RUN == 0 )); then
    printf '%s\n' "$output" >"$XRAY_VLESSENC_LAST"
  fi

  echo
  echo "${BOLD}xray vlessenc 输出如下，请优先选择 X25519 那组参数：${RESET}"
  printf '%s\n' "$output"
  echo

  decryption="$(parse_vlessenc_value "$output" "decryption")"
  encryption="$(parse_vlessenc_value "$output" "encryption")"

  if [[ -n "$decryption" && -n "$encryption" ]]; then
    echo "自动解析到："
    echo "VLESSENC_DECRYPTION=${decryption}"
    echo "VLESSENC_ENCRYPTION=${encryption}"
    if prompt_yes_no "是否使用这组 VLESS Encryption 参数？" "Y"; then
      VLESSENC_DECRYPTION_RESULT="$decryption"
      VLESSENC_ENCRYPTION_RESULT="$encryption"
      return 0
    fi
  fi

  warn "请从上方输出中选择 X25519 组，分别复制服务端 decryption 与客户端 encryption。"
  decryption="$(clean_vlessenc_value "$(prompt_non_empty "请输入 VLESSENC_DECRYPTION")")"
  encryption="$(clean_vlessenc_value "$(prompt_non_empty "请输入 VLESSENC_ENCRYPTION")")"
  VLESSENC_DECRYPTION_RESULT="$decryption"
  VLESSENC_ENCRYPTION_RESULT="$encryption"
}

render_leikwan_xray_config() {
  local entry_uuid="$1"
  local vlessenc_decryption="$2"
  local landing_address="$3"
  local landing_port="$4"
  local landing_uuid="$5"
  local landing_public_key="$6"
  local landing_short_id="$7"
  local landing_server_name="$8"
  local entry_uuid_json vlessenc_decryption_json landing_address_json landing_uuid_json landing_public_key_json landing_short_id_json landing_server_name_json
  entry_uuid_json="$(json_escape "$entry_uuid")"
  vlessenc_decryption_json="$(json_escape "$vlessenc_decryption")"
  landing_address_json="$(json_escape "$landing_address")"
  landing_uuid_json="$(json_escape "$landing_uuid")"
  landing_public_key_json="$(json_escape "$landing_public_key")"
  landing_short_id_json="$(json_escape "$landing_short_id")"
  landing_server_name_json="$(json_escape "$landing_server_name")"

  cat <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray-leikwan-access.log",
    "error": "/var/log/xray-leikwan-error.log"
  },
  "inbounds": [
    {
      "tag": "leikwan-entry-vless-in",
      "listen": "10.198.1.1",
      "port": 30000,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": ${entry_uuid_json} }
        ],
        "decryption": ${vlessenc_decryption_json}
      },
      "streamSettings": {
        "network": "raw",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "landing-reality-out",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": ${landing_address_json},
            "port": ${landing_port},
            "users": [
              {
                "id": ${landing_uuid_json},
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "serverName": ${landing_server_name_json},
          "publicKey": ${landing_public_key_json},
          "shortId": ${landing_short_id_json},
          "fingerprint": "chrome",
          "spiderX": "/"
        }
      }
    },
    { "protocol": "blackhole", "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "protocol": [ "bittorrent" ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
}

urlencode() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -sRr @uri
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))' <<<"$1"
  else
    warn "未检测到 jq 或 python3，客户端链接中的 encryption 参数将不做 URL 编码。"
    printf '%s' "$1"
  fi
}

deploy_leikwan_relay() {
  need_root_unless_dry_run
  init_log
  if (( DRY_RUN == 0 )); then
    install_wireguard_deps
    ensure_wireguard_dir
  fi

  local cloud_public_key cloud_endpoint cloud_port wg_private wg_public wg_content wg_summary
  ensure_wg_identity "wg0" || return 1
  wg_private="$WG_IDENTITY_PRIVATE"
  wg_public="$WG_IDENTITY_PUBLIC"

  echo
  print_copy_block "请复制到公网入口机" "LEIKWAN_PUBLIC_KEY=${wg_public}" $'去公网入口机运行：\nbash wg-toolkit.sh\n选择：公网入口机部署\n并粘贴上面的 LEIKWAN_PUBLIC_KEY'
  if ! prompt_yes_no "是否继续配置公网入口机 Peer 和 Xray 中转？如果公网入口机还没部署，可先复制 PublicKey 后选择 n。" "Y"; then
    return 0
  fi

  local saved_cloud_public_key saved_cloud_endpoint saved_cloud_port saved_client_entry_port
  saved_cloud_public_key="$(saved_param CLOUD_PUBLIC_KEY "$CLOUD_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_cloud_endpoint="$(saved_param CLOUD_ENDPOINT "$CLOUD_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_cloud_port="$(saved_param CLOUD_WG_PORT "$CLOUD_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_client_entry_port="$(saved_param CLIENT_ENTRY_PORT "$CLOUD_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -n "$saved_cloud_public_key" ]] && ok "已从参数文件读取 CLOUD_PUBLIC_KEY。"
  [[ -n "$saved_cloud_endpoint" ]] && ok "已从参数文件读取 CLOUD_ENDPOINT=${saved_cloud_endpoint}。"

  cloud_public_key="$(prompt_wg_key_default "请输入公网入口机 CLOUD_PUBLIC_KEY" "$saved_cloud_public_key")"
  cloud_endpoint="$(prompt_endpoint_host "请输入公网入口机 CLOUD_ENDPOINT" "$saved_cloud_endpoint")"
  cloud_port="$(prompt_port "请输入公网入口机 CLOUD_WG_PORT" "${saved_cloud_port:-$CLOUD_WG_PORT_DEFAULT}")"
  CLIENT_ENTRY_PORT_DEFAULT="${saved_client_entry_port:-$CLIENT_ENTRY_PORT_DEFAULT}"
  wg_content="$(render_leikwan_wg_config "$wg_private" "$cloud_public_key" "$cloud_endpoint" "$cloud_port")"

  wg_summary="角色：利群中转机\n文件：${LEIKWAN_WG_CONF}\n接口：wg0\n地址：${LEIKWAN_WG_ADDR}\nPeer 公网入口机：${cloud_public_key}\nEndpoint：${cloud_endpoint}:${cloud_port}\nAllowedIPs：${CLOUD_WG_IP}/32\nPersistentKeepalive：${WG_KEEPALIVE_DEFAULT}\n动作：写入 WireGuard 配置并启用 wg-quick@wg0。"
  if confirm_summary "利群中转机 WireGuard 部署摘要" "$wg_summary"; then
    write_text_file "$LEIKWAN_WG_CONF" "$wg_content" 600 || true
    if (( DRY_RUN == 0 )); then
      chmod 600 "$LEIKWAN_WG_CONF"
    fi
    enable_wg_quick "wg0"
  else
    warn "已取消利群中转机 WireGuard 部署。"
    return 0
  fi

  install_xray

  local landing_address landing_port landing_uuid landing_public_key landing_short_id landing_server_name
  local entry_uuid vless_decryption vless_encryption xray_content xray_summary encoded_encryption client_link

  local saved_landing_address saved_landing_port saved_landing_uuid saved_landing_public_key saved_landing_short_id saved_landing_server_name
  saved_landing_address="$(saved_param LANDING_ADDRESS "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_landing_port="$(saved_param LANDING_PORT "$LANDING_OUTPUT_FILE" "$RELAY_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_landing_uuid="$(saved_param LANDING_UUID "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_landing_public_key="$(saved_param LANDING_PUBLIC_KEY "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_landing_short_id="$(saved_param LANDING_SHORT_ID "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  saved_landing_server_name="$(saved_param LANDING_SERVER_NAME "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  [[ -n "$saved_landing_address" ]] && ok "已从参数文件读取 LANDING_ADDRESS=${saved_landing_address}。"

  landing_address="$(prompt_endpoint_host "请输入海外落地机 LANDING_ADDRESS" "$saved_landing_address")"
  landing_port="$(prompt_port "请输入海外落地机 LANDING_PORT" "${saved_landing_port:-$LANDING_PORT_DEFAULT}")"
  landing_uuid="$(prompt_non_empty "请输入海外落地机 LANDING_UUID" "$saved_landing_uuid")"
  landing_public_key="$(prompt_non_empty "请输入海外落地机 LANDING_PUBLIC_KEY" "$saved_landing_public_key")"
  landing_short_id="$(prompt_non_empty "请输入海外落地机 LANDING_SHORT_ID" "$saved_landing_short_id")"
  landing_server_name="$(prompt_non_empty "请输入海外落地机 LANDING_SERVER_NAME" "${saved_landing_server_name:-$LANDING_SERVER_NAME_DEFAULT}")"

  entry_uuid="$(xray_uuid)"
  get_vlessenc_pair
  vless_decryption="$VLESSENC_DECRYPTION_RESULT"
  vless_encryption="$VLESSENC_ENCRYPTION_RESULT"
  xray_content="$(render_leikwan_xray_config "$entry_uuid" "$vless_decryption" "$landing_address" "$landing_port" "$landing_uuid" "$landing_public_key" "$landing_short_id" "$landing_server_name")"
  encoded_encryption="$(urlencode "$vless_encryption")"
  client_link="vless://${entry_uuid}@${cloud_endpoint}:${CLIENT_ENTRY_PORT_DEFAULT}?type=raw&security=none&encryption=${encoded_encryption}#Leikwan-WG-Xray-Reality"

  xray_summary="角色：利群中转机\n文件：${XRAY_CONFIG}\ninbound：${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT} vless/raw/security=none\nENTRY_UUID：${entry_uuid}\nVLESSENC_DECRYPTION：${vless_decryption}\noutbound：${landing_address}:${landing_port} vless/raw/reality\nReality serverName：${landing_server_name}\nReality publicKey：${landing_public_key}\nReality shortId：${landing_short_id}\nrouting：block bittorrent\n动作：写入 Xray 中转配置，执行 xray run -test，通过后启动 ${ACTIVE_XRAY_SERVICE_NAME}.service。"
  if ! confirm_summary "利群中转机 Xray 部署摘要" "$xray_summary"; then
    warn "已取消利群中转机 Xray 部署。"
    return 0
  fi

  if (( DRY_RUN == 0 )); then
    install -d -m 755 "$(dirname "$XRAY_CONFIG")"
    install -d -m 755 "$XRAY_MARKER_DIR"
  fi
  write_text_file "$XRAY_CONFIG" "$xray_content" 644 || true
  if (( DRY_RUN == 0 )); then
    printf 'leikwan-relay\n' >"${XRAY_MARKER_DIR}/role"
  fi

  if xray_test_config; then
    ok "Xray 配置测试通过。"
    restart_xray
  else
    fail "Xray 配置测试失败，未启动服务。请检查 ${XRAY_CONFIG}。"
    show_xray_config_context "$XRAY_CONFIG"
    return 1
  fi

  local relay_output client_link_output
  relay_output="$(cat <<EOF
ENTRY_UUID=${entry_uuid}
VLESSENC_ENCRYPTION=${vless_encryption}
CLOUD_ENDPOINT=${cloud_endpoint}
CLIENT_ENTRY_PORT=${CLIENT_ENTRY_PORT_DEFAULT}
LANDING_ADDRESS=${landing_address}
LANDING_PORT=${landing_port}
CLIENT_LINK=${client_link}
LEIKWAN_PUBLIC_KEY=${wg_public}
CLOUD_PUBLIC_KEY=${cloud_public_key}
WG_STATUS_HINT=请运行 wg show，确认与公网入口机存在 latest handshake，并能 ping ${CLOUD_WG_IP}
EOF
)"
  client_link_output="$(cat <<EOF
ENTRY_UUID=${entry_uuid}
VLESSENC_ENCRYPTION=${vless_encryption}
CLOUD_ENDPOINT=${cloud_endpoint}
CLIENT_ENTRY_PORT=${CLIENT_ENTRY_PORT_DEFAULT}
LANDING_ADDRESS=${landing_address}
LANDING_PORT=${landing_port}
CLIENT_LINK=${client_link}
EOF
)"
  print_copy_block "客户端导入链接" "CLIENT_LINK=${client_link}"
  write_output_file "leikwan-relay" "$relay_output"
  write_output_file "client-link" "$client_link_output"
  print_relay_acceptance_commands "$landing_address" "$landing_port"
}

ensure_nc() {
  if command -v nc >/dev/null 2>&1; then
    return 0
  fi
  warn "未检测到 nc。"
  if prompt_yes_no "是否安装 netcat-openbsd 用于链路测试？" "Y"; then
    install_packages netcat-openbsd
  else
    return 1
  fi
}

test_cloud_entry() {
  need_root
  init_log
  ensure_nc || true

  echo
  echo "${BOLD}公网入口机测试：wg show${RESET}"
  wg show || warn "wg show 执行失败。"

  echo
  echo "${BOLD}公网入口机测试：ping ${LEIKWAN_WG_IP}${RESET}"
  ping -c 3 -W 2 "$LEIKWAN_WG_IP" || warn "ping ${LEIKWAN_WG_IP} 失败。"

  echo
  echo "${BOLD}公网入口机测试：nc -vz ${LEIKWAN_WG_IP} ${CLIENT_ENTRY_PORT_DEFAULT}${RESET}"
  if command -v nc >/dev/null 2>&1; then
    nc -vz -w 3 "$LEIKWAN_WG_IP" "$CLIENT_ENTRY_PORT_DEFAULT" || warn "TCP ${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT} 连接失败。"
  fi

  echo
  echo "${BOLD}公网入口机测试：ss -lntup | grep ${CLIENT_ENTRY_PORT_DEFAULT}${RESET}"
  ss -lntup | grep "$CLIENT_ENTRY_PORT_DEFAULT" || warn "未看到 ${CLIENT_ENTRY_PORT_DEFAULT} 监听，请检查 realm。"
}

test_leikwan_relay() {
  need_root
  init_log
  ensure_nc || true

  local landing_address landing_port
  landing_address="$(prompt_endpoint_host "请输入 LANDING_ADDRESS")"
  landing_port="$(prompt_port "请输入 LANDING_PORT" "$LANDING_PORT_DEFAULT")"

  echo
  echo "${BOLD}利群中转机测试：wg show${RESET}"
  wg show || warn "wg show 执行失败。"

  echo
  echo "${BOLD}利群中转机测试：ss -lntup | grep ${CLIENT_ENTRY_PORT_DEFAULT}${RESET}"
  ss -lntup | grep "$CLIENT_ENTRY_PORT_DEFAULT" || warn "未看到 ${CLIENT_ENTRY_PORT_DEFAULT} 监听，请检查 Xray inbound。"

  echo
  echo "${BOLD}利群中转机测试：ip route get ${landing_address}${RESET}"
  ip route get "$landing_address" || warn "路由查询失败。"

  echo
  echo "${BOLD}利群中转机测试：nc -vz ${landing_address} ${landing_port}${RESET}"
  if command -v nc >/dev/null 2>&1; then
    nc -vz -w 3 "$landing_address" "$landing_port" || warn "落地机 ${landing_address}:${landing_port} TCP 连接失败。"
  fi

  echo
  echo "${BOLD}利群中转机测试：systemctl status ${XRAY_LEIKWAN_SERVICE_NAME}${RESET}"
  systemctl status "${XRAY_LEIKWAN_SERVICE_NAME}" --no-pager || systemctl status xray --no-pager || true
}

test_landing_server() {
  need_root
  init_log
  local landing_port
  landing_port="$(prompt_port "请输入 LANDING_PORT" "$LANDING_PORT_DEFAULT")"

  echo
  echo "${BOLD}海外落地机测试：systemctl status ${XRAY_LEIKWAN_SERVICE_NAME}${RESET}"
  systemctl status "${XRAY_LEIKWAN_SERVICE_NAME}" --no-pager || systemctl status xray --no-pager || true

  echo
  echo "${BOLD}海外落地机测试：ss -lntup | grep ${landing_port}${RESET}"
  ss -lntup | grep "$landing_port" || warn "未看到 ${landing_port} 监听，请检查 Xray Reality inbound。"

  echo
  echo "${BOLD}海外落地机测试：xray run -test${RESET}"
  if [[ -x "$XRAY_BIN" ]]; then
    xray_test_config || warn "Xray 配置测试失败。"
  else
    warn "未找到 ${XRAY_BIN}。"
  fi
}

link_test_menu() {
  while true; do
    echo
    echo "${BOLD}链路测试${RESET}"
    echo "1. 公网入口机测试"
    echo "2. 利群中转机测试"
    echo "3. 海外落地机测试"
    echo "0. 返回主菜单"
    read -r -p "请选择：" choice
    case "$choice" in
      1) test_cloud_entry || true ;;
      2) test_leikwan_relay || true ;;
      3) test_landing_server || true ;;
      0) return 0 ;;
      *) echo "无效选择。" ;;
    esac
  done
}

resolved_available() {
  systemctl list-unit-files --type=service --no-legend systemd-resolved.service 2>/dev/null \
    | grep -q '^systemd-resolved\.service' \
    || command -v resolvectl >/dev/null 2>&1
}

fix_dns_ipv4_first() {
  need_root
  init_log
  ensure_supported_os

  local gai_content resolved_content resolved_file summary need_gai_update="no" need_resolved_update="no"
  resolved_file="/etc/systemd/resolved.conf.d/99-custom-dns.conf"

  if [[ ! -f /etc/gai.conf ]] || ! grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' /etc/gai.conf; then
    need_gai_update="yes"
  fi

  resolved_content='[Resolve]
DNS=8.8.8.8 1.1.1.1 8.8.4.4
FallbackDNS=9.9.9.9 223.5.5.5
LLMNR=no
MulticastDNS=no'

  if resolved_available; then
    if [[ ! -f "$resolved_file" ]] || [[ "$(cat "$resolved_file" 2>/dev/null || true)" != "$resolved_content" ]]; then
      need_resolved_update="yes"
    fi
  fi

  summary="文件：/etc/gai.conf\n动作：确保添加 IPv4 优先规则 precedence ::ffff:0:0/96  100\n\n文件：${resolved_file}\n动作：如果 systemd-resolved 存在，写入 DNS=8.8.8.8 1.1.1.1 8.8.4.4，FallbackDNS=9.9.9.9 223.5.5.5，并关闭 LLMNR/MulticastDNS。\n\n测试：getent ahosts raw.githubusercontent.com\n提示：raw.githubusercontent.com 能通即可；github.com 主站可能仍因出口路由不可达。Release 下载推荐 ghfast 镜像。"

  if [[ "$need_gai_update" == "no" && "$need_resolved_update" == "no" ]]; then
    ok "DNS / IPv4 优先配置已是目标状态。"
  else
    if ! confirm_summary "DNS / IPv4 优先修复摘要" "$summary"; then
      warn "已取消 DNS / IPv4 优先修复。"
      return 0
    fi

    if [[ "$need_gai_update" == "yes" ]]; then
      gai_content="$(cat /etc/gai.conf 2>/dev/null || true)"
      gai_content="${gai_content%$'\n'}"$'\n\n# Added by leikwan-wg-toolkit: prefer IPv4-mapped addresses\nprecedence ::ffff:0:0/96  100'
      write_text_file /etc/gai.conf "$gai_content" 644 || true
    fi

    if resolved_available; then
      install -d -m 755 /etc/systemd/resolved.conf.d
      write_text_file "$resolved_file" "$resolved_content" 644 || true
      if systemctl is-enabled systemd-resolved.service >/dev/null 2>&1 || systemctl is-active systemd-resolved.service >/dev/null 2>&1; then
        run_cmd systemctl restart systemd-resolved.service || warn "systemd-resolved 重启失败，请手动检查。"
      else
        warn "systemd-resolved 存在但未启用，已写入 drop-in 配置。"
      fi
    else
      warn "未检测到 systemd-resolved，跳过 resolved drop-in。"
    fi
  fi

  echo
  echo "${BOLD}解析测试：raw.githubusercontent.com${RESET}"
  if getent ahosts raw.githubusercontent.com; then
    ok "getent 测试完成。raw.githubusercontent.com 能解析即可。"
  else
    warn "getent 解析失败，可能仍受 DNS、出口路由或污染影响。"
  fi
  warn "github.com 主站可能仍因出口路由不可达；Release 下载推荐 ghfast 镜像。"
}

write_resolved_ipv6_lockdown() {
  local file="/etc/systemd/resolved.conf.d/98-leikwan-ipv6-lockdown.conf"
  local content='[Resolve]
LLMNR=no
MulticastDNS=no'

  if resolved_available; then
    install -d -m 755 /etc/systemd/resolved.conf.d
    write_text_file "$file" "$content" 644 || true
    if systemctl is-active systemd-resolved.service >/dev/null 2>&1; then
      run_cmd systemctl restart systemd-resolved.service || warn "systemd-resolved 重启失败，请手动检查。"
    fi
  fi
}

ipv6_lockdown() {
  need_root
  init_log
  ensure_supported_os

  local summary
  summary="动作：安装 iptables-persistent，创建并刷新 V6_LOCKDOWN 链。\n允许：lo、ESTABLISHED/RELATED、ipv6-icmp、tcp/22。\n拒绝：其他 IPv6 入站流量 DROP。\n同时：关闭 LLMNR 和 MulticastDNS。\n保存：/etc/iptables/rules.v6。\n说明：不禁用 IPv6，不改 IPv4；WG/Xray 主链路不受 IPv6 入站收口影响。"

  if ! confirm_summary "IPv6 入站安全收口摘要" "$summary"; then
    warn "已取消 IPv6 入站安全收口。"
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections || true
  echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections || true
  install_packages iptables-persistent

  backup_file /etc/iptables/rules.v6

  ip6tables -N V6_LOCKDOWN 2>/dev/null || true
  ip6tables -F V6_LOCKDOWN
  ip6tables -A V6_LOCKDOWN -i lo -j ACCEPT
  ip6tables -A V6_LOCKDOWN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A V6_LOCKDOWN -p ipv6-icmp -j ACCEPT
  ip6tables -A V6_LOCKDOWN -p tcp --dport 22 -j ACCEPT
  ip6tables -A V6_LOCKDOWN -j DROP
  ip6tables -C INPUT -j V6_LOCKDOWN 2>/dev/null || ip6tables -I INPUT 1 -j V6_LOCKDOWN

  install -d -m 755 /etc/iptables
  ip6tables-save >/etc/iptables/rules.v6
  ok "IPv6 V6_LOCKDOWN 已保存到 /etc/iptables/rules.v6"

  write_resolved_ipv6_lockdown

  echo
  echo "${BOLD}主链路检查${RESET}"
  wg show 2>/dev/null || warn "未检测到 WireGuard 状态或 wg show 失败。"
  ss -lntup | grep -E "(:22|:${CLOUD_WG_PORT_DEFAULT}|:${CLIENT_ENTRY_PORT_DEFAULT}|:${LANDING_PORT_DEFAULT}|realm|xray)" || true
  ok "IPv6 入站收口完成。若业务需要 IPv6 公网入站，请先添加允许规则。"
}

PBR_FOUND_NAMES=()
PBR_FOUND_GWS=()
PBR_FOUND_IDS=()
PBR_FOUND_IPS=()
PBR_SELECTED_NAME=""

pbr_route_definitions() {
  cat <<'EOF'
9929 10.7.0.1 ^10\.7\.
CN2 10.8.0.1 ^10\.8\.
JPSDWAN 10.3.0.1 ^10\.3\.[0-3]\.
DESDWAN 10.3.10.1 ^10\.3\.(8|9|10|11)\.
KRSDWAN 10.4.0.1 ^10\.4\.[0-3]\.
HKSDWAN 10.3.50.1 ^10\.3\.(48|49|50|51)\.
TWSDWAN 10.3.100.1 ^10\.3\.(100|101|102|103)\.
SEATTLE 10.3.160.1 ^10\.3\.(160|161)\.
MOSCOW 10.3.170.1 ^10\.3\.(170|171)\.
SINGAPORE 10.3.180.1 ^10\.3\.180\.
USSDWAN-LAX 10.3.150.1 ^10\.3\.(150|151)\.
EOF
}

pbr_ensure_dir() {
  if (( DRY_RUN == 0 )); then
    install -d -m 755 "$PBR_DIR"
  fi
}

pbr_ensure_state_dir() {
  if (( DRY_RUN == 0 )); then
    install -d -m 755 "$PBR_STATE_DIR"
  fi
}

pbr_group_table_id() {
  local target="$1"
  local idx=101 name gw pattern
  while read -r name gw pattern; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == "$target" ]]; then
      printf '%s' "$idx"
      return 0
    fi
    idx=$((idx + 1))
  done < <(pbr_route_definitions)
  return 1
}

pbr_group_gateway() {
  local target="$1"
  local name gw pattern
  while read -r name gw pattern; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == "$target" ]]; then
      printf '%s' "$gw"
      return 0
    fi
  done < <(pbr_route_definitions)
  return 1
}

pbr_builtin_group_exists() {
  local target="$1"
  local name gw pattern
  while read -r name gw pattern; do
    [[ -z "$name" ]] && continue
    [[ "$name" == "$target" ]] && return 0
  done < <(pbr_route_definitions)
  return 1
}

pbr_table_id_to_name() {
  local table_id="$1"
  [[ -f "$PBR_RT_TABLES" ]] || return 1
  awk -v id="$table_id" '$1 == id {print $2; exit}' "$PBR_RT_TABLES"
}

pbr_lookup_to_group() {
  local lookup="$1"
  local table_name="$lookup"
  local group
  if [[ "$lookup" =~ ^[0-9]+$ ]]; then
    table_name="$(pbr_table_id_to_name "$lookup")"
  fi
  [[ "$table_name" == T_* ]] || return 1
  group="${table_name#T_}"
  pbr_builtin_group_exists "$group" || return 1
  printf '%s' "$group"
}

pbr_lookup_to_table_id() {
  local lookup="$1"
  local group
  if [[ "$lookup" =~ ^[0-9]+$ ]]; then
    printf '%s' "$lookup"
    return 0
  fi
  group="$(pbr_lookup_to_group "$lookup")" || return 1
  pbr_group_table_id "$group"
}

pbr_rule_target_to_cidr() {
  local target="$1"
  normalize_ipv4_cidr "$target"
}

pbr_ensure_rt_tables() {
  local content=""
  local changed=0
  local line
  if [[ -f "$PBR_RT_TABLES" ]]; then
    content="$(cat "$PBR_RT_TABLES")"
  else
    changed=1
  fi

  for line in "255 local" "254 main" "253 default" "0 unspec"; do
    if ! grep -Eq "^${line%% *}[[:space:]]+${line#* }([[:space:]]|$)" <<<"$content"; then
      content="${content%$'\n'}"$'\n'"$line"
      changed=1
    fi
  done

  if (( changed == 1 )); then
    write_text_file "$PBR_RT_TABLES" "${content#$'\n'}" 644 || true
  fi
}

pbr_ensure_table_for_group() {
  local group="$1"
  local table_id table_name content
  table_id="$(pbr_group_table_id "$group")" || return 1
  table_name="T_${group}"
  pbr_ensure_rt_tables
  content="$(cat "$PBR_RT_TABLES" 2>/dev/null || true)"
  if ! grep -Eq "^[0-9]+[[:space:]]+${table_name}([[:space:]]|$)" <<<"$content"; then
    content="${content%$'\n'}"$'\n'"${table_id} ${table_name}"
    write_text_file "$PBR_RT_TABLES" "${content#$'\n'}" 644 || true
  fi
}

pbr_ensure_tables_for_found_groups() {
  local content changed=0 i group table_id table_name line
  content="$(cat "$PBR_RT_TABLES" 2>/dev/null || true)"
  for line in "255 local" "254 main" "253 default" "0 unspec"; do
    if ! grep -Eq "^${line%% *}[[:space:]]+${line#* }([[:space:]]|$)" <<<"$content"; then
      content="${content%$'\n'}"$'\n'"$line"
      changed=1
    fi
  done
  for ((i = 0; i < ${#PBR_FOUND_NAMES[@]}; i++)); do
    group="${PBR_FOUND_NAMES[$i]}"
    table_id="$(pbr_group_table_id "$group")" || continue
    table_name="T_${group}"
    if ! grep -Eq "^[0-9]+[[:space:]]+${table_name}([[:space:]]|$)" <<<"$content"; then
      line="${table_id} ${table_name}"
      content="${content%$'\n'}"$'\n'"${line}"
      changed=1
    fi
  done
  if (( changed == 1 )); then
    write_text_file "$PBR_RT_TABLES" "${content#$'\n'}" 644 || true
  fi
}

pbr_detect_available_routes() {
  local mode="${1:-show}"
  local save="${2:-no}"
  local all_ips name gw pattern table_id matched matched_ips group_content

  PBR_FOUND_NAMES=()
  PBR_FOUND_GWS=()
  PBR_FOUND_IDS=()
  PBR_FOUND_IPS=()

  all_ips="$(ip -4 addr show 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | grep -v '^127\.' || true)"

  while read -r name gw pattern; do
    [[ -z "$name" ]] && continue
    matched=0
    matched_ips=""
    local ip_addr
    for ip_addr in $all_ips; do
      if [[ "$ip_addr" =~ $pattern ]]; then
        matched=1
        matched_ips="${matched_ips}${matched_ips:+,}${ip_addr}"
      fi
    done
    if (( matched == 1 )); then
      table_id="$(pbr_group_table_id "$name")"
      PBR_FOUND_NAMES+=("$name")
      PBR_FOUND_GWS+=("$gw")
      PBR_FOUND_IDS+=("$table_id")
      PBR_FOUND_IPS+=("$matched_ips")
      group_content="${group_content:-}${name} ${gw} T_${name} ${table_id} ${matched_ips}"$'\n'
    fi
  done < <(pbr_route_definitions)

  if [[ "$save" == "save" ]]; then
    pbr_ensure_dir
    pbr_ensure_tables_for_found_groups
    write_text_file "$PBR_GROUP_CONF" "${group_content:-}" 644 || true
  fi

  if [[ "$mode" != "quiet" ]]; then
    echo
    echo "${BOLD}可用 IPv4 出口线路组${RESET}"
    if (( ${#PBR_FOUND_NAMES[@]} == 0 )); then
      warn "未检测到匹配的利群常见线路组 IPv4 地址。"
    else
      printf '%-4s %-14s %-15s %-24s\n' "No." "线路组" "网关" "检测到的本机 IP"
      local i
      for ((i = 0; i < ${#PBR_FOUND_NAMES[@]}; i++)); do
        printf '%-4d %-14s %-15s %-24s\n' "$((i + 1))" "${PBR_FOUND_NAMES[$i]}" "${PBR_FOUND_GWS[$i]}" "${PBR_FOUND_IPS[$i]}"
      done
    fi
  fi
}

pbr_select_group() {
  local allow_all="${1:-yes}"
  local choice count name gw pattern
  pbr_detect_available_routes "show" "no"
  count="${#PBR_FOUND_NAMES[@]}"

  if (( count == 0 )) && [[ "$allow_all" != "yes" ]]; then
    return 1
  fi

  if [[ "$allow_all" == "yes" ]]; then
    echo "A. 其他：显示所有内置线路组"
  fi
  read -r -p "请选择线路组编号，或输入 A 查看全部，留空取消：" choice
  [[ -z "$choice" ]] && return 255

  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
    PBR_SELECTED_NAME="${PBR_FOUND_NAMES[$((choice - 1))]}"
    return 0
  fi

  if [[ "$allow_all" == "yes" && "$choice" =~ ^[Aa]$ ]]; then
    echo
    echo "${BOLD}全部内置线路组${RESET}"
    local idx=1
    while read -r name gw pattern; do
      printf '%-4d %-14s %-15s %s\n' "$idx" "$name" "$gw" "$pattern"
      idx=$((idx + 1))
    done < <(pbr_route_definitions)
    read -r -p "请选择线路组编号，留空取消：" choice
    [[ -z "$choice" ]] && return 255
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < idx )); then
      idx=1
      while read -r name gw pattern; do
        if (( idx == choice )); then
          PBR_SELECTED_NAME="$name"
          return 0
        fi
        idx=$((idx + 1))
      done < <(pbr_route_definitions)
    fi
  fi

  fail "无效线路组选择。"
  return 1
}

pbr_prepare_table_for_group() {
  local group="$1"
  local gw table_name
  gw="$(pbr_group_gateway "$group")" || {
    warn "未知线路组：${group}"
    return 1
  }
  table_name="T_${group}"
  pbr_ensure_table_for_group "$group"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将设置路由表 ${table_name}: default via ${gw}"
    return 0
  fi
  if ip route replace default via "$gw" table "$table_name" 2>/dev/null; then
    ok "已设置 ${table_name} 默认出口：${gw}"
  else
    warn "设置 ${table_name} 默认出口失败：${gw}。请确认本机具备该线路网关。"
    return 1
  fi
}

pbr_rule_exact_exists() {
  local priority="$1"
  local target="$2"
  local table_name="${3:-}"
  local target_cidr expected_table_id line_priority line_target line_lookup raw line_cidr line_table_id
  target_cidr="$(pbr_rule_target_to_cidr "$target" 2>/dev/null || true)"
  [[ -n "$target_cidr" ]] || return 1
  if [[ -n "$table_name" ]]; then
    expected_table_id="$(pbr_lookup_to_table_id "$table_name" 2>/dev/null || true)"
    [[ -n "$expected_table_id" ]] || return 1
  fi
  while IFS='|' read -r line_priority line_target line_lookup raw; do
    [[ -n "$line_priority" ]] || continue
    [[ "$line_priority" == "$priority" ]] || continue
    line_cidr="$(pbr_rule_target_to_cidr "$line_target" 2>/dev/null || true)"
    [[ "$line_cidr" == "$target_cidr" ]] || continue
    if [[ -n "$table_name" ]]; then
      line_table_id="$(pbr_lookup_to_table_id "$line_lookup" 2>/dev/null || true)"
      [[ "$line_table_id" == "$expected_table_id" ]] || continue
    fi
    return 0
  done < <(pbr_collect_relevant_rules)
  return 1
}

pbr_delete_rule_exact() {
  local priority="$1"
  local target="$2"
  local table_name="${3:-}"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将删除 ip rule priority ${priority} to ${target}${table_name:+ table ${table_name}}"
    return 0
  fi
  while pbr_rule_exact_exists "$priority" "$target" "$table_name"; do
    if [[ -n "$table_name" ]]; then
      ip rule del priority "$priority" to "$target" table "$table_name" 2>/dev/null || break
    else
      ip rule del priority "$priority" to "$target" 2>/dev/null || break
    fi
  done
}

pbr_add_rule_exact() {
  local priority="$1"
  local target="$2"
  local group="$3"
  local table_name="T_${group}"
  pbr_prepare_table_for_group "$group" || return 1
  pbr_delete_rule_exact "$priority" "$target" "$table_name"
  if (( DRY_RUN == 1 )); then
    echo "[DRY-RUN] 将添加 ip rule priority ${priority} to ${target} table ${table_name}"
    return 0
  fi
  ip rule add priority "$priority" to "$target" table "$table_name" 2>/dev/null || true
}

pbr_config_has_target() {
  local file="$1"
  local target="$2"
  [[ -f "$file" ]] || return 1
  awk -v t="$target" '$1 == t {found=1} END {exit !found}' "$file"
}

pbr_static_managed_group() {
  local cidr="$1"
  [[ -f "$PBR_STATIC_CONF" ]] || return 1
  awk -v c="$cidr" '$1 == c {print $2; exit}' "$PBR_STATIC_CONF"
}

pbr_domain_state_managed() {
  local cidr="$1"
  local table_id="$2"
  [[ -f "$PBR_DOMAIN_STATE" ]] || return 1
  awk -v c="$cidr" -v t="$table_id" '$4 == c && $5 == t {found=1} END {exit !found}' "$PBR_DOMAIN_STATE"
}

pbr_collect_relevant_rules() {
  ip rule show 2>/dev/null | awk -v ps="$PBR_STATIC_PRIORITY" -v pd="$PBR_DOMAIN_PRIORITY" '
    $1 ~ ":" {
      prio=$1
      sub(/:$/, "", prio)
      if (prio != ps && prio != pd) next
      target=""
      lookup=""
      for (i=1; i<=NF; i++) {
        if ($i == "to" && (i+1)<=NF) target=$(i+1)
        if ($i == "lookup" && (i+1)<=NF) lookup=$(i+1)
      }
      if (target ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/ && lookup != "") {
        print prio "|" target "|" lookup "|" $0
      }
    }'
}

pbr_rule_is_managed() {
  local priority="$1"
  local cidr="$2"
  local lookup="$3"
  local group table_id static_group
  group="$(pbr_lookup_to_group "$lookup" 2>/dev/null || true)"
  table_id="$(pbr_lookup_to_table_id "$lookup" 2>/dev/null || true)"
  static_group="$(pbr_static_managed_group "$cidr" 2>/dev/null || true)"
  if [[ -n "$static_group" && -n "$group" && "$static_group" == "$group" ]]; then
    return 0
  fi
  if [[ "$priority" == "$PBR_DOMAIN_PRIORITY" && -n "$table_id" ]]; then
    pbr_domain_state_managed "$cidr" "$table_id"
    return
  fi
  return 1
}

pbr_list_unmanaged_rules() {
  local line priority target lookup raw cidr
  while IFS='|' read -r priority target lookup raw; do
    [[ -n "$priority" ]] || continue
    cidr="$(pbr_rule_target_to_cidr "$target" 2>/dev/null || true)"
    [[ -n "$cidr" ]] || continue
    if ! pbr_rule_is_managed "$priority" "$cidr" "$lookup"; then
      printf '%s\n' "$raw"
    fi
  done < <(pbr_collect_relevant_rules)
}

pbr_list_managed_rules() {
  local line priority target lookup raw cidr
  while IFS='|' read -r priority target lookup raw; do
    [[ -n "$priority" ]] || continue
    cidr="$(pbr_rule_target_to_cidr "$target" 2>/dev/null || true)"
    [[ -n "$cidr" ]] || continue
    if pbr_rule_is_managed "$priority" "$cidr" "$lookup"; then
      printf '%s\n' "$raw"
    fi
  done < <(pbr_collect_relevant_rules)
}

pbr_add_static_route() {
  need_root_unless_dry_run
  init_log
  local ret input raw item cidr group content additions summary
  pbr_select_group "yes"
  ret=$?
  [[ $ret -eq 255 ]] && return 0
  [[ $ret -ne 0 ]] && return 1
  group="$PBR_SELECTED_NAME"
  input="$(prompt_non_empty "请输入目标 IPv4 / CIDR，多个用逗号分隔")"

  content="$(cat "$PBR_STATIC_CONF" 2>/dev/null || true)"
  additions=""
  IFS=',' read -r -a raw <<<"$input"
  for item in "${raw[@]}"; do
    if cidr="$(normalize_ipv4_cidr "$item")"; then
      if grep -Eq "^${cidr//./\\.}[[:space:]]+" <<<"$content" || grep -Eq "^${cidr//./\\.}[[:space:]]+" <<<"$additions"; then
        warn "跳过已存在目标：${cidr}"
      else
        additions="${additions}${cidr} ${group}"$'\n'
      fi
    else
      warn "跳过无效 IPv4/CIDR：${item}"
    fi
  done
  [[ -n "$additions" ]] || {
    warn "没有可添加的有效规则。"
    return 0
  }

  summary="规则类型：静态 IPv4 PBR\n优先级：${PBR_STATIC_PRIORITY}\n线路组：${group}\n路由表：T_${group}\n新增规则：\n${additions}\n说明：只为目标 IP/CIDR 指定出口，不修改 main 默认路由。"
  if ! confirm_summary "添加静态 IPv4 PBR 规则摘要" "$summary"; then
    return 0
  fi

  pbr_ensure_dir
  write_text_file "$PBR_STATIC_CONF" "$(printf '%s\n%s' "${content%$'\n'}" "${additions%$'\n'}" | sed '/^$/d')" 644 || true
  pbr_apply_saved_rules
}

pbr_resolve_domain_a() {
  local domain="$1"
  getent ahostsv4 "$domain" 2>/dev/null \
    | awk '{print $1}' \
    | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' \
    | sort -u \
    | paste -sd, - || true
}

pbr_add_domain_route() {
  need_root_unless_dry_run
  init_log
  local ret input item domain group ips content additions summary
  pbr_select_group "yes"
  ret=$?
  [[ $ret -eq 255 ]] && return 0
  [[ $ret -ne 0 ]] && return 1
  group="$PBR_SELECTED_NAME"
  input="$(prompt_non_empty "请输入域名，多个用逗号分隔，只解析 A 记录")"

  content="$(cat "$PBR_DOMAIN_CONF" 2>/dev/null || true)"
  additions=""
  IFS=',' read -r -a item <<<"$input"
  for domain in "${item[@]}"; do
    domain="$(trim_spaces "$domain")"
    [[ -n "$domain" ]] || continue
    if [[ "$domain" =~ [[:space:]/] ]]; then
      warn "跳过无效域名：${domain}"
      continue
    fi
    if grep -Eq "^${domain//./\\.}[[:space:]]+" <<<"$content" || grep -Eq "^${domain//./\\.}[[:space:]]+" <<<"$additions"; then
      warn "跳过已存在域名：${domain}"
      continue
    fi
    ips="$(pbr_resolve_domain_a "$domain")"
    if [[ -z "$ips" ]]; then
      warn "域名当前解析 A 记录失败，将保存规则；刷新失败时会保留旧状态和旧规则。"
    fi
    additions="${additions}${domain} ${group}"$'\n'
  done
  [[ -n "$additions" ]] || {
    warn "没有可添加的有效域名规则。"
    return 0
  }

  summary="规则类型：域名 DDNS IPv4 PBR\n优先级：${PBR_DOMAIN_PRIORITY}\n线路组：${group}\n路由表：T_${group}\n新增规则：\n${additions}\n说明：只解析 A 记录，不处理 AAAA；systemd timer 默认每 5 分钟刷新。"
  if ! confirm_summary "添加域名 DDNS IPv4 PBR 规则摘要" "$summary"; then
    return 0
  fi

  pbr_ensure_dir
  write_text_file "$PBR_DOMAIN_CONF" "$(printf '%s\n%s' "${content%$'\n'}" "${additions%$'\n'}" | sed '/^$/d')" 644 || true
  pbr_refresh_domains
  pbr_install_service
}

pbr_apply_static_rules() {
  [[ -s "$PBR_STATIC_CONF" ]] || return 0
  local cidr group
  while read -r cidr group _rest; do
    [[ -z "$cidr" || "$cidr" =~ ^# ]] && continue
    pbr_add_rule_exact "$PBR_STATIC_PRIORITY" "$cidr" "$group" || true
  done < "$PBR_STATIC_CONF"
}

pbr_refresh_domains() {
  need_root_unless_dry_run
  init_log
  pbr_detect_available_routes "quiet" "save" || true
  [[ -s "$PBR_DOMAIN_CONF" ]] || return 0

  pbr_ensure_state_dir

  local new_state="" handled_keys="" domain group new_ips ip_addr old_domain old_group old_ip old_cidr old_table old_key key
  while read -r domain group _rest; do
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue
    key="${domain} ${group}"
    handled_keys="${handled_keys}${key}"$'\n'
    new_ips="$(pbr_resolve_domain_a "$domain")"

    if [[ -z "$new_ips" ]]; then
      warn "域名解析失败，保留旧规则：${domain}"
      if [[ -f "$PBR_DOMAIN_STATE" ]]; then
        while read -r old_domain old_group old_ip old_cidr old_table _; do
          [[ -z "$old_domain" || "$old_domain" =~ ^# ]] && continue
          if [[ "$old_domain" == "$domain" && "$old_group" == "$group" ]]; then
            new_state="${new_state}${old_domain} ${old_group} ${old_ip} ${old_cidr} ${old_table}"$'\n'
          fi
        done < "$PBR_DOMAIN_STATE"
      fi
      continue
    fi

    if [[ -f "$PBR_DOMAIN_STATE" ]]; then
      while read -r old_domain old_group old_ip old_cidr old_table _; do
        [[ -z "$old_domain" || "$old_domain" =~ ^# ]] && continue
        if [[ "$old_domain" == "$domain" && "$old_group" == "$group" ]]; then
          pbr_delete_rule_exact "$PBR_DOMAIN_PRIORITY" "$old_cidr" "$old_table"
        fi
      done < "$PBR_DOMAIN_STATE"
    fi

    IFS=',' read -r -a new_arr <<<"$new_ips"
    for ip_addr in "${new_arr[@]}"; do
      [[ -n "$ip_addr" ]] || continue
      pbr_add_rule_exact "$PBR_DOMAIN_PRIORITY" "${ip_addr}/32" "$group" || true
      new_state="${new_state}${domain} ${group} ${ip_addr} ${ip_addr}/32 $(pbr_group_table_id "$group")"$'\n'
    done
  done < "$PBR_DOMAIN_CONF"

  if [[ -f "$PBR_DOMAIN_STATE" ]]; then
    while read -r old_domain old_group old_ip old_cidr old_table _; do
      [[ -z "$old_domain" || "$old_domain" =~ ^# ]] && continue
      old_key="${old_domain} ${old_group}"
      if ! grep -Fxq "$old_key" <<<"$handled_keys"; then
        pbr_delete_rule_exact "$PBR_DOMAIN_PRIORITY" "$old_cidr" "$old_table"
      fi
    done < "$PBR_DOMAIN_STATE"
  fi

  write_text_file "$PBR_DOMAIN_STATE" "${new_state%$'\n'}" 644 || true
}

pbr_apply_saved_rules() {
  need_root_unless_dry_run
  init_log
  pbr_ensure_dir
  pbr_detect_available_routes "quiet" "save" || true
  pbr_apply_static_rules
  pbr_refresh_domains
  ok "IPv4 PBR 规则已应用。"
}

pbr_audit_existing_rules() {
  local quiet="${1:-show}"
  local managed="" unmanaged="" conflicts="" line priority target lookup raw cidr group table_id expected_group actual_group count

  while IFS='|' read -r priority target lookup raw; do
    [[ -n "$priority" ]] || continue
    cidr="$(pbr_rule_target_to_cidr "$target" 2>/dev/null || true)"
    [[ -n "$cidr" ]] || continue
    actual_group="$(pbr_lookup_to_group "$lookup" 2>/dev/null || true)"
    table_id="$(pbr_lookup_to_table_id "$lookup" 2>/dev/null || true)"

    if pbr_rule_is_managed "$priority" "$cidr" "$lookup"; then
      managed="${managed}${raw}"$'\n'
    else
      unmanaged="${unmanaged}${raw}"$'\n'
    fi

    if [[ "$priority" == "$PBR_STATIC_PRIORITY" ]]; then
      expected_group="$(pbr_static_managed_group "$cidr" 2>/dev/null || true)"
      if [[ -n "$expected_group" && -n "$actual_group" && "$expected_group" != "$actual_group" ]]; then
        conflicts="${conflicts}配置要求 ${cidr} -> T_${expected_group}，系统存在 ${cidr} -> T_${actual_group}: ${raw}"$'\n'
      fi
    fi

    count="$(pbr_collect_relevant_rules | awk -F'|' -v p="$priority" -v t="$target" '$1==p && $2==t {c++} END{print c+0}')"
    if (( count > 1 )); then
      conflicts="${conflicts}同一目标存在多个 priority ${priority} 规则：${target}"$'\n'
    fi
  done < <(pbr_collect_relevant_rules)

  if [[ "$quiet" == "quiet" ]]; then
    [[ -n "$unmanaged" ]] && return 2
    [[ -n "$conflicts" ]] && return 3
    return 0
  fi

  echo
  echo "${BOLD}IPv4 PBR 审计${RESET}"
  echo
  echo "${BOLD}1. 本项目已管理规则${RESET}"
  [[ -n "$managed" ]] && printf '%s' "$managed" || echo "(无)"
  echo
  echo "${BOLD}2. 疑似手工规则 / 非本项目规则${RESET}"
  if [[ -n "$unmanaged" ]]; then
    printf '%s' "$unmanaged"
    warn "可在菜单中选择\"导入已有 PBR 规则\"接管。"
  else
    echo "(无)"
  fi
  echo
  echo "${BOLD}3. 冲突规则${RESET}"
  [[ -n "$conflicts" ]] && printf '%s' "$conflicts" || echo "(无)"
}

pbr_show() {
  local domain group ips state_domain state_group state_ip state_cidr state_table system_rules unmanaged_rules
  echo
  echo "${BOLD}1. 可用线路组${RESET}"
  pbr_detect_available_routes "quiet" "no" || true
  if (( ${#PBR_FOUND_NAMES[@]} == 0 )); then
    echo "(未检测到)"
  else
    local i
    for ((i = 0; i < ${#PBR_FOUND_NAMES[@]}; i++)); do
      printf '%s %s detected (%s)\n' "${PBR_FOUND_NAMES[$i]}" "${PBR_FOUND_GWS[$i]}" "${PBR_FOUND_IPS[$i]}"
    done
  fi

  echo
  echo "${BOLD}2. 项目静态规则${RESET}"
  if [[ -s "$PBR_STATIC_CONF" ]]; then
    awk '{print $1" -> "$2}' "$PBR_STATIC_CONF"
  else
    echo "(空)"
  fi

  echo
  echo "${BOLD}3. 项目域名规则${RESET}"
  if [[ -s "$PBR_DOMAIN_CONF" ]]; then
    awk '{print $1" -> "$2}' "$PBR_DOMAIN_CONF"
  else
    echo "(空)"
  fi

  echo
  echo "${BOLD}4. 域名当前解析状态${RESET}"
  if [[ -s "$PBR_DOMAIN_CONF" ]]; then
    while read -r domain group _; do
      [[ -z "$domain" || "$domain" =~ ^# ]] && continue
      ips="$(pbr_resolve_domain_a "$domain")"
      if [[ -n "$ips" ]]; then
        printf '%s -> %s\n' "$domain" "$ips"
      else
        warn "${domain} 当前解析失败"
      fi
    done < "$PBR_DOMAIN_CONF"
  else
    echo "(空)"
  fi

  echo
  echo "${BOLD}5. 域名状态文件${RESET}"
  if [[ -s "$PBR_DOMAIN_STATE" ]]; then
    while read -r state_domain state_group state_ip state_cidr state_table _; do
      [[ -z "$state_domain" || "$state_domain" =~ ^# ]] && continue
      printf '%s -> %s (%s table %s)\n' "$state_domain" "$state_ip" "$state_cidr" "$state_table"
    done < "$PBR_DOMAIN_STATE"
  else
    echo "(空)"
  fi

  echo
  echo "${BOLD}6. 系统生效规则${RESET}"
  system_rules="$(pbr_collect_relevant_rules | awk -F'|' '{print $4}' || true)"
  if [[ -n "$system_rules" ]]; then
    printf '%s\n' "$system_rules"
  else
    echo "(无)"
  fi

  echo
  echo "${BOLD}7. 未被项目管理的疑似规则${RESET}"
  unmanaged_rules="$(pbr_list_unmanaged_rules | sed '/^$/d' || true)"
  if [[ -n "$unmanaged_rules" ]]; then
    printf '%s\n' "$unmanaged_rules"
  else
    echo "(无)"
  fi
}

pbr_delete_rule() {
  need_root_unless_dry_run
  init_log
  local kind file priority choice total line target group ips summary
  echo "1. 删除静态 IP/CIDR 规则"
  echo "2. 删除域名 DDNS 规则"
  read -r -p "请选择：" kind
  case "$kind" in
    1) file="$PBR_STATIC_CONF"; priority="$PBR_STATIC_PRIORITY" ;;
    2) file="$PBR_DOMAIN_CONF"; priority="$PBR_DOMAIN_PRIORITY" ;;
    *) warn "无效选择。"; return 1 ;;
  esac
  [[ -s "$file" ]] || {
    warn "规则文件为空：${file}"
    return 0
  }

  awk '{print NR". "$0}' "$file"
  choice="$(prompt_value "请输入要删除的编号")"
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "编号无效。"
    return 1
  }
  total="$(wc -l < "$file")"
  (( choice >= 1 && choice <= total )) || {
    warn "编号超出范围。"
    return 1
  }
  line="$(awk -v n="$choice" 'NR==n {print; exit}' "$file")"
  target="$(awk -v n="$choice" 'NR==n {print $1; exit}' "$file")"
  group="$(awk -v n="$choice" 'NR==n {print $2; exit}' "$file")"
  ips="$(awk -v n="$choice" 'NR==n {print $3; exit}' "$file")"

  summary="文件：${file}\n删除行：${line}\n动作：删除配置行，并只删除本项目对应 priority ${priority} 的 ip rule。"
  if ! confirm_summary "删除 IPv4 PBR 规则摘要" "$summary"; then
    return 0
  fi

  if [[ "$kind" == "1" ]]; then
    pbr_delete_rule_exact "$priority" "$target" "T_${group}"
  else
    if [[ -f "$PBR_DOMAIN_STATE" ]]; then
      local state_domain state_group state_ip state_cidr state_table kept_state=""
      while read -r state_domain state_group state_ip state_cidr state_table _; do
        [[ -z "$state_domain" || "$state_domain" =~ ^# ]] && continue
        if [[ "$state_domain" == "$target" && "$state_group" == "$group" ]]; then
          pbr_delete_rule_exact "$priority" "$state_cidr" "$state_table"
        else
          kept_state="${kept_state}${state_domain} ${state_group} ${state_ip} ${state_cidr} ${state_table}"$'\n'
        fi
      done < "$PBR_DOMAIN_STATE"
      write_text_file "$PBR_DOMAIN_STATE" "${kept_state%$'\n'}" 644 || true
    fi
  fi

  write_text_file "$file" "$(awk -v n="$choice" 'NR != n {print}' "$file")" 644 || true
  ok "已删除规则。"
}

pbr_install_service() {
  need_root_unless_dry_run
  init_log
  local script_path pbr_service_content ddns_service_content timer_content summary
  script_path="$(script_self_path)"
  pbr_service_content="$(cat <<EOF
# Managed by leikwan-wg-toolkit
[Unit]
Description=Leikwan IPv4 PBR apply saved rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${script_path} --pbr-apply

[Install]
WantedBy=multi-user.target
EOF
)"
  ddns_service_content="$(cat <<EOF
# Managed by leikwan-wg-toolkit
[Unit]
Description=Leikwan IPv4 PBR refresh domain routes
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${script_path} --pbr-refresh-domains
EOF
)"
  timer_content="$(cat <<EOF
# Managed by leikwan-wg-toolkit
[Unit]
Description=Leikwan IPv4 PBR DDNS refresh timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=${PBR_DDNS_SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF
)"

  summary="服务：${PBR_SERVICE_NAME}.service\n动作：开机执行 --pbr-apply，只应用本项目保存的规则。\n\n服务：${PBR_DDNS_SERVICE_NAME}.service\n定时器：${PBR_DDNS_SERVICE_NAME}.timer\n动作：每 5 分钟执行 --pbr-refresh-domains，刷新域名 A 记录。\n\n说明：不修改 main 默认路由，不删除系统已有默认网关。"
  if ! confirm_summary "安装 / 重启 IPv4 PBR 开机恢复服务摘要" "$summary"; then
    return 0
  fi

  write_text_file "$PBR_SERVICE" "$pbr_service_content" 644 || true
  write_text_file "$PBR_DDNS_SERVICE" "$ddns_service_content" 644 || true
  write_text_file "$PBR_DDNS_TIMER" "$timer_content" 644 || true
  run_cmd systemctl daemon-reload
  run_cmd systemctl enable "$PBR_SERVICE_NAME.service"
  run_cmd systemctl enable --now "$PBR_DDNS_SERVICE_NAME.timer"
  run_cmd systemctl restart "$PBR_SERVICE_NAME.service" || true
  ok "IPv4 PBR 开机恢复服务和 DDNS timer 已安装/重启。"
}

pbr_read_landing_address() {
  local value=""
  value="$(saved_param LANDING_ADDRESS "$RELAY_OUTPUT_FILE" "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(parse_landing_from_xray_config address || true)"
  fi
  if [[ -n "$value" && ! "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    local resolved
    resolved="$(pbr_resolve_domain_a "$value" | cut -d, -f1)"
    [[ -n "$resolved" ]] && value="$resolved"
  fi
  printf '%s' "$value"
}

pbr_group_from_route_output() {
  local route_output="$1"
  local name gw pattern escaped_gw
  while read -r name gw pattern; do
    [[ -z "$name" ]] && continue
    escaped_gw="${gw//./\\.}"
    if grep -Eq "(^|[[:space:]])via[[:space:]]+${escaped_gw}([[:space:]]|$)" <<<"$route_output"; then
      printf '%s' "$name"
      return 0
    fi
  done < <(pbr_route_definitions)
  return 1
}

pbr_route_landing() {
  need_root_unless_dry_run
  init_log
  local landing_ip cidr content imported_content group summary ret existing_raw="" existing_group="" existing_lookup="" existing_priority="" config_group="" new_content
  landing_ip="$(pbr_read_landing_address)"
  if ! is_ipv4 "$landing_ip"; then
    landing_ip="$(prompt_non_empty "未读取到 Reality 落地机 IPv4，请输入 LANDING_ADDRESS IPv4")"
  fi
  is_ipv4 "$landing_ip" || {
    fail "落地机地址不是有效 IPv4：${landing_ip}"
    return 1
  }
  pbr_select_group "yes"
  ret=$?
  [[ $ret -eq 255 ]] && return 0
  [[ $ret -ne 0 ]] && return 1
  group="$PBR_SELECTED_NAME"
  cidr="${landing_ip}/32"
  content="$(cat "$PBR_STATIC_CONF" 2>/dev/null || true)"

  while IFS='|' read -r existing_priority target existing_lookup raw; do
    [[ "$existing_priority" == "$PBR_STATIC_PRIORITY" ]] || continue
    if [[ "$(pbr_rule_target_to_cidr "$target" 2>/dev/null || true)" == "$cidr" ]]; then
      existing_group="$(pbr_lookup_to_group "$existing_lookup" 2>/dev/null || true)"
      existing_raw="$raw"
      break
    fi
  done < <(pbr_collect_relevant_rules)

  config_group="$(pbr_static_managed_group "$cidr" 2>/dev/null || true)"

  if [[ -n "$config_group" ]]; then
    if [[ "$config_group" == "$group" ]]; then
      ok "落地机规则已由本项目托管：${cidr} -> ${group}"
    else
      warn "检测到本项目已有落地机规则：${cidr} -> ${config_group}"
      summary="目标：${cidr}\n当前托管出口：T_${config_group}\n新出口：T_${group}\n动作：只删除 ${cidr} 在 T_${config_group} 的旧托管规则，并改写为 T_${group}。"
      if ! confirm_summary "修改 Reality 落地机 PBR 出口摘要" "$summary"; then
        return 0
      fi
      pbr_delete_rule_exact "$PBR_STATIC_PRIORITY" "$cidr" "T_${config_group}"
      new_content="$(awk -v c="$cidr" -v g="$group" '$1 == c {$2=g} {print}' <<<"$content")"
      write_text_file "$PBR_STATIC_CONF" "$new_content" 644 || true
    fi
  elif [[ -n "$existing_raw" ]]; then
    warn "检测到已有手工规则：${existing_raw}"
    if [[ "$existing_group" == "$group" ]]; then
      summary="检测到已有规则：${existing_raw}\n导入为：${cidr} ${group}\n动作：只写入 ${PBR_STATIC_CONF}，不删除原系统规则；后续 --pbr-apply 会识别为本项目托管。"
      if ! confirm_summary "导入 Reality 落地机已有 PBR 规则摘要" "$summary"; then
        warn "未导入已有规则，不重复添加。"
        return 0
      fi
      pbr_ensure_dir
      write_text_file "$PBR_STATIC_CONF" "$(printf '%s\n%s %s\n' "${content%$'\n'}" "$cidr" "$group" | sed '/^$/d')" 644 || true
    else
      warn "冲突：已有规则走 ${existing_group:-未知出口}，你选择的是 ${group}。"
      if [[ -z "$existing_group" ]]; then
        warn "无法把已有 lookup 反查为内置线路组，已停止，避免误删非项目规则。"
        return 0
      fi
      summary="检测到已有手工规则：${existing_raw}\n目标：${cidr}\n已有出口：T_${existing_group}\n新出口：T_${group}\n动作：先导入已有规则作为本项目托管记录，再仅删除同一目标 ${cidr} 的 T_${existing_group} 规则，最后改写为 T_${group}。不会删除其他目标或默认路由。"
      if ! confirm_summary "接管并修改 Reality 落地机 PBR 出口摘要" "$summary"; then
        warn "未接管已有规则，不重复添加冲突规则。"
        return 0
      fi
      pbr_ensure_dir
      imported_content="$(printf '%s\n%s %s\n' "${content%$'\n'}" "$cidr" "$existing_group" | sed '/^$/d')"
      write_text_file "$PBR_STATIC_CONF" "$imported_content" 644 || true
      pbr_delete_rule_exact "$PBR_STATIC_PRIORITY" "$cidr" "T_${existing_group}"
      new_content="$(awk -v c="$cidr" -v g="$group" '$1 == c {$2=g} {print}' <<<"$imported_content")"
      write_text_file "$PBR_STATIC_CONF" "$new_content" 644 || true
    fi
  else
    summary="目标：${cidr}\n线路组：${group}\n路由表：T_${group}\n动作：为当前 Reality 落地机指定 IPv4 出口，并执行 ip route get ${landing_ip}。"
    if ! confirm_summary "一键为 Reality 落地机指定出口摘要" "$summary"; then
      return 0
    fi
    pbr_ensure_dir
    write_text_file "$PBR_STATIC_CONF" "$(printf '%s\n%s %s\n' "${content%$'\n'}" "$cidr" "$group" | sed '/^$/d')" 644 || true
  fi

  pbr_apply_saved_rules
  echo
  echo "${BOLD}当前实际出口：ip route get ${landing_ip}${RESET}"
  ip route get "$landing_ip" || true
}

pbr_import_existing_rules() {
  need_root_unless_dry_run
  init_log
  local pbr_candidates="" priority target lookup raw cidr group content import_all=0 choice additions="" imported_targets=""
  while IFS='|' read -r priority target lookup raw; do
    [[ -n "$priority" ]] || continue
    cidr="$(pbr_rule_target_to_cidr "$target" 2>/dev/null || true)"
    [[ -n "$cidr" ]] || continue
    group="$(pbr_lookup_to_group "$lookup" 2>/dev/null || true)"
    [[ -n "$group" ]] || continue
    if [[ "$priority" != "$PBR_STATIC_PRIORITY" && "$priority" != "$PBR_DOMAIN_PRIORITY" ]]; then
      continue
    fi
    if pbr_rule_is_managed "$priority" "$cidr" "$lookup"; then
      continue
    fi
    pbr_candidates="${pbr_candidates}${priority}|${cidr}|${group}|${raw}"$'\n'
  done < <(pbr_collect_relevant_rules)

  if [[ -z "$pbr_candidates" ]]; then
    ok "未发现可导入的已有 IPv4 PBR 规则。"
    return 0
  fi

  echo
  echo "${BOLD}可导入的已有 IPv4 PBR 规则${RESET}"
  printf '%s' "$pbr_candidates" | awk -F'|' '{printf "%d. priority %s %s -> %s | %s\n", NR, $1, $2, $3, $4}'

  content="$(cat "$PBR_STATIC_CONF" 2>/dev/null || true)"
  while IFS='|' read -r priority cidr group raw; do
    [[ -n "$priority" ]] || continue
    if grep -Eq "^${cidr//./\\.}[[:space:]]+${group}([[:space:]]|$)" <<<"$content" || grep -Eq "^${cidr//./\\.}[[:space:]]+${group}([[:space:]]|$)" <<<"$additions"; then
      continue
    fi
    if (( import_all == 0 )); then
      echo
      echo "规则：${raw}"
      echo "导入为：${cidr} ${group}"
      echo "1. 导入"
      echo "2. 跳过"
      echo "3. 全部导入"
      echo "4. 取消"
      read -r -p "请选择：" choice
      case "$choice" in
        1) ;;
        2) continue ;;
        3) import_all=1 ;;
        4) warn "已取消导入。"; break ;;
        *) warn "无效选择，跳过。"; continue ;;
      esac
    fi
    additions="${additions}${cidr} ${group}"$'\n'
    imported_targets="${imported_targets}${cidr}"$'\n'
  done <<<"$pbr_candidates"

  [[ -n "$additions" ]] || {
    warn "没有导入任何规则。"
    return 0
  }

  local summary="导入目标文件：${PBR_STATIC_CONF}\n新增规则：\n${additions}\n说明：导入后不删除原系统规则；后续 --pbr-apply 会识别为本项目托管规则。"
  if ! confirm_summary "导入已有 IPv4 PBR 规则摘要" "$summary"; then
    return 0
  fi

  pbr_ensure_dir
  write_text_file "$PBR_STATIC_CONF" "$(printf '%s\n%s' "${content%$'\n'}" "${additions%$'\n'}" | sed '/^$/d')" 644 || true
  ok "导入完成。"

  while read -r existing; do
    [[ -n "$existing" ]] || continue
    echo
    echo "${BOLD}实际出口：ip route get ${existing%/32}${RESET}"
    ip route get "${existing%/32}" || true
  done <<<"$imported_targets"
}

pbr_remove_project_rules_only() {
  need_root
  init_log
  local cidr group domain state_ip state_cidr state_table managed_summary="" unmanaged_summary content name gw pattern
  if [[ -s "$PBR_STATIC_CONF" ]]; then
    while read -r cidr group _rest; do
      [[ -z "$cidr" || "$cidr" =~ ^# ]] && continue
      managed_summary="${managed_summary}priority ${PBR_STATIC_PRIORITY}: to ${cidr} table T_${group}"$'\n'
      if pbr_rule_exact_exists "$PBR_DOMAIN_PRIORITY" "$cidr" "T_${group}"; then
        managed_summary="${managed_summary}priority ${PBR_DOMAIN_PRIORITY}: to ${cidr} table T_${group} (static-routes.conf 导入托管)"$'\n'
      fi
    done < "$PBR_STATIC_CONF"
  fi
  if [[ -s "$PBR_DOMAIN_STATE" ]]; then
    while read -r domain group state_ip state_cidr state_table _rest; do
      [[ -z "$domain" || "$domain" =~ ^# ]] && continue
      managed_summary="${managed_summary}priority ${PBR_DOMAIN_PRIORITY}: ${domain} ${state_ip} (${state_cidr}) table ${state_table}"$'\n'
    done < "$PBR_DOMAIN_STATE"
  fi
  unmanaged_summary="$(pbr_list_unmanaged_rules | sed '/^$/d' || true)"
  summary="将删除以下本项目托管规则：\n${managed_summary:-（无）}\n以下同 priority 但未托管规则会保留：\n${unmanaged_summary:-（无）}\n说明：不会清空 ${PBR_RT_TABLES}，不会修改 main/default/local 基础表，不删除系统默认网关。"
  if ! confirm_summary "仅删除 IPv4 PBR 规则摘要" "$summary"; then
    return 0
  fi

  if [[ -s "$PBR_STATIC_CONF" ]]; then
    while read -r cidr group _rest; do
      [[ -z "$cidr" || "$cidr" =~ ^# ]] && continue
      pbr_delete_rule_exact "$PBR_STATIC_PRIORITY" "$cidr" "T_${group}"
      pbr_delete_rule_exact "$PBR_DOMAIN_PRIORITY" "$cidr" "T_${group}"
    done < "$PBR_STATIC_CONF"
  fi
  if [[ -s "$PBR_DOMAIN_STATE" ]]; then
    while read -r domain group state_ip state_cidr state_table _rest; do
      [[ -z "$domain" || "$domain" =~ ^# ]] && continue
      pbr_delete_rule_exact "$PBR_DOMAIN_PRIORITY" "$state_cidr" "$state_table"
    done < "$PBR_DOMAIN_STATE"
  fi
  ok "已删除本项目 IPv4 PBR 运行中规则。"
  warn "如果 ${PBR_DDNS_SERVICE_NAME}.timer 仍在运行，域名规则可能会被再次刷新。"

  if prompt_yes_no "是否二次确认删除 rt_tables 中本项目追加的 T_ 表名？" "N"; then
    if prompt_yes_no "二次确认：删除 T_9929/T_CN2 等本项目表名，但保留系统默认表？" "N"; then
      content="$(cat "$PBR_RT_TABLES" 2>/dev/null || true)"
      while read -r name gw pattern; do
        [[ -z "$name" ]] && continue
        content="$(printf '%s\n' "$content" | grep -Ev "^[0-9]+[[:space:]]+T_${name}([[:space:]]|$)" || true)"
      done < <(pbr_route_definitions)
      write_text_file "$PBR_RT_TABLES" "$content" 644 || true
      ok "已删除本项目 T_ 路由表名。"
    fi
  fi
}

pbr_menu() {
  while true; do
    echo
    echo "${BOLD}IPv4 多出口策略路由${RESET}"
    echo "1. 检测可用 IPv4 出口"
    echo "2. 添加目标 IP/CIDR 指定出口"
    echo "3. 添加域名 DDNS 指定出口"
    echo "4. 一键为当前 Reality 落地机指定出口"
    echo "5. 查看当前 PBR 规则"
    echo "6. 删除规则"
    echo "7. 刷新并应用规则"
    echo "8. 安装 / 重启 PBR 开机恢复服务"
    echo "9. 导入已有 PBR 规则"
    echo "0. 返回"
    read -r -p "请选择：" choice
    case "$choice" in
      1) pbr_detect_available_routes "show" "no" || true ;;
      2) pbr_add_static_route || true ;;
      3) pbr_add_domain_route || true ;;
      4) pbr_route_landing || true ;;
      5) pbr_show || true ;;
      6) pbr_delete_rule || true ;;
      7) pbr_apply_saved_rules || true ;;
      8) pbr_install_service || true ;;
      9) pbr_import_existing_rules || true ;;
      0) return 0 ;;
      *) echo "无效选择。" ;;
    esac
  done
}

show_status() {
  need_root
  init_log
  echo
  echo "${BOLD}WireGuard 状态${RESET}"
  if command -v wg >/dev/null 2>&1; then
    wg show || true
  else
    warn "未安装 wg 命令。"
  fi

  echo
  echo "${BOLD}接口地址${RESET}"
  ip addr show wg0 2>/dev/null || true
  ip addr show wg1 2>/dev/null || true

  echo
  echo "${BOLD}Xray 状态${RESET}"
  systemctl status "${XRAY_LEIKWAN_SERVICE_NAME}" --no-pager 2>/dev/null \
    || systemctl status xray --no-pager 2>/dev/null \
    || warn "未检测到 xray-leikwan.service / xray.service 或服务未运行。"
  [[ -x "$XRAY_BIN" ]] && "$XRAY_BIN" version 2>/dev/null | head -n 1 || true

  echo
  echo "${BOLD}realm 状态${RESET}"
  local services=()
  [[ -f "$REALM_ENTRY_SERVICE" ]] && services+=("$REALM_ENTRY_SERVICE")
  local service stem
  if (( ${#services[@]} == 0 )); then
    warn "未找到本项目创建的 realm 服务。"
  else
    for service in "${services[@]}"; do
      stem="$(basename "$service" .service)"
      systemctl --no-pager --full status "${stem}.service" || true
    done
  fi

  echo
  echo "${BOLD}关键端口${RESET}"
  ss -lntup | grep -E "(:${CLOUD_WG_PORT_DEFAULT}|:${CLIENT_ENTRY_PORT_DEFAULT}|:${LANDING_PORT_DEFAULT}|realm|xray)" || warn "未匹配到默认关键端口。"
}

create_snapshot_backup() {
  need_root
  init_log
  local tag="${1:-manual}"
  local tar_path
  tar_path="${BACKUP_DIR}/${tag}-$(date '+%Y%m%d-%H%M%S').tar.gz"
  local paths=()

  mkdir -p "$BACKUP_DIR"
  [[ -e /etc/wireguard ]] && paths+=(etc/wireguard)
  [[ -e "$XRAY_CONFIG" ]] && paths+=("${XRAY_CONFIG#/}")
  [[ -e "$STATE_DIR" ]] && paths+=("${STATE_DIR#/}")
  [[ -e /etc/gai.conf ]] && paths+=(etc/gai.conf)
  [[ -e /etc/systemd/resolved.conf.d/99-custom-dns.conf ]] && paths+=(etc/systemd/resolved.conf.d/99-custom-dns.conf)
  [[ -e /etc/systemd/resolved.conf.d/98-leikwan-ipv6-lockdown.conf ]] && paths+=(etc/systemd/resolved.conf.d/98-leikwan-ipv6-lockdown.conf)
  [[ -e /etc/iptables/rules.v4 ]] && paths+=(etc/iptables/rules.v4)
  [[ -e /etc/iptables/rules.v6 ]] && paths+=(etc/iptables/rules.v6)
  [[ -e "$PBR_DIR" ]] && paths+=("${PBR_DIR#/}")
  [[ -e "$PBR_SERVICE" ]] && paths+=("${PBR_SERVICE#/}")
  [[ -e "$PBR_DDNS_SERVICE" ]] && paths+=("${PBR_DDNS_SERVICE#/}")
  [[ -e "$PBR_DDNS_TIMER" ]] && paths+=("${PBR_DDNS_TIMER#/}")
  [[ -e "$PBR_RT_TABLES" ]] && paths+=("${PBR_RT_TABLES#/}")

  shopt -s nullglob
  local realm_files=("${REALM_DIR}"/*.toml /etc/systemd/system/realm-leikwan.service)
  shopt -u nullglob
  local item
  for item in "${realm_files[@]}"; do
    [[ -e "$item" ]] && paths+=("${item#/}")
  done

  if (( ${#paths[@]} == 0 )); then
    warn "没有找到可备份的项目相关配置。"
    return 0
  fi

  tar -C / -czf "$tar_path" "${paths[@]}"
  ok "快照备份已创建：${tar_path}"
}

list_snapshot_backups() {
  need_root
  shopt -s nullglob
  local backups=("${BACKUP_DIR}"/*.tar.gz)
  shopt -u nullglob

  if (( ${#backups[@]} == 0 )); then
    warn "暂无快照备份。"
    return 0
  fi

  local i=1 item
  for item in "${backups[@]}"; do
    printf '%d. %s\n' "$i" "$item"
    i=$((i + 1))
  done
}

restore_snapshot_backup() {
  need_root
  init_log
  shopt -s nullglob
  local backups=("${BACKUP_DIR}"/*.tar.gz)
  shopt -u nullglob

  if (( ${#backups[@]} == 0 )); then
    warn "暂无快照备份可恢复。"
    return 0
  fi

  list_snapshot_backups
  local choice idx backup summary
  choice="$(prompt_value "请输入要恢复的备份编号")"
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#backups[@]} )); then
    fail "编号无效。"
    return 1
  fi
  idx=$((choice - 1))
  backup="${backups[$idx]}"
  summary="备份：${backup}\n动作：先创建 pre-restore 快照，再将备份内容恢复到 /etc 与 systemd 相关路径。"
  if ! confirm_summary "恢复备份摘要" "$summary"; then
    warn "已取消恢复。"
    return 0
  fi

  create_snapshot_backup "pre-restore"
  tar -C / -xzf "$backup"
  run_cmd systemctl daemon-reload || true
  ok "恢复完成。WireGuard、Xray 或 realm 服务如需生效，请手动重启对应服务。"
}

backup_restore_menu() {
  while true; do
    echo
    echo "${BOLD}备份 / 恢复${RESET}"
    echo "1. 创建快照备份"
    echo "2. 查看快照备份"
    echo "3. 从快照恢复"
    echo "0. 返回主菜单"
    read -r -p "请选择：" choice
    case "$choice" in
      1) create_snapshot_backup "manual" || true ;;
      2) list_snapshot_backups || true ;;
      3) restore_snapshot_backup || true ;;
      0) return 0 ;;
      *) echo "无效选择。" ;;
    esac
  done
}

remove_ipv6_lockdown() {
  need_root
  init_log
  local summary="动作：删除 INPUT 中跳转到 V6_LOCKDOWN 的规则，清空并删除 V6_LOCKDOWN 链，然后保存 /etc/iptables/rules.v6。"
  if ! confirm_summary "删除 IPv6 V6_LOCKDOWN 摘要" "$summary"; then
    warn "已取消删除 IPv6 V6_LOCKDOWN。"
    return 0
  fi

  if ! command -v ip6tables >/dev/null 2>&1; then
    warn "未检测到 ip6tables。"
    return 0
  fi

  while ip6tables -C INPUT -j V6_LOCKDOWN 2>/dev/null; do
    ip6tables -D INPUT -j V6_LOCKDOWN || break
  done

  if ip6tables -L V6_LOCKDOWN >/dev/null 2>&1; then
    ip6tables -F V6_LOCKDOWN || true
    ip6tables -X V6_LOCKDOWN || true
  fi

  if [[ -e /etc/iptables/rules.v6 ]]; then
    backup_file /etc/iptables/rules.v6
    ip6tables-save >/etc/iptables/rules.v6 || true
  fi
  ok "已删除 IPv6 V6_LOCKDOWN 规则。"
}

remove_project_realm_services() {
  local services=()
  [[ -f "$REALM_ENTRY_SERVICE" ]] && services+=("$REALM_ENTRY_SERVICE")
  local service stem conf summary

  if (( ${#services[@]} == 0 )); then
    warn "未找到本项目创建的 realm 服务。"
    return 0
  fi

  summary="动作：停止并删除本项目创建的 realm-leikwan.service 与 ${REALM_DIR} 下对应配置。\n不会删除用户其他 realm 服务。"
  if ! confirm_summary "删除 realm 服务摘要" "$summary"; then
    warn "已取消删除 realm 服务。"
    return 0
  fi

  for service in "${services[@]}"; do
    stem="$(basename "$service" .service)"
    conf="$(grep -Eo -- '-c[[:space:]]+[^[:space:]]+' "$service" | awk '{print $2}' | tail -n 1 || true)"
    systemctl disable --now "${stem}.service" >/dev/null 2>&1 || true
    backup_file "$service"
    rm -f "$service"
    if [[ -n "$conf" && "$conf" == "$REALM_DIR"/* && -f "$conf" ]]; then
      backup_file "$conf"
      rm -f "$conf"
    fi
    ok "已删除 realm 服务：${stem}.service"
  done
  run_cmd systemctl daemon-reload || true
}

wg_config_is_managed() {
  local conf="$1"
  [[ -f "$conf" ]] && grep -q 'Managed by leikwan-wg-toolkit' "$conf"
}

remove_wg_iface_if_managed() {
  local iface="$1"
  local conf="/etc/wireguard/${iface}.conf"

  if [[ ! -e "$conf" ]]; then
    warn "未找到 ${conf}。"
    return 0
  fi

  if ! wg_config_is_managed "$conf"; then
    warn "${conf} 不是本项目标记创建的配置，跳过删除。"
    return 0
  fi

  local summary="接口：${iface}\n配置：${conf}\n动作：停止并禁用 wg-quick@${iface}，备份后删除本项目创建的配置文件。"
  if ! confirm_summary "删除 WireGuard ${iface} 摘要" "$summary"; then
    warn "已取消删除 ${iface}。"
    return 0
  fi

  systemctl disable --now "wg-quick@${iface}.service" >/dev/null 2>&1 || true
  backup_file "$conf"
  rm -f "$conf"
  ok "已删除 ${conf}"
}

xray_config_is_managed() {
  [[ -f "$XRAY_CONFIG" ]] && grep -q 'leikwan-' "$XRAY_CONFIG"
}

remove_xray_config_with_double_confirm() {
  if [[ ! -f "$XRAY_CONFIG" ]]; then
    warn "未找到 ${XRAY_CONFIG}。"
    return 0
  fi

  if ! xray_config_is_managed; then
    warn "${XRAY_CONFIG} 未检测到本项目 tag，跳过删除。"
    return 0
  fi

  local role="$1"
  local summary="角色：${role}\n配置：${XRAY_CONFIG}\n动作：停止 xray-leikwan.service；如果用户选择过覆盖模式且 unit 带本项目标记，也会按确认删除。\n不会删除 xray 二进制，不会删除非本项目 systemd 服务。"
  if ! confirm_summary "删除 Xray 配置摘要" "$summary"; then
    warn "已取消删除 Xray 配置。"
    return 0
  fi
  if ! prompt_yes_no "二次确认：确定删除 ${XRAY_CONFIG} 吗？" "N"; then
    warn "二次确认未通过，保留 Xray 配置。"
    return 0
  fi

  systemctl stop "${XRAY_LEIKWAN_SERVICE_NAME}.service" >/dev/null 2>&1 || true
  systemctl stop xray.service >/dev/null 2>&1 || true
  backup_file "$XRAY_CONFIG"
  rm -f "$XRAY_CONFIG"
  ok "已删除 ${XRAY_CONFIG}"

  if [[ -f "$XRAY_LEIKWAN_SERVICE" ]] && grep -q 'Managed by leikwan-wg-toolkit' "$XRAY_LEIKWAN_SERVICE"; then
    systemctl disable "${XRAY_LEIKWAN_SERVICE_NAME}.service" >/dev/null 2>&1 || true
    backup_file "$XRAY_LEIKWAN_SERVICE"
    rm -f "$XRAY_LEIKWAN_SERVICE"
    ok "已删除本项目创建的 ${XRAY_LEIKWAN_SERVICE_NAME}.service。"
  fi

  if [[ -f "$XRAY_SYSTEM_SERVICE" ]] && grep -q 'Managed by leikwan-wg-toolkit' "$XRAY_SYSTEM_SERVICE"; then
    if prompt_yes_no "检测到 xray.service 带本项目标记，是否删除该 unit 文件？" "N"; then
      systemctl disable xray.service >/dev/null 2>&1 || true
      backup_file "$XRAY_SYSTEM_SERVICE"
      rm -f "$XRAY_SYSTEM_SERVICE"
      ok "已删除本项目覆盖写入的 xray.service。"
    fi
  fi
  run_cmd systemctl daemon-reload || true
}

uninstall_cloud_entry() {
  need_root
  init_log
  create_snapshot_backup "pre-uninstall-cloud" || true
  remove_wg_iface_if_managed "wg1"
  remove_project_realm_services
}

uninstall_leikwan_relay() {
  need_root
  init_log
  create_snapshot_backup "pre-uninstall-leikwan" || true
  remove_wg_iface_if_managed "wg0"
  remove_xray_config_with_double_confirm "利群中转机"
}

uninstall_landing_server() {
  need_root
  init_log
  create_snapshot_backup "pre-uninstall-landing" || true
  remove_xray_config_with_double_confirm "海外落地机"
}

uninstall_menu() {
  while true; do
    echo
    echo "${BOLD}卸载${RESET}"
    echo "1. 卸载公网入口机组件"
    echo "2. 卸载利群中转机组件"
    echo "3. 卸载海外落地机组件"
    echo "4. 单独删除 IPv6 V6_LOCKDOWN 规则"
    echo "5. 仅删除 IPv4 PBR 规则"
    echo "0. 返回主菜单"
    read -r -p "请选择：" choice
    case "$choice" in
      1) uninstall_cloud_entry || true ;;
      2) uninstall_leikwan_relay || true ;;
      3) uninstall_landing_server || true ;;
      4) remove_ipv6_lockdown || true ;;
      5) pbr_remove_project_rules_only || true ;;
      0) return 0 ;;
      *) echo "无效选择。" ;;
    esac
  done
}

validate_report() {
  local status="$1"
  local message="$2"
  case "$status" in
    ok) echo "${GREEN}[OK]${RESET} ${message}" ;;
    info) echo "[INFO] ${message}" ;;
    warn) echo "${YELLOW}[WARN]${RESET} ${message}" ;;
    fail) echo "${RED}[FAIL]${RESET} ${message}" ;;
  esac
}

validate_url_reachable() {
  local name="$1"
  local url="$2"
  if command -v curl >/dev/null 2>&1; then
    if curl -4 -fsSI --connect-timeout 8 --max-time 12 "$url" >/dev/null 2>&1; then
      validate_report ok "${name} 可达：${url}"
    else
      validate_report warn "${name} 不可达或超时：${url}"
    fi
  else
    validate_report warn "未安装 curl，跳过 ${name} 可达性检查"
  fi
}

validate_command_exists() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    validate_report ok "命令存在：${cmd} ($(command -v "$cmd"))"
    return 0
  fi
  validate_report fail "命令不存在：${cmd}"
  return 1
}

validate_xray_exists() {
  if command -v xray >/dev/null 2>&1; then
    validate_report ok "命令存在：xray ($(command -v xray))"
  elif [[ -x "$XRAY_BIN" ]]; then
    validate_report ok "命令存在：${XRAY_BIN}"
  else
    validate_report fail "命令不存在：xray / ${XRAY_BIN}"
    return 1
  fi
}

validate_service() {
  local service="$1"
  if systemctl list-unit-files --type=service --no-legend "${service}.service" 2>/dev/null | grep -q "^${service}\\.service"; then
    if systemctl is-active --quiet "${service}.service"; then
      validate_report ok "服务运行中：${service}.service"
    else
      validate_report warn "服务存在但未运行：${service}.service"
    fi
    return 0
  fi
  validate_report warn "服务不存在：${service}.service"
  return 1
}

validate_oneshot_service_status() {
  local service="$1"
  local unit="${service}.service"
  local enabled active result
  if ! systemctl list-unit-files --type=service --no-legend "$unit" 2>/dev/null | grep -q "^${unit}"; then
    validate_report warn "服务不存在：${unit}"
    return 1
  fi
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  result="$(systemctl show "$unit" -p Result --value 2>/dev/null || true)"
  if [[ "$enabled" == "enabled" ]]; then
    validate_report ok "服务已 enabled：${unit}"
  else
    validate_report warn "服务未 enabled：${unit} (${enabled:-unknown})"
  fi
  if [[ "$active" == "active" ]]; then
    validate_report ok "服务 active：${unit}"
  elif [[ "$result" == "success" ]]; then
    validate_report ok "oneshot 上次执行成功：${unit}"
  else
    validate_report warn "oneshot 当前未运行或未成功执行：${unit} (active=${active:-unknown}, result=${result:-unknown})"
  fi
}

validate_timer_status() {
  local timer="$1"
  local unit="${timer}.timer"
  local enabled active
  if ! systemctl list-unit-files --type=timer --no-legend "$unit" 2>/dev/null | grep -q "^${unit}"; then
    validate_report warn "timer 不存在：${unit}"
    return 1
  fi
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  if [[ "$enabled" == "enabled" ]]; then
    validate_report ok "timer 已 enabled：${unit}"
  else
    validate_report warn "timer 未 enabled：${unit} (${enabled:-unknown})"
  fi
  if [[ "$active" == "active" ]]; then
    validate_report ok "timer 运行中：${unit}"
  else
    validate_report warn "timer 未运行：${unit} (${active:-unknown})"
  fi
}

validate_port_listen() {
  local port="$1"
  local name="$2"
  if ss -lntup 2>/dev/null | grep -q ":${port}\\b"; then
    validate_report ok "端口监听存在：${name} ${port}"
  else
    validate_report warn "未检测到端口监听：${name} ${port}"
  fi
}

validate_ping() {
  local target="$1"
  local name="$2"
  if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
    validate_report ok "链路 ping 成功：${name} ${target}"
  else
    validate_report warn "链路 ping 失败：${name} ${target}"
  fi
}

parse_landing_from_xray_config() {
  local field="$1"
  [[ -f "$XRAY_CONFIG" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  case "$field" in
    address)
      xray_relay_outbound_field address
      ;;
    port)
      xray_relay_outbound_field port
      ;;
  esac
}

detect_current_role() {
  local roles=()
  if ip -4 addr show wg0 2>/dev/null | grep -q "${LEIKWAN_WG_IP}/"; then
    roles+=("leikwan-relay")
  elif [[ -f "$LEIKWAN_WG_CONF" ]] && grep -q "$LEIKWAN_WG_IP" "$LEIKWAN_WG_CONF"; then
    roles+=("leikwan-relay")
  fi
  if ip -4 addr show wg1 2>/dev/null | grep -q "${CLOUD_WG_IP}/"; then
    roles+=("cloud-entry")
  elif [[ -f "$CLOUD_WG_CONF" ]] && grep -q "$CLOUD_WG_IP" "$CLOUD_WG_CONF"; then
    roles+=("cloud-entry")
  fi
  if [[ -f "$XRAY_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e --argjson port "$LANDING_PORT_DEFAULT" '.inbounds[]? | select(.listen=="0.0.0.0" and .port==$port and .streamSettings.security=="reality")' "$XRAY_CONFIG" >/dev/null 2>&1; then
      roles+=("landing-server")
    fi
  elif [[ -f "${XRAY_MARKER_DIR}/role" ]] && grep -q '^landing' "${XRAY_MARKER_DIR}/role"; then
    roles+=("landing-server")
  fi
  if (( ${#roles[@]} == 0 )); then
    printf '%s' "unknown"
  elif (( ${#roles[@]} == 1 )); then
    printf '%s' "${roles[0]}"
  else
    printf '%s' "multiple:${roles[*]}"
  fi
}

role_has() {
  local role="$1"
  local needle="$2"
  [[ "$role" == "$needle" || "$role" == multiple:*"$needle"* ]]
}

read_landing_param() {
  local key="$1"
  local field="$2"
  local value
  value="$(saved_param "$key" "$RELAY_OUTPUT_FILE" "$LANDING_OUTPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(parse_landing_from_xray_config "$field" 2>/dev/null || true)"
  fi
  printf '%s' "$value"
}

validate_all() {
  init_log
  local role pretty_name landing_address landing_port client_link unmanaged_rules route_output expected_group expected_gw actual_group
  role="$(detect_current_role)"
  echo "${BOLD}${PROJECT_TITLE} Doctor 诊断报告${RESET}"
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    warn "建议使用 root 运行 --doctor / --validate，否则 wg show、ss 进程名等信息可能不完整。"
  fi

  echo
  echo "${BOLD}1. 系统信息${RESET}"
  pretty_name="$(awk -F= '$1=="PRETTY_NAME" {gsub(/"/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null || true)"
  validate_report ok "工具版本：${TOOL_VERSION}"
  validate_report ok "当前角色：${role}"
  validate_report ok "系统：${pretty_name:-unknown}"
  validate_report ok "内核：$(uname -srmo 2>/dev/null || uname -a)"
  validate_report ok "架构：$(uname -m)"
  validate_report ok "时间：$(date '+%F %T %z')"
  notice_outputs_missing "$role"
  if [[ -w "$LOG_FILE" || ! -e "$LOG_FILE" ]]; then
    validate_report ok "脚本日志路径：${LOG_FILE}"
  else
    validate_report warn "脚本日志不可写：${LOG_FILE}"
  fi

  echo
  echo "${BOLD}2. 基础命令${RESET}"
  validate_command_exists ip || true
  validate_command_exists ss || true
  validate_command_exists getent || true
  if role_has "$role" "cloud-entry" || role_has "$role" "leikwan-relay"; then
    validate_command_exists wg || true
  else
    command -v wg >/dev/null 2>&1 && validate_report info "已安装 wg，但当前角色不强制检查 WireGuard"
  fi
  if role_has "$role" "leikwan-relay" || role_has "$role" "landing-server"; then
    validate_xray_exists || true
  else
    validate_report info "当前角色不要求 xray-leikwan"
  fi
  if role_has "$role" "cloud-entry"; then
    validate_command_exists realm || true
  else
    validate_report info "当前角色不要求 realm-leikwan"
  fi

  echo
  echo "${BOLD}3. WireGuard 状态${RESET}"
  if role_has "$role" "cloud-entry"; then
    if ip addr show wg1 >/dev/null 2>&1; then
      validate_report ok "检测到 wg1（公网入口机）"
    else
      validate_report warn "未检测到 wg1"
    fi
    validate_port_listen "$CLOUD_WG_PORT_DEFAULT" "wg1 ${CLOUD_WG_PORT_DEFAULT}/udp"
  elif role_has "$role" "leikwan-relay"; then
    if ip addr show wg0 >/dev/null 2>&1; then
      validate_report ok "检测到 wg0（利群中转机）"
    else
      validate_report warn "未检测到 wg0"
    fi
  else
    validate_report info "未按当前角色强制检查 wg0/wg1"
  fi
  command -v wg >/dev/null 2>&1 && wg show || true

  echo
  echo "${BOLD}4. 角色组件状态${RESET}"
  if role_has "$role" "cloud-entry"; then
    validate_service "$REALM_ENTRY_STEM" || true
    if [[ -f "$REALM_ENTRY_CONF" ]]; then
      validate_report ok "realm 配置存在：${REALM_ENTRY_CONF}"
    else
      validate_report warn "realm 配置不存在：${REALM_ENTRY_CONF}"
    fi
    validate_port_listen "$CLIENT_ENTRY_PORT_DEFAULT" "公网客户端入口 / realm"
  else
    validate_report info "realm-leikwan 属于公网入口机，当前角色缺失不报 WARN"
  fi
  if role_has "$role" "leikwan-relay" || role_has "$role" "landing-server"; then
    validate_service "$XRAY_LEIKWAN_SERVICE_NAME" || true
    if [[ -f "$XRAY_CONFIG" ]]; then
      validate_report ok "Xray leikwan 配置存在：${XRAY_CONFIG}"
    else
      validate_report warn "Xray leikwan 配置不存在：${XRAY_CONFIG}"
    fi
    if role_has "$role" "leikwan-relay"; then
      validate_port_listen "$CLIENT_ENTRY_PORT_DEFAULT" "利群 Xray inbound ${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT}"
    fi
    if role_has "$role" "landing-server"; then
      validate_port_listen "$LANDING_PORT_DEFAULT" "海外落地 Reality ${LANDING_PORT_DEFAULT}/tcp"
    fi
  else
    validate_report info "xray-leikwan 属于利群中转机/海外落地机，当前角色缺失不报 WARN"
  fi

  echo
  echo "${BOLD}5. DNS / IPv4 优先状态${RESET}"
  if getent ahosts raw.githubusercontent.com >/tmp/leikwan-dns-validate.$$ 2>&1; then
    validate_report ok "raw.githubusercontent.com 解析成功"
  else
    validate_report warn "raw.githubusercontent.com 解析失败"
  fi
  rm -f /tmp/leikwan-dns-validate.$$
  if [[ -f /etc/gai.conf ]] && grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' /etc/gai.conf; then
    validate_report ok "IPv4 优先规则已存在：/etc/gai.conf"
  else
    validate_report warn "未检测到 IPv4 优先规则：precedence ::ffff:0:0/96  100"
  fi

  echo
  echo "${BOLD}6. IPv6 V6_LOCKDOWN 状态${RESET}"
  if command -v ip6tables >/dev/null 2>&1 && ip6tables -S V6_LOCKDOWN >/dev/null 2>&1; then
    validate_report ok "检测到 V6_LOCKDOWN 链"
    if ip6tables -C INPUT -j V6_LOCKDOWN >/dev/null 2>&1; then
      validate_report ok "INPUT 已接入 V6_LOCKDOWN"
    else
      validate_report warn "INPUT 未接入 V6_LOCKDOWN"
    fi
    if [[ -f /etc/iptables/rules.v6 ]]; then
      validate_report ok "IPv6 规则已持久化：/etc/iptables/rules.v6"
    else
      validate_report warn "未找到 /etc/iptables/rules.v6"
    fi
  else
    validate_report info "未检测到 V6_LOCKDOWN 链；如果未启用 IPv6 入站收口，可忽略"
  fi

  echo
  echo "${BOLD}7. IPv4 PBR / 多出口策略路由${RESET}"
  if role_has "$role" "leikwan-relay" || [[ -s "$PBR_STATIC_CONF" || -s "$PBR_DOMAIN_CONF" ]]; then
    if [[ -f "$PBR_STATIC_CONF" ]]; then
      validate_report ok "静态规则配置存在：${PBR_STATIC_CONF}"
    else
      validate_report info "静态规则配置暂不存在"
    fi
    if [[ -f "$PBR_DOMAIN_CONF" ]]; then
      validate_report ok "域名规则配置存在：${PBR_DOMAIN_CONF}"
    else
      validate_report info "域名规则配置暂不存在"
    fi
    if [[ -f "$PBR_DOMAIN_STATE" ]]; then
      validate_report ok "域名状态文件存在：${PBR_DOMAIN_STATE}"
    else
      validate_report info "域名状态文件暂不存在"
    fi
    pbr_detect_available_routes "quiet" "no" || true
    if (( ${#PBR_FOUND_NAMES[@]} > 0 )); then
      validate_report ok "检测到可用线路组：${PBR_FOUND_NAMES[*]}"
    else
      validate_report warn "未检测到利群常见 IPv4 线路组"
    fi
    unmanaged_rules="$(pbr_list_unmanaged_rules | sed '/^$/d' || true)"
    if [[ -n "$unmanaged_rules" ]]; then
      validate_report warn "检测到未托管 PBR 规则"
      printf '%s\n' "$unmanaged_rules"
    else
      validate_report ok "未检测到未托管的 priority ${PBR_STATIC_PRIORITY}/${PBR_DOMAIN_PRIORITY} 规则"
    fi
    validate_oneshot_service_status "$PBR_SERVICE_NAME" || true
    if [[ -s "$PBR_DOMAIN_CONF" ]]; then
      validate_oneshot_service_status "$PBR_DDNS_SERVICE_NAME" || true
      validate_timer_status "$PBR_DDNS_SERVICE_NAME" || true
    else
      validate_report info "未启用域名 PBR，跳过 ${PBR_DDNS_SERVICE_NAME}.timer 检查"
    fi
    landing_address="$(read_landing_param LANDING_ADDRESS address)"
    if is_ipv4 "$landing_address"; then
      if route_output="$(ip route get "$landing_address" 2>&1)"; then
        printf '%s\n' "$route_output"
        actual_group="$(pbr_group_from_route_output "$route_output" 2>/dev/null || true)"
        if [[ -n "$actual_group" ]]; then
          validate_report ok "LANDING_ADDRESS 当前走 T_${actual_group}"
        else
          validate_report info "未能从 ip route get 输出识别 T_ 出口"
        fi
        expected_group="$(pbr_static_managed_group "${landing_address}/32" 2>/dev/null || true)"
        if [[ -n "$expected_group" ]]; then
          expected_gw="$(pbr_group_gateway "$expected_group" 2>/dev/null || true)"
          if [[ -n "$expected_gw" && "$route_output" == *" via ${expected_gw} "* ]]; then
            validate_report ok "LANDING_ADDRESS 与 static-routes.conf 一致：T_${expected_group}"
          else
            validate_report fail "LANDING_ADDRESS 实际出口与 static-routes.conf 不一致，期望 T_${expected_group}"
          fi
        fi
      else
        validate_report warn "ip route get ${landing_address} 执行失败：${route_output}"
      fi
    else
      validate_report info "未读取到 LANDING_ADDRESS，跳过落地机 PBR 出口检查"
    fi
  else
    validate_report info "PBR 只建议在利群中转机启用，当前角色跳过"
  fi

  echo
  echo "${BOLD}8. 链路连通性${RESET}"
  if role_has "$role" "cloud-entry"; then
    validate_ping "$LEIKWAN_WG_IP" "公网入口机 -> 利群中转机"
    if command -v nc >/dev/null 2>&1 && nc -vz -w 3 "$LEIKWAN_WG_IP" "$CLIENT_ENTRY_PORT_DEFAULT" >/tmp/leikwan-nc-validate.$$ 2>&1; then
      validate_report ok "公网入口机到利群入口 TCP 可达：${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT}"
    else
      validate_report warn "公网入口机到利群入口 TCP 不可达或未安装 nc"
    fi
    rm -f /tmp/leikwan-nc-validate.$$
  elif role_has "$role" "leikwan-relay"; then
    validate_ping "$CLOUD_WG_IP" "利群中转机 -> 公网入口机"
    landing_address="$(read_landing_param LANDING_ADDRESS address)"
    landing_port="$(read_landing_param LANDING_PORT port)"
    if [[ -n "$landing_address" && -n "$landing_port" ]]; then
      ip route get "$landing_address" || validate_report warn "ip route get ${landing_address} 执行失败"
      if command -v nc >/dev/null 2>&1 && nc -vz -w 3 "$landing_address" "$landing_port" >/tmp/leikwan-nc-validate.$$ 2>&1; then
        validate_report ok "利群中转机到落地机 TCP 可达：${landing_address}:${landing_port}"
      else
        validate_report warn "利群中转机到落地机 TCP 不可达或未安装 nc：${landing_address}:${landing_port}"
      fi
      rm -f /tmp/leikwan-nc-validate.$$
    else
      validate_report warn "未能解析 LANDING_ADDRESS/LANDING_PORT"
    fi
    client_link="$(env_file_get "$CLIENT_LINK_FILE" CLIENT_LINK 2>/dev/null || env_file_get "$RELAY_OUTPUT_FILE" CLIENT_LINK 2>/dev/null || true)"
    if [[ -n "$client_link" ]]; then
      validate_report ok "CLIENT_LINK 已生成：${CLIENT_LINK_FILE}"
    else
      validate_report warn "CLIENT_LINK 不存在，可运行：bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption 'mlkem...'"
    fi
  elif role_has "$role" "landing-server"; then
    validate_report info "落地机链路入口由外部客户端/利群访问，当前只检查 Xray 服务与端口"
  else
    validate_report info "未知角色，跳过角色链路检查"
  fi

  echo
  echo "${BOLD}9. Xray 配置测试${RESET}"
  if role_has "$role" "leikwan-relay" || role_has "$role" "landing-server"; then
    if [[ -x "$XRAY_BIN" && -f "$XRAY_CONFIG" ]]; then
      if "$XRAY_BIN" run -test -config "$XRAY_CONFIG" >/tmp/leikwan-xray-test.$$ 2>&1; then
        validate_report ok "Xray leikwan 配置测试通过"
      else
        validate_report fail "Xray leikwan 配置测试失败：$(tr '\n' ' ' </tmp/leikwan-xray-test.$$)"
        show_xray_config_context "$XRAY_CONFIG"
      fi
      rm -f /tmp/leikwan-xray-test.$$
    else
      validate_report warn "跳过 Xray 配置测试，缺少 ${XRAY_BIN} 或 ${XRAY_CONFIG}"
    fi
  else
    validate_report info "当前角色不需要 Xray 配置测试"
  fi

  echo
  echo "${BOLD}10. GitHub/raw/ghfast 可达性${RESET}"
  validate_url_reachable "github.com" "https://github.com/"
  validate_url_reachable "raw.githubusercontent.com" "https://raw.githubusercontent.com/github/gitignore/main/README.md"
  validate_url_reachable "ghfast" "https://ghfast.top/"
}

validate_doctor_concise() {
  init_log
  local role wg_iface handshake_ts handshake_age landing_address pbr_group client_link github_ok=0 raw_ok=0 ghfast_ok=0
  role="$(detect_current_role)"
  validate_report ok "角色：${role}"
  notice_outputs_missing "$role"

  if role_has "$role" "cloud-entry"; then
    wg_iface="wg1"
  elif role_has "$role" "leikwan-relay"; then
    wg_iface="wg0"
  else
    wg_iface=""
  fi

  if [[ -n "$wg_iface" ]] && command -v wg >/dev/null 2>&1; then
    handshake_ts="$(wg show "$wg_iface" latest-handshakes 2>/dev/null | awk '$2 > 0 {print $2; exit}' || true)"
    if [[ -n "$handshake_ts" ]]; then
      handshake_age=$(( $(date +%s) - handshake_ts ))
      validate_report ok "WG：handshake ${handshake_age} 秒前"
    else
      validate_report warn "WG：未检测到 handshake"
    fi
  elif [[ -n "$wg_iface" ]]; then
    validate_report warn "WG：未安装 wg 或接口不可读"
  else
    validate_report info "WG：当前角色不需要"
  fi

  if role_has "$role" "cloud-entry"; then
    if systemctl is-active --quiet "${REALM_ENTRY_STEM}.service"; then
      validate_report ok "realm：${CLIENT_ENTRY_PORT_DEFAULT}"
    else
      validate_report warn "realm：未运行"
    fi
  elif role_has "$role" "leikwan-relay"; then
    if systemctl is-active --quiet "${XRAY_LEIKWAN_SERVICE_NAME}.service"; then
      validate_report ok "Xray：${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT}"
    else
      validate_report warn "Xray：未运行"
    fi
  elif role_has "$role" "landing-server"; then
    if systemctl is-active --quiet "${XRAY_LEIKWAN_SERVICE_NAME}.service"; then
      validate_report ok "Xray：0.0.0.0:${LANDING_PORT_DEFAULT}"
    else
      validate_report warn "Xray：未运行"
    fi
  fi

  if role_has "$role" "leikwan-relay"; then
    landing_address="$(read_landing_param LANDING_ADDRESS address)"
    if is_ipv4 "$landing_address"; then
      pbr_group="$(pbr_static_managed_group "${landing_address}/32" 2>/dev/null || true)"
      if [[ -n "$pbr_group" ]]; then
        validate_report ok "PBR：${landing_address} -> T_${pbr_group}"
      else
        validate_report info "PBR：LANDING_ADDRESS 未指定出口"
      fi
    else
      validate_report info "PBR：未读取到 LANDING_ADDRESS"
    fi
    client_link="$(env_file_get "$CLIENT_LINK_FILE" CLIENT_LINK 2>/dev/null || env_file_get "$RELAY_OUTPUT_FILE" CLIENT_LINK 2>/dev/null || true)"
    if [[ -n "$client_link" ]]; then
      validate_report ok "客户端链接：存在"
    elif [[ -f "$XRAY_CONFIG" ]]; then
      validate_report warn "客户端链接：不存在，可运行 --rebuild-outputs 修复"
    else
      validate_report info "客户端链接：未生成"
    fi
  fi

  command -v curl >/dev/null 2>&1 && curl -4 -fsSI --connect-timeout 5 --max-time 8 https://github.com/ >/dev/null 2>&1 && github_ok=1
  command -v curl >/dev/null 2>&1 && curl -4 -fsSI --connect-timeout 5 --max-time 8 https://raw.githubusercontent.com/github/gitignore/main/README.md >/dev/null 2>&1 && raw_ok=1
  command -v curl >/dev/null 2>&1 && curl -4 -fsSI --connect-timeout 5 --max-time 8 https://ghfast.top/ >/dev/null 2>&1 && ghfast_ok=1
  if (( github_ok == 1 )); then
    validate_report ok "GitHub：github.com 可达"
  elif (( raw_ok == 1 || ghfast_ok == 1 )); then
    validate_report warn "GitHub：github.com 不可达，raw/ghfast 可达"
  else
    validate_report warn "GitHub：github/raw/ghfast 均不可达或 curl 不存在"
  fi
  echo "详细报告：bash wg-toolkit.sh --doctor --verbose"
}

recommended_wizard_menu() {
  while true; do
    local role
    role="$(detect_current_role)"
    echo
    echo "${BOLD}极速部署向导${RESET}"
    echo "当前角色：${role}"
    local choice
    if role_has "$role" "landing-server"; then
      echo "1. 部署 / 更新 Reality 落地"
      echo "2. 查看 LANDING 参数"
      echo "3. doctor"
      echo "0. 返回"
      read -r -p "请选择：" choice
      case "$choice" in
        1) deploy_landing_server || true ;;
        2) show_copy_params || true ;;
        3) validate_doctor_concise || true ;;
        0) return 0 ;;
        *) echo "无效选择。" ;;
      esac
    elif role_has "$role" "cloud-entry"; then
      echo "1. 导入 / 输入 LEIKWAN_PUBLIC_KEY"
      echo "2. 部署 / 更新 WireGuard + realm"
      echo "3. 查看 CLOUD 参数"
      echo "4. doctor"
      echo "0. 返回"
      read -r -p "请选择：" choice
      case "$choice" in
        1) cloud_import_leikwan_public_key || true ;;
        2) deploy_cloud_entry || true ;;
        3) show_copy_params || true ;;
        4) validate_doctor_concise || true ;;
        0) return 0 ;;
        *) echo "无效选择。" ;;
      esac
    elif role_has "$role" "leikwan-relay"; then
      echo "1. 查看 / 生成 LEIKWAN_PUBLIC_KEY"
      echo "2. 导入 CLOUD 参数"
      echo "3. 导入 LANDING 参数"
      echo "4. 完成链式代理部署"
      echo "5. 指定 Reality 落地机出口"
      echo "6. 查看客户端链接"
      echo "7. doctor"
      echo "0. 返回"
      read -r -p "请选择：" choice
      case "$choice" in
        1) show_wg_identity_for_iface "wg0" || true ;;
        2) import_params_file || true ;;
        3) import_params_file || true ;;
        4) deploy_leikwan_relay || true ;;
        5) pbr_route_landing || true ;;
        6) view_client_link || true ;;
        7) validate_doctor_concise || true ;;
        0) return 0 ;;
        *) echo "无效选择。" ;;
      esac
    else
      echo "1. 我这是海外落地机"
      echo "2. 我这是公网入口机"
      echo "3. 我这是利群中转机"
      echo "0. 返回"
      read -r -p "请选择：" choice
      case "$choice" in
        1) deploy_landing_server || true ;;
        2) cloud_import_leikwan_public_key || true; deploy_cloud_entry || true ;;
        3) show_wg_identity_for_iface "wg0" || true ;;
        0) return 0 ;;
        *) echo "无效选择。" ;;
      esac
    fi
  done
}

deployment_overview() {
  init_log
  local role wg_pub="" link="" landing_address landing_port pbr_group peer_line
  role="$(detect_current_role)"
  echo
  echo "${BOLD}部署总览 / 下一步提示${RESET}"
  echo "当前角色：${role}"

  if role_has "$role" "leikwan-relay"; then
    wg_pub="$(read_key_file "$LEIKWAN_WG_PUBLIC_FILE" 2>/dev/null || true)"
    echo "WG：wg0 ${LEIKWAN_WG_ADDR}"
    [[ -n "$wg_pub" ]] && echo "本机 WG PublicKey：${wg_pub}"
    peer_line="$(wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}' | head -n 1 || true)"
    [[ -n "$peer_line" && "$peer_line" != "0" ]] && echo "Handshake：$(( $(date +%s) - peer_line )) 秒前" || echo "Handshake：未检测到"
    systemctl is-active --quiet "${XRAY_LEIKWAN_SERVICE_NAME}.service" && echo "Xray：active" || echo "Xray：inactive/unknown"
    echo "Inbound：${LEIKWAN_WG_IP}:${CLIENT_ENTRY_PORT_DEFAULT}"
    landing_address="$(read_landing_param LANDING_ADDRESS address)"
    landing_port="$(read_landing_param LANDING_PORT port)"
    [[ -n "$landing_address" && -n "$landing_port" ]] && echo "Reality：${landing_address}:${landing_port}"
    if is_ipv4 "$landing_address"; then
      pbr_group="$(pbr_static_managed_group "${landing_address}/32" 2>/dev/null || true)"
      [[ -n "$pbr_group" ]] && echo "PBR：${landing_address} -> T_${pbr_group}"
    fi
    link="$(env_file_get "$CLIENT_LINK_FILE" CLIENT_LINK 2>/dev/null || env_file_get "$RELAY_OUTPUT_FILE" CLIENT_LINK 2>/dev/null || true)"
    [[ -n "$link" ]] && echo "CLIENT_LINK：${link}" || echo "下一步：完成利群中转机链式部署以生成 CLIENT_LINK"
    echo
    echo "验收命令：wg show; ss -lntup | grep ${CLIENT_ENTRY_PORT_DEFAULT}; bash wg-toolkit.sh --doctor"
  elif role_has "$role" "cloud-entry"; then
    wg_pub="$(read_key_file "$CLOUD_WG_PUBLIC_FILE" 2>/dev/null || true)"
    echo "WG：wg1 ${CLOUD_WG_ADDR}"
    [[ -n "$wg_pub" ]] && echo "本机 WG PublicKey：${wg_pub}"
    systemctl is-active --quiet "${REALM_ENTRY_STEM}.service" && echo "realm：active" || echo "realm：inactive/unknown"
    echo "公网入口：0.0.0.0:${CLIENT_ENTRY_PORT_DEFAULT}"
    echo "需要复制给利群：${CLOUD_OUTPUT_FILE}"
    echo
    echo "验收命令：wg show; ping ${LEIKWAN_WG_IP}; nc -vz ${LEIKWAN_WG_IP} ${CLIENT_ENTRY_PORT_DEFAULT}"
  elif role_has "$role" "landing-server"; then
    systemctl is-active --quiet "${XRAY_LEIKWAN_SERVICE_NAME}.service" && echo "Xray：active" || echo "Xray：inactive/unknown"
    echo "Reality：0.0.0.0:${LANDING_PORT_DEFAULT}"
    echo "需要复制给利群：${LANDING_OUTPUT_FILE}"
    echo
    echo "验收命令：systemctl status ${XRAY_LEIKWAN_SERVICE_NAME}; ss -lntup | grep ${LANDING_PORT_DEFAULT}; ${XRAY_BIN} run -test -config ${XRAY_CONFIG}"
  else
    echo "下一步：建议从\"推荐部署向导\"开始。"
  fi
}

advanced_menu() {
  while true; do
    echo
    echo "${BOLD}高级功能${RESET}"
    echo "1. 查看 / 生成本机 WireGuard 身份"
    echo "2. 部署总览 / 下一步提示"
    echo "3. 公网入口机部署"
    echo "4. 利群中转机部署"
    echo "5. 海外落地机部署"
    echo "6. 导入参数文件"
    echo "7. IPv4 多出口策略路由"
    echo "8. 链路测试"
    echo "9. DNS / IPv4 优先修复"
    echo "10. IPv6 入站安全收口"
    echo "11. 查看状态"
    echo "12. 备份 / 恢复"
    echo "13. 卸载"
    echo "0. 返回"
    local choice
    read -r -p "请选择：" choice
    case "$choice" in
      1) show_wg_identity_menu || true ;;
      2) deployment_overview || true ;;
      3) deploy_cloud_entry || true ;;
      4) deploy_leikwan_relay || true ;;
      5) deploy_landing_server || true ;;
      6) import_params_file || true ;;
      7) pbr_menu || true ;;
      8) link_test_menu || true ;;
      9) fix_dns_ipv4_first || true ;;
      10) ipv6_lockdown || true ;;
      11) show_status || true ;;
      12) backup_restore_menu || true ;;
      13) uninstall_menu || true ;;
      0) return 0 ;;
      *) echo "无效选择。" ;;
    esac
  done
}

main_menu() {
  need_root_unless_dry_run
  init_log
  while true; do
    echo
    echo "${BOLD}${PROJECT_TITLE} ${TOOL_VERSION}${RESET}"
    echo "1. 极速部署向导"
    echo "2. 查看复制参数 / 客户端链接"
    echo "3. 一键诊断 doctor"
    echo "4. 高级功能"
    echo "0. 退出"
    read -r -p "请选择：" choice
    case "$choice" in
      1) recommended_wizard_menu || true ;;
      2) show_copy_params || true ;;
      3) validate_doctor_concise || true ;;
      4) advanced_menu || true ;;
      0) echo "已退出。"; exit 0 ;;
      *) echo "无效选择，请重新输入。" ;;
    esac
  done
}

main() {
  local role_filter
  while [[ "${1:-}" == "--dry-run" ]]; do
    DRY_RUN=1
    shift
  done

  case "${1:-}" in
    --help|-h)
      print_help
      ;;
    --version|-v)
      echo "${PROJECT_NAME} ${TOOL_VERSION}"
      ;;
    --validate)
      validate_all
      ;;
    --doctor)
      if [[ "${2:-}" == "--verbose" ]]; then
        validate_all
      else
        validate_doctor_concise
      fi
      ;;
    --show-wg-identity)
      role_filter="auto"
      if [[ "${2:-}" == "--role" ]]; then
        role_filter="${3:-auto}"
      fi
      show_wg_identity_cli "$role_filter"
      ;;
    --rebuild-outputs)
      shift
      parse_rebuild_cli_options "$@"
      rebuild_outputs
      ;;
    --pbr-apply)
      need_root
      init_log
      pbr_apply_saved_rules
      ;;
    --pbr-refresh-domains)
      need_root
      init_log
      pbr_refresh_domains
      ;;
    --pbr-show)
      pbr_show
      ;;
    --pbr-audit)
      pbr_audit_existing_rules
      ;;
    --pbr-import-existing)
      init_log
      pbr_import_existing_rules
      ;;
    --uninstall)
      need_root
      init_log
      uninstall_menu
      ;;
    "")
      main_menu
      ;;
    *)
      fail "未知参数：$1"
      print_help
      exit 1
      ;;
  esac
}

main "$@"
