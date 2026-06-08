#!/usr/bin/env bash
# Edge Tunnel Panel — 一键安装入口（Controller / Agent）
# 仓库：https://github.com/ike-sh/edge-tunnel-panel
#
# 安装 Controller（生产，推荐）：
#   curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash
#
# 国内镜像 + 生产鉴权：
#   curl -fsSL https://gh.llkk.cc/https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash -s -- --cn
#
set -Eeuo pipefail

REPO="${REPO:-ike-sh/edge-tunnel-panel}"
BRANCH="${BRANCH:-main}"
VERSION="${VERSION:-latest}"
SCRIPT_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/panel/scripts"

CN=false
STRICT=true
OPEN_UFW=false
PRODUCTION=false
PRODUCTION_PROXY="nginx"
SOURCE_BUILD=false
NO_START=false
SUBCMD="controller"

log() { printf '[quick-install] %s\n' "$*"; }
fail() { printf '[quick-install] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Edge Tunnel Panel 一键安装

用法：
  quick-install.sh [全局选项]           安装 Controller（默认）
  quick-install.sh agent [Agent 选项]   安装 Agent

全局选项：
  --cn              使用国内 GitHub 镜像
  --no-strict-auth  开发用：关闭 Operator 鉴权
  --strict          生产模式（默认）
  --open-ufw        放行 18080/tcp（ufw active 时，开发用）
  --production      生产反代：监听 127.0.0.1:18080 + 防火墙 80/443
  --production-proxy nginx|caddy  配合 --production（默认 nginx）
  --version VER     release 版本，默认 latest
  --source-build    从 git 源码编译
  --no-start        安装后不启动
  -h, --help

Agent 选项：
  --url URL  --token TOKEN  --machine-id ID  [--name nat-ix-1] [--cn]
USAGE
}

require_root() {
  [ "$(id -u)" -eq 0 ] || fail "请使用 root 或 sudo"
}

detect_public_ip() {
  local ip url
  for url in "https://api.ipify.org" "https://ifconfig.me/ip"; do
    ip="$(curl -fsSL --connect-timeout 4 --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]')" || true
    [ -n "$ip" ] && { printf '%s' "$ip"; return 0; }
  done
  return 1
}

fetch_script() {
  local name="$1" dest="$2" url="${SCRIPT_BASE}/${name}"
  if [ "$CN" = true ]; then
    export EDGE_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/"
    url="https://gh.llkk.cc/${url}"
  fi
  curl -fsSL --connect-timeout 15 --max-time 180 "$url" -o "$dest" || fail "下载 ${name} 失败，请加 --cn"
  chmod +x "$dest"
}

maybe_open_firewall() {
  [ "$OPEN_UFW" = true ] || return 0
  command -v ufw >/dev/null 2>&1 || return 0
  ufw status 2>/dev/null | grep -qi 'Status: active' || return 0
  local port="${EDGE_LISTEN:-0.0.0.0:18080}"
  port="${port##*:}"
  ufw allow "${port}/tcp" >/dev/null 2>&1 || true
  log "已尝试 ufw allow ${port}/tcp"
}

print_controller_summary() {
  local env_file="${CONFIG_DIR:-/etc/edge-tunnel/controller}/controller.env"
  local summary_file="${CONFIG_DIR:-/etc/edge-tunnel/controller}/install-summary.txt"
  [ -f "$env_file" ] || return 0
  set -a
  # shellcheck source=/dev/null
  . "$env_file"
  set +a
  local port="${EDGE_LISTEN:-0.0.0.0:18080}"
  port="${port##*:}"
  local pub_ip base strict
  pub_ip="$(detect_public_ip)" || pub_ip="YOUR_SERVER_IP"
  base="http://${pub_ip}:${port}"
  strict="${EDGE_STRICT_AUTH:-false}"

  cat >"$summary_file" <<EOF
# Edge Tunnel Panel — $(date -Iseconds 2>/dev/null || date)
面板：     ${base}/dashboard
登录：     ${base}/login
Operator： ${EDGE_OPERATOR_TOKEN:-}
严格鉴权： ${strict}
配置：     ${env_file}

下一步：登录 → 机器 → 添加 NAT IX → 线路 → 接入码
安全提示：
- Token 曾出现在安装命令/终端，Agent 上线后请在面板轮换 Token
- 生产环境务必启用严格鉴权，勿对公网开放鉴权模式
- release 包会自动校验 SHA256SUMS（若 GitHub release 提供）
EOF
  chmod 0600 "$summary_file"

  printf '\n'
  echo '══════════════════════════════════════════════════'
  echo '  Edge Tunnel Panel 安装成功'
  echo "  面板  ${base}/dashboard"
  if [ "$strict" = "true" ]; then
    echo "  登录  ${base}/login"
    echo "  Token ${EDGE_OPERATOR_TOKEN:-}"
  else
    echo '  模式  开放鉴权（未启用 Token）'
  fi
  echo "  摘要  ${summary_file}"
  echo '══════════════════════════════════════════════════'
  printf '\n'
}

patch_controller_production_env() {
  local env_file="${CONFIG_DIR:-/etc/edge-tunnel/controller}/controller.env"
  [ -f "$env_file" ] || return 0
  if grep -q '^EDGE_LISTEN=' "$env_file"; then
    sed -i 's/^EDGE_LISTEN=.*/EDGE_LISTEN=127.0.0.1:18080/' "$env_file"
  else
    echo 'EDGE_LISTEN=127.0.0.1:18080' >>"$env_file"
  fi
  if grep -q '^EDGE_FORCE_HTTPS=' "$env_file"; then
    sed -i 's/^EDGE_FORCE_HTTPS=.*/EDGE_FORCE_HTTPS=true/' "$env_file"
  else
    echo 'EDGE_FORCE_HTTPS=true' >>"$env_file"
  fi
  systemctl restart edge-tunnel-controller.service 2>/dev/null || true
  log "生产模式：Controller 已改为 127.0.0.1:18080 + EDGE_FORCE_HTTPS=true"
}

run_production_setup() {
  local setup_script mode_flag="--nginx"
  case "$PRODUCTION_PROXY" in
    caddy) mode_flag="--caddy" ;;
    nginx|*) mode_flag="--nginx" ;;
  esac
  setup_script="$(mktemp)"
  fetch_script "setup-production-edge.sh" "$setup_script"
  bash "$setup_script" "$mode_flag" --open-ssh
  rm -f "$setup_script"
  log "下一步：配置 Nginx/Caddy/Traefik 反代到 127.0.0.1:18080，见 docs/deployment-v2.md"
}

install_controller() {
  require_root
  local tmpdir script args=()
  tmpdir="$(mktemp -d)"
  script="${tmpdir}/install-controller.sh"
  if [ "$SOURCE_BUILD" = true ] && [ -f "$(dirname "$0")/install-controller.sh" ]; then
    script="$(cd "$(dirname "$0")" && pwd)/install-controller.sh"
  else
    fetch_script "install-controller.sh" "$script"
  fi
  args=(--version "$VERSION")
  if [ "$STRICT" = true ]; then args+=(--strict-auth); else args+=(--no-strict-auth); fi
  [ "$PRODUCTION" = true ] && args+=(--listen "127.0.0.1:18080")
  [ "$SOURCE_BUILD" = true ] && args+=(--source-build)
  [ "$NO_START" = true ] && args+=(--no-start)
  log "安装 Controller ${VERSION} …"
  bash "$script" "${args[@]}"
  if [ "$PRODUCTION" = true ]; then
    patch_controller_production_env
    run_production_setup
  else
    maybe_open_firewall
  fi
  print_controller_summary
  rm -rf "$tmpdir" 2>/dev/null || true
}

install_agent() {
  require_root
  local url="" token="" machine_id="" name="nat-ix-1"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --url) url="$2"; shift 2 ;;
      --token) token="$2"; shift 2 ;;
      --machine-id) machine_id="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      --cn) CN=true; shift ;;
      *) fail "未知参数: $1" ;;
    esac
  done
  [ -n "$url" ] && [ -n "$token" ] || fail "需要 --url --token"
  local tmpdir script agent_args=()
  tmpdir="$(mktemp -d)"
  script="${tmpdir}/install-agent.sh"
  fetch_script "install-agent.sh" "$script"
  agent_args=(--version "$VERSION" --controller-url "$url" --token "$token" --node-name "$name" --enable-tasks --enable-write-actions --install-ixtf)
  [ -n "$machine_id" ] && agent_args+=(--machine-id "$machine_id")
  bash "$script" "${agent_args[@]}"
  rm -rf "$tmpdir"
  log "Agent 完成，回面板刷新机器状态。"
}

AGENT_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    controller) SUBCMD="controller"; shift ;;
    agent) SUBCMD="agent"; shift; AGENT_ARGS=("$@"); break ;;
    --cn) CN=true; shift ;;
    --strict) STRICT=true; shift ;;
    --no-strict-auth) STRICT=false; shift ;;
    --production) PRODUCTION=true; STRICT=true; shift ;;
    --production-proxy) PRODUCTION_PROXY="$2"; shift 2 ;;
    --open-ufw) OPEN_UFW=true; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    --source-build) SOURCE_BUILD=true; shift ;;
    --no-start) NO_START=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "未知选项: $1" ;;
  esac
done

case "$SUBCMD" in
  controller) install_controller ;;
  agent) install_agent "${AGENT_ARGS[@]}" ;;
esac
