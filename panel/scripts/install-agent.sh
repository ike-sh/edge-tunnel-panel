#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-ike-sh/edge-tunnel-panel}"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/edge-tunnel/agent}"
STATE_DIR="${STATE_DIR:-/var/lib/edge-tunnel/agent}"
LOG_DIR="${LOG_DIR:-/var/log/edge-tunnel}"
EDGE_GITHUB_MIRRORS="${EDGE_GITHUB_MIRRORS:-}"
CONTROLLER_URL="${EDGE_CONTROLLER_URL:-}"
CONTROLLER_TOKEN="${EDGE_CONTROLLER_TOKEN:-}"
NODE_ID="${EDGE_NODE_ID:-}"
NODE_NAME="${EDGE_NODE_NAME:-$(hostname 2>/dev/null || printf 'edge-node')}"
NODE_ROLE="${EDGE_NODE_ROLE:-backend}"
MACHINE_ID="${EDGE_MACHINE_ID:-}"
ENABLE_TASKS="${EDGE_ENABLE_TASKS:-false}"
ENABLE_WRITE_ACTIONS="${EDGE_ENABLE_WRITE_ACTIONS:-false}"
INSTALL_IXTF="${EDGE_INSTALL_IXTF:-auto}"
IXTF_REPO="${IXTF_REPO:-ike-sh/ix-transit-fabric}"
IXTF_VERSION="${IXTF_VERSION:-v1.2.0}"
IXTF_INSTALL_DIR="${IXTF_INSTALL_DIR:-/opt/ix-transit-fabric}"
REPORT_INTERVAL="${EDGE_REPORT_INTERVAL:-30s}"
TASK_POLL_INTERVAL="${EDGE_TASK_POLL_INTERVAL:-10s}"
SOURCE_BUILD=false
NO_START=false
UNINSTALL=false
PURGE=false
REMOVE_EASYTIER_BINARIES=false

usage() {
  cat <<'USAGE'
Install Edge Tunnel Panel Agent.

Options:
  --version VERSION             Release version, default: latest
  --controller-url URL          Controller URL, required
  --token TOKEN                 Controller token, required
  --node-id ID                  Optional node id
  --node-name NAME              Node name
  --machine-id ID               IX machine id for controller binding
  --role ROLE                   entry, relay, exit, backend
  --enable-tasks                Enable task polling
  --enable-write-actions        Enable write actions
  --install-ixtf                Install ix-transit-fabric CLI (default: auto when --enable-write-actions)
  --skip-ixtf                   Skip ix-transit-fabric installation
  --ixtf-version VERSION        ix-transit-fabric version tag, default: v1.2.0
  --config-dir DIR              Agent config directory
  --state-dir DIR               Agent state directory
  --install-dir DIR             Binary install directory
  --source-build                Build from current source checkout
  --no-start                    Do not start service after install
  --uninstall                   卸载 Agent 服务和二进制，保留配置、状态和日志
  --purge                       彻底删除 Agent 服务、二进制、配置、状态和日志
  --remove-easytier-binaries    配合 --purge 删除 easytier-core 和 easytier-cli
  -h, --help                    Show help
USAGE
}

log() { printf '[edge-tunnel-agent] %s\n' "$*"; }
fail() { printf '[edge-tunnel-agent] ERROR: %s\n' "$*" >&2; exit 1; }
find_file_cmd() {
  if command -v file >/dev/null 2>&1; then
    printf 'file\n'
    return 0
  fi
  for candidate in "/mnt/host/d/Program Files/Git/usr/bin/file.exe" "/mnt/host/c/Program Files/Git/usr/bin/file.exe" "/d/Program Files/Git/usr/bin/file.exe" "/c/Program Files/Git/usr/bin/file.exe"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}
mask() {
  local value="$1"
  if [ "${#value}" -le 8 ]; then printf '[REDACTED]'; else printf '%s...[REDACTED]' "${value:0:4}"; fi
}

safe_id() {
  printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'
}

generate_node_id() {
  local host mid random_part raw
  host="$(hostname 2>/dev/null || printf 'edge-node')"
  host="$(safe_id "$host")"
  if [ -r /etc/machine-id ]; then
    mid="$(cut -c1-12 /etc/machine-id | tr -cd 'A-Za-z0-9')"
  else
    mid=""
  fi
  if [ -z "$mid" ]; then
    random_part="$(date +%s%N 2>/dev/null || date +%s)"
    mid="$(safe_id "$random_part")"
  fi
  raw="node-${host:-edge-node}-${mid}"
  safe_id "$raw"
}

ensure_node_id() {
  if [ -n "$NODE_ID" ]; then
    NODE_ID="$(safe_id "$NODE_ID")"
    return
  fi
  if [ -f "$CONFIG_DIR/agent.env" ]; then
    NODE_ID="$(sed -n 's/^EDGE_NODE_ID=//p' "$CONFIG_DIR/agent.env" | head -n 1 | tr -d '\"' || true)"
    NODE_ID="$(safe_id "$NODE_ID")"
  fi
  if [ -z "$NODE_ID" ]; then
    NODE_ID="$(generate_node_id)"
  fi
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "please run as root"
  fi
}

load_existing_env() {
  if [ -f "$CONFIG_DIR/agent.env" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_DIR/agent.env" || true
    CONTROLLER_URL="${CONTROLLER_URL:-${EDGE_CONTROLLER_URL:-}}"
    CONTROLLER_TOKEN="${CONTROLLER_TOKEN:-${EDGE_CONTROLLER_TOKEN:-}}"
    NODE_ID="${NODE_ID:-${EDGE_NODE_ID:-}}"
  fi
}

notify_controller_offline() {
  load_existing_env
  if [ -z "${CONTROLLER_URL:-}" ] || [ -z "${CONTROLLER_TOKEN:-}" ] || [ -z "${NODE_ID:-}" ]; then
    log "未找到完整 Controller/节点信息，跳过下线通知"
    return 0
  fi
  local url payload
  url="${CONTROLLER_URL%/}/api/v1/agent/unregister"
  payload="{\"node_id\":\"${NODE_ID}\",\"reason\":\"agent purge\"}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -m 8 -H "Authorization: Bearer ${CONTROLLER_TOKEN}" -H "Content-Type: application/json" -d "$payload" "$url" >/dev/null 2>&1 || {
      log "无法通知 Controller 节点下线，请稍后由心跳超时自动变为离线。"
      return 0
    }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=8 --header="Authorization: Bearer ${CONTROLLER_TOKEN}" --header="Content-Type: application/json" --post-data="$payload" "$url" >/dev/null 2>&1 || {
      log "无法通知 Controller 节点下线，请稍后由心跳超时自动变为离线。"
      return 0
    }
  else
    log "curl/wget 不可用，无法通知 Controller 节点下线。"
    return 0
  fi
  log "已通知 Controller 节点下线：${NODE_ID}"
}

uninstall_agent() {
  notify_controller_offline
  systemctl stop edge-tunnel-agent.service >/dev/null 2>&1 || true
  log "已停止 Agent 服务"
  systemctl disable edge-tunnel-agent.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/edge-tunnel-agent.service
  rm -f "$INSTALL_DIR/edge-tunnel-agent"
  log "已删除 Agent 二进制"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed edge-tunnel-agent.service >/dev/null 2>&1 || true
  if [ "$PURGE" = true ]; then
    systemctl stop edge-tunnel-easytier.service >/dev/null 2>&1 || true
    systemctl disable edge-tunnel-easytier.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/edge-tunnel-easytier.service
    rm -rf "$CONFIG_DIR/systemd"
    rm -f "$CONFIG_DIR/easytier.toml" "$CONFIG_DIR/network-profile.json"
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed edge-tunnel-easytier.service >/dev/null 2>&1 || true
    log "已停止 EasyTier 服务"
    log "已删除 EasyTier systemd service"
    log "已删除 EasyTier 配置"
    if [ "$REMOVE_EASYTIER_BINARIES" = true ]; then
      rm -f /usr/local/bin/easytier-core /usr/local/bin/easytier-cli
      log "已删除 easytier-core/easytier-cli"
    else
      log "如需删除 easytier-core/easytier-cli，请使用 --remove-easytier-binaries"
    fi
    rm -rf "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"
    rmdir /etc/edge-tunnel >/dev/null 2>&1 || true
    rmdir /var/lib/edge-tunnel >/dev/null 2>&1 || true
    log "已彻底删除配置、状态和日志"
  else
    log "已保留配置和状态"
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *) fail "unsupported architecture: $(uname -m)" ;;
  esac
}

mirror_url() {
  local mirror="$1" url="$2"
  mirror="${mirror%/}"
  if [ -z "$mirror" ]; then
    printf '%s' "$url"
  else
    printf '%s/%s' "$mirror" "$url"
  fi
}

download_file_once() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 10 --max-time 180 "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget --timeout=30 --tries=2 -O "$dest" "$url"
  else
    fail "curl or wget is required"
  fi
}

download_file() {
  local url="$1" dest="$2" candidate mirror
  log "downloading $url"
  if download_file_once "$url" "$dest"; then
    return 0
  fi
  IFS=',' read -r -a mirrors <<<"$EDGE_GITHUB_MIRRORS"
  for mirror in "${mirrors[@]:-}"; do
    mirror="$(printf '%s' "$mirror" | xargs)"
    [ -n "$mirror" ] || continue
    candidate="$(mirror_url "$mirror" "$url")"
    log "retry with mirror $candidate"
    if download_file_once "$candidate" "$dest"; then
      return 0
    fi
  done
  return 1
}

resolve_version() {
  if [ "$VERSION" != "latest" ]; then
    printf '%s' "$VERSION"
    return
  fi
  local api="https://api.github.com/repos/${REPO}/releases/latest"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$api" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$api" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
  fi
}

install_from_release() {
  local arch version asset url tmp
  arch="$(detect_arch)"
  version="$(resolve_version)"
  [ -n "$version" ] || fail "cannot resolve latest release; use --version or --source-build"
  asset="edge-tunnel-panel-${version}-linux-${arch}.tar.gz"
  url="https://github.com/${REPO}/releases/download/${version}/${asset}"
  tmp="$(mktemp -d)"
  if ! download_file "$url" "$tmp/$asset"; then
    fail "release asset not available; use --source-build or run panel/scripts/build-release.sh first"
  fi
  tar -xzf "$tmp/$asset" -C "$tmp"
  if [ ! -f "$tmp/edge-tunnel-agent" ]; then
    find "$tmp" -maxdepth 3 -type f | sort >&2
    fail "edge-tunnel-agent not found in release archive"
  fi
  if file_cmd="$(find_file_cmd)"; then
    "$file_cmd" "$tmp/edge-tunnel-agent" || true
  fi
  if ! "$tmp/edge-tunnel-agent" --version >/dev/null 2>&1; then
    fail "downloaded edge-tunnel-agent cannot run on this machine; check release asset architecture"
  fi
  install -m 0755 "$tmp/edge-tunnel-agent" "$INSTALL_DIR/edge-tunnel-agent"
  rm -rf "$tmp"
}

install_from_source() {
  command -v go >/dev/null 2>&1 || fail "go is required for --source-build"
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  (cd "$root/panel/agent" && go build -o "$INSTALL_DIR/edge-tunnel-agent" ./cmd/edge-tunnel-agent)
}

install_ixtf() {
  local url tmp
  install -d -m 0755 "$IXTF_INSTALL_DIR"
  url="https://raw.githubusercontent.com/${IXTF_REPO}/${IXTF_VERSION}/install.sh"
  tmp="$(mktemp)"
  log "installing ix-transit-fabric ${IXTF_VERSION} to ${IXTF_INSTALL_DIR}"
  if ! download_file "$url" "$tmp"; then
    fail "cannot download ix-transit-fabric install.sh"
  fi
  install -m 0755 "$tmp" "$IXTF_INSTALL_DIR/install.sh"
  rm -f "$tmp"
  if ! bash "$IXTF_INSTALL_DIR/install.sh" install-ix-cli; then
    log "install-ix-cli failed; ixtf may still work via install.sh directly"
  fi
  log "ix-transit-fabric installed at ${IXTF_INSTALL_DIR}/install.sh"
}

should_install_ixtf() {
  case "$INSTALL_IXTF" in
    true|1|yes) return 0 ;;
    false|0|no) return 1 ;;
    auto)
      [ "$ENABLE_WRITE_ACTIONS" = true ] && return 0
      return 1
      ;;
    *) return 1 ;;
  esac
}

write_env() {
  ensure_node_id
  install -d -m 0755 "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"
  cat >"$CONFIG_DIR/agent.env" <<EOF
EDGE_CONTROLLER_URL=${CONTROLLER_URL}
EDGE_CONTROLLER_TOKEN=${CONTROLLER_TOKEN}
EDGE_NODE_ID=${NODE_ID}
EDGE_NODE_NAME=${NODE_NAME}
EDGE_NODE_ROLE=${NODE_ROLE}
EDGE_ENABLE_TASKS=${ENABLE_TASKS}
EDGE_ENABLE_WRITE_ACTIONS=${ENABLE_WRITE_ACTIONS}
EDGE_AGENT_CONFIG_DIR=${CONFIG_DIR}
EDGE_AGENT_STATE_DIR=${STATE_DIR}
EDGE_REPORT_INTERVAL=${REPORT_INTERVAL}
EDGE_TASK_POLL_INTERVAL=${TASK_POLL_INTERVAL}
IXTF_INSTALL_PATH=${IXTF_INSTALL_DIR}/install.sh
EOF
  if [ -n "$MACHINE_ID" ]; then
    printf 'EDGE_MACHINE_ID=%s\n' "$MACHINE_ID" >>"$CONFIG_DIR/agent.env"
  fi
  chmod 0600 "$CONFIG_DIR/agent.env"
}

write_service() {
  cat >/etc/systemd/system/edge-tunnel-agent.service <<EOF
[Unit]
Description=Edge Tunnel Panel Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=${CONFIG_DIR}/agent.env
WorkingDirectory=${STATE_DIR}
ExecStart=${INSTALL_DIR}/edge-tunnel-agent
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

run_once_registration_check() {
  local args=(
    --controller-url "$CONTROLLER_URL"
    --token "$CONTROLLER_TOKEN"
    --node-name "$NODE_NAME"
    --role "$NODE_ROLE"
    --config-dir "$CONFIG_DIR"
    --state-dir "$STATE_DIR"
    --once
  )
  args+=(--node-id "$NODE_ID")
  if [ -n "$MACHINE_ID" ]; then
    args+=(--machine-id "$MACHINE_ID")
  fi
  if [ "$ENABLE_TASKS" = true ]; then
    args+=(--enable-tasks)
  fi
  if [ "$ENABLE_WRITE_ACTIONS" = true ]; then
    args+=(--enable-write-actions)
  fi
  log "正在尝试一次性注册"
  if ! "$INSTALL_DIR/edge-tunnel-agent" "${args[@]}"; then
    log "一次性注册失败"
    log "Controller 地址：${CONTROLLER_URL}"
    log "节点 ID：${NODE_ID}"
    log "节点名称：${NODE_NAME}"
    log "节点角色：${NODE_ROLE}"
    log "请检查 Controller 地址、Token、防火墙和服务日志："
    log "journalctl -u edge-tunnel-agent -n 100 --no-pager"
    return 1
  fi
  log "一次性注册完成，节点 ID：${NODE_ID}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --controller-url) CONTROLLER_URL="$2"; shift 2 ;;
    --token) CONTROLLER_TOKEN="$2"; shift 2 ;;
    --node-id) NODE_ID="$2"; shift 2 ;;
    --node-name) NODE_NAME="$2"; shift 2 ;;
    --machine-id) MACHINE_ID="$2"; shift 2 ;;
    --role) NODE_ROLE="$2"; shift 2 ;;
    --enable-tasks) ENABLE_TASKS=true; shift ;;
    --enable-write-actions) ENABLE_WRITE_ACTIONS=true; shift ;;
    --install-ixtf) INSTALL_IXTF=true; shift ;;
    --skip-ixtf) INSTALL_IXTF=false; shift ;;
    --ixtf-version) IXTF_VERSION="$2"; shift 2 ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --state-dir) STATE_DIR="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --source-build) SOURCE_BUILD=true; shift ;;
    --no-start) NO_START=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    --purge) PURGE=true; UNINSTALL=true; shift ;;
    --remove-easytier-binaries) REMOVE_EASYTIER_BINARIES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

require_root
if [ "$UNINSTALL" = true ]; then
  uninstall_agent
  exit 0
fi
[ -n "$CONTROLLER_URL" ] || fail "--controller-url is required"
[ -n "$CONTROLLER_TOKEN" ] || fail "--token is required"
install -d -m 0755 "$INSTALL_DIR"
if [ "$SOURCE_BUILD" = true ]; then
  install_from_source
else
  install_from_release
fi
if should_install_ixtf; then
  install_ixtf
fi
write_env
write_service
systemctl daemon-reload
systemctl enable edge-tunnel-agent.service
run_once_registration_check || true
if [ "$NO_START" = false ]; then
  systemctl restart edge-tunnel-agent.service
fi

log "Agent 安装完成。"
log "Controller 地址：${CONTROLLER_URL}"
log "Controller Token：$(mask "$CONTROLLER_TOKEN")"
log "节点 ID：${NODE_ID}"
log "节点名称：${NODE_NAME}"
log "节点角色：${NODE_ROLE}"
if [ "$(id -u)" -eq 0 ]; then
  log "当前是 root 用户，后续手动安装命令可以不使用 sudo。"
fi
log "下一步："
log "1. 回到主控面板“节点”页面"
log "2. 点击“刷新”"
log "3. 如果节点未上线，查看："
log "   systemctl status edge-tunnel-agent --no-pager"
log "   journalctl -u edge-tunnel-agent -n 100 --no-pager"
