#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-ike-sh/edge-tunnel-panel}"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/edge-tunnel/agent}"
STATE_DIR="${STATE_DIR:-/var/lib/edge-tunnel/agent}"
LOG_DIR="${LOG_DIR:-/var/log/edge-tunnel}"
CONTROLLER_URL="${EDGE_CONTROLLER_URL:-}"
CONTROLLER_TOKEN="${EDGE_CONTROLLER_TOKEN:-}"
NODE_ID="${EDGE_NODE_ID:-}"
NODE_NAME="${EDGE_NODE_NAME:-$(hostname 2>/dev/null || printf 'edge-node')}"
NODE_ROLE="${EDGE_NODE_ROLE:-backend}"
ENABLE_TASKS="${EDGE_ENABLE_TASKS:-false}"
ENABLE_WRITE_ACTIONS="${EDGE_ENABLE_WRITE_ACTIONS:-false}"
SOURCE_BUILD=false
NO_START=false
UNINSTALL=false
PURGE=false

usage() {
  cat <<'USAGE'
Install Edge Tunnel Panel Agent.

Options:
  --version VERSION             Release version, default: latest
  --controller-url URL          Controller URL, required
  --token TOKEN                 Controller token, required
  --node-id ID                  Optional node id
  --node-name NAME              Node name
  --role ROLE                   entry, relay, exit, backend
  --enable-tasks                Enable task polling
  --enable-write-actions        Enable write actions
  --config-dir DIR              Agent config directory
  --state-dir DIR               Agent state directory
  --install-dir DIR             Binary install directory
  --source-build                Build from current source checkout
  --no-start                    Do not start service after install
  --uninstall                   卸载 Agent 服务和二进制，保留配置、状态和日志
  --purge                       彻底删除 Agent 服务、二进制、配置、状态和日志
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

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "please run as root"
  fi
}

uninstall_agent() {
  systemctl stop edge-tunnel-agent.service >/dev/null 2>&1 || true
  log "已停止 Agent 服务"
  systemctl disable edge-tunnel-agent.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/edge-tunnel-agent.service
  rm -f "$INSTALL_DIR/edge-tunnel-agent"
  log "已删除 Agent 二进制"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed edge-tunnel-agent.service >/dev/null 2>&1 || true
  if [ "$PURGE" = true ]; then
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

download_file() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$dest" "$url"
  else
    fail "curl or wget is required"
  fi
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
  log "downloading $url"
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

write_env() {
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
EOF
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --controller-url) CONTROLLER_URL="$2"; shift 2 ;;
    --token) CONTROLLER_TOKEN="$2"; shift 2 ;;
    --node-id) NODE_ID="$2"; shift 2 ;;
    --node-name) NODE_NAME="$2"; shift 2 ;;
    --role) NODE_ROLE="$2"; shift 2 ;;
    --enable-tasks) ENABLE_TASKS=true; shift ;;
    --enable-write-actions) ENABLE_WRITE_ACTIONS=true; shift ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --state-dir) STATE_DIR="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --source-build) SOURCE_BUILD=true; shift ;;
    --no-start) NO_START=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    --purge) PURGE=true; UNINSTALL=true; shift ;;
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
write_env
write_service
systemctl daemon-reload
systemctl enable edge-tunnel-agent.service
"$INSTALL_DIR/edge-tunnel-agent" --once || log "one-time registration check failed; inspect service logs after startup"
if [ "$NO_START" = false ]; then
  systemctl restart edge-tunnel-agent.service
fi

log "installed /usr/local/bin/edge-tunnel-agent"
log "controller URL: ${CONTROLLER_URL}"
log "controller token: $(mask "$CONTROLLER_TOKEN")"
log "node name: ${NODE_NAME}"
log "node role: ${NODE_ROLE}"
