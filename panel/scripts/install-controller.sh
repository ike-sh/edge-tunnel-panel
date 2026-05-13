#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-ike-sh/edge-tunnel-panel}"
VERSION="${VERSION:-latest}"
LISTEN="${LISTEN:-0.0.0.0:18080}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/edge-tunnel/controller}"
DATA_DIR="${DATA_DIR:-/var/lib/edge-tunnel/controller}"
WEB_DIR="${WEB_DIR:-/var/lib/edge-tunnel/controller/web}"
LOG_DIR="${LOG_DIR:-/var/log/edge-tunnel}"
SOURCE_BUILD=false
NO_START=false
UNINSTALL=false
PURGE=false
STRICT_AUTH=false
OPERATOR_TOKEN="${EDGE_OPERATOR_TOKEN:-}"
AGENT_TOKEN="${EDGE_CONTROLLER_TOKEN:-}"

usage() {
  cat <<'USAGE'
Install Edge Tunnel Panel Controller.

Options:
  --version VERSION          Release version, default: latest
  --listen ADDR             Listen address, default: 0.0.0.0:18080
  --operator-token TOKEN    Web/API operator token
  --agent-token TOKEN       Agent controller token
  --web-dir DIR             Web asset directory
  --install-dir DIR         Binary install directory
  --data-dir DIR            Controller data directory
  --config-dir DIR          Controller config directory
  --source-build            Build from current source checkout
  --no-start                Do not start service after install
  --strict-auth             Enable Operator Token auth for Web/API
  --no-strict-auth          Disable Operator Token auth for testing, default
  --uninstall               卸载主控服务和二进制，保留配置、数据和日志
  --purge                   彻底删除主控服务、二进制、配置、数据和日志
  -h, --help                Show help
USAGE
}

log() { printf '[edge-tunnel-controller] %s\n' "$*"; }
fail() { printf '[edge-tunnel-controller] ERROR: %s\n' "$*" >&2; exit 1; }

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

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "please run as root"
  fi
}

uninstall_controller() {
  systemctl stop edge-tunnel-controller.service >/dev/null 2>&1 || true
  log "已停止主控服务"
  systemctl disable edge-tunnel-controller.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/edge-tunnel-controller.service
  rm -f "$INSTALL_DIR/edge-tunnel-controller"
  log "已删除主控二进制"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed edge-tunnel-controller.service >/dev/null 2>&1 || true
  if [ "$PURGE" = true ]; then
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    rmdir /etc/edge-tunnel >/dev/null 2>&1 || true
    rmdir /var/lib/edge-tunnel >/dev/null 2>&1 || true
    log "已彻底删除配置、数据和日志"
  else
    log "已保留配置和数据"
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

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
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
  if [ ! -f "$tmp/edge-tunnel-controller" ]; then
    find "$tmp" -maxdepth 3 -type f | sort >&2
    fail "edge-tunnel-controller not found in release archive"
  fi
  if file_cmd="$(find_file_cmd)"; then
    "$file_cmd" "$tmp/edge-tunnel-controller" || true
  fi
  if ! "$tmp/edge-tunnel-controller" --version >/dev/null 2>&1; then
    fail "downloaded edge-tunnel-controller cannot run on this machine; check release asset architecture"
  fi
  install -m 0755 "$tmp/edge-tunnel-controller" "$INSTALL_DIR/edge-tunnel-controller"
  if [ -d "$tmp/web" ]; then
    rm -rf "$WEB_DIR"
    mkdir -p "$WEB_DIR"
    cp -a "$tmp/web/." "$WEB_DIR/"
  fi
  rm -rf "$tmp"
}

install_from_source() {
  command -v go >/dev/null 2>&1 || fail "go is required for --source-build"
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  (cd "$root/panel/controller" && go build -o "$INSTALL_DIR/edge-tunnel-controller" ./cmd/edge-tunnel-controller)
  if [ -d "$root/panel/controller/web/dist" ]; then
    rm -rf "$WEB_DIR"
    mkdir -p "$WEB_DIR"
    cp -a "$root/panel/controller/web/dist/." "$WEB_DIR/"
  else
    log "web dist not found; run npm --prefix panel/controller/web run build if static assets are needed"
  fi
}

write_env() {
  install -d -m 0755 "$CONFIG_DIR" "$DATA_DIR" "$WEB_DIR" "$LOG_DIR"
  OPERATOR_TOKEN="${OPERATOR_TOKEN:-$(random_token)}"
  AGENT_TOKEN="${AGENT_TOKEN:-$(random_token)}"
  cat >"$CONFIG_DIR/controller.env" <<EOF
EDGE_LISTEN=${LISTEN}
EDGE_DATA_DIR=${DATA_DIR}
EDGE_OPERATOR_TOKEN=${OPERATOR_TOKEN}
EDGE_CONTROLLER_TOKEN=${AGENT_TOKEN}
EDGE_STRICT_AUTH=${STRICT_AUTH}
EDGE_WEB_DIR=${WEB_DIR}
EOF
  chmod 0600 "$CONFIG_DIR/controller.env"
}

write_service() {
  cat >/etc/systemd/system/edge-tunnel-controller.service <<EOF
[Unit]
Description=Edge Tunnel Panel Controller
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=${CONFIG_DIR}/controller.env
WorkingDirectory=${DATA_DIR}
ExecStart=${INSTALL_DIR}/edge-tunnel-controller
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --listen) LISTEN="$2"; shift 2 ;;
    --operator-token) OPERATOR_TOKEN="$2"; shift 2 ;;
    --agent-token) AGENT_TOKEN="$2"; shift 2 ;;
    --web-dir) WEB_DIR="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --source-build) SOURCE_BUILD=true; shift ;;
    --no-start) NO_START=true; shift ;;
    --strict-auth) STRICT_AUTH=true; shift ;;
    --no-strict-auth) STRICT_AUTH=false; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    --purge) PURGE=true; UNINSTALL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

require_root
if [ "$UNINSTALL" = true ]; then
  uninstall_controller
  exit 0
fi
install -d -m 0755 "$INSTALL_DIR"
if [ "$SOURCE_BUILD" = true ]; then
  install_from_source
else
  install_from_release
fi
write_env
write_service
systemctl daemon-reload
systemctl enable edge-tunnel-controller.service
if [ "$NO_START" = false ]; then
  systemctl restart edge-tunnel-controller.service
fi

log "Controller 安装完成。"
log "监听地址：http://${LISTEN}"
log "浏览器访问：请使用服务器公网 IP 或域名，例如 http://SERVER_IP:18080"
log "Operator Token：${OPERATOR_TOKEN}"
log "Agent 接入 Token：${AGENT_TOKEN}"
log "Token 只在安装输出中显示一次，请妥善保存。"
if [ "$STRICT_AUTH" = false ]; then
  log "当前为测试模式：Web API 未启用 Operator Token 鉴权。"
  log "如需开启，请使用 --strict-auth 重新安装或修改 controller.env。"
fi
log "下一步："
log "1. 打开主控 Web"
log "2. 保存 Operator Token"
log "3. 进入“节点”页面，点击“添加节点”生成一键接入命令"
