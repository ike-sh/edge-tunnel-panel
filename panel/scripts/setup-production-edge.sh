#!/usr/bin/env bash
# 生产环境：防火墙 + certbot 续期检查（配合 Nginx）
# 用法：sudo bash panel/scripts/setup-production-edge.sh [--nginx|--caddy] [--open-ssh]
set -Eeuo pipefail

MODE="nginx"
OPEN_SSH=false

log() { printf '[setup-production] %s\n' "$*"; }
fail() { printf '[setup-production] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
生产环境辅助脚本：UFW 防火墙 + TLS 续期提示

用法：
  setup-production-edge.sh [--nginx] [--caddy] [--open-ssh]

默认（--nginx）：
  - 允许 22/tcp（仅 --open-ssh 时）
  - 允许 80/tcp、443/tcp
  - 拒绝公网直接访问 18080（本机反代）
  - 检查 certbot timer 与 nginx 续期 hook

--caddy：仅放行 80/443（Caddy 自动 HTTPS，无需 certbot hook）
USAGE
}

require_root() {
  [ "$(id -u)" -eq 0 ] || fail "请使用 root 或 sudo"
}

setup_ufw() {
  command -v ufw >/dev/null 2>&1 || { log "未安装 ufw，跳过防火墙"; return 0; }
  if ! ufw status 2>/dev/null | grep -qi 'Status: active'; then
    log "ufw 未启用，尝试 ufw enable（默认 deny incoming）"
    ufw --force enable >/dev/null 2>&1 || true
  fi
  if [ "$OPEN_SSH" = true ]; then
    ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
    log "已放行 SSH (22/tcp)"
  fi
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw allow 443/tcp >/dev/null 2>&1 || true
  log "已放行 80/tcp、443/tcp"
  ufw deny 18080/tcp >/dev/null 2>&1 || true
  log "已拒绝公网 18080/tcp（请经 Nginx/Caddy 访问）"
  ufw status numbered || true
}

setup_certbot_renewal() {
  command -v certbot >/dev/null 2>&1 || {
    log "未安装 certbot。安装：apt install certbot python3-certbot-nginx"
    return 0
  }
  if systemctl list-unit-files 2>/dev/null | grep -q certbot.timer; then
    systemctl enable certbot.timer >/dev/null 2>&1 || true
    systemctl start certbot.timer >/dev/null 2>&1 || true
    log "certbot.timer 已启用（系统自动续期）"
  else
    log "提示：可添加 cron — 0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'"
  fi
  local hook="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
  if [ "$MODE" = nginx ] && command -v nginx >/dev/null 2>&1; then
    install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
    cat >"$hook" <<'EOF'
#!/usr/bin/env bash
nginx -t && systemctl reload nginx
EOF
    chmod +x "$hook"
    log "已写入 certbot 续期 hook：$hook"
  fi
  certbot renew --dry-run >/dev/null 2>&1 && log "certbot renew --dry-run 通过" || log "certbot dry-run 未通过，请检查域名与 nginx 配置"
}

print_controller_env_hint() {
  cat <<'EOF'

Controller 建议配置（/etc/edge-tunnel/controller/controller.env）：
  EDGE_LISTEN=127.0.0.1:18080
  EDGE_STRICT_AUTH=true
  EDGE_FORCE_HTTPS=1

修改后：systemctl restart edge-tunnel-controller

EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --nginx) MODE="nginx"; shift ;;
    --caddy) MODE="caddy"; shift ;;
    --open-ssh) OPEN_SSH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "未知选项: $1" ;;
  esac
done

require_root
log "模式：$MODE"
setup_ufw
if [ "$MODE" = nginx ]; then
  setup_certbot_renewal
else
  log "Caddy 模式：自动 HTTPS，无需 certbot hook"
fi
print_controller_env_hint
log "完成"
