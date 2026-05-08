#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_GITHUB="https://github.com/ike-sh/leikwan-wg-toolkit"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/wg-toolkit.sh"
INSTALL_PATH="/root/wg-toolkit.sh"
SHORTCUT_PATH="/usr/local/bin/lq"

ok() { echo "[OK] $*"; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*" >&2; }

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
  local raw_url="$1" mirrors mirror
  local -a mirror_list=()
  printf '%s\n' "$raw_url"
  mirrors="${LEIKWAN_GITHUB_MIRRORS:-${LEIKWAN_GITHUB_MIRROR:-}}"
  mirrors="${mirrors//;/,}"
  IFS=',' read -r -a mirror_list <<<"$mirrors"
  for mirror in "${mirror_list[@]}"; do
    mirror="$(trim_spaces "$mirror")"
    [[ -n "$mirror" ]] || continue
    mirror_url_for "$mirror" "$raw_url"
  done
}

download_with_fallback() {
  local raw_url="$1" dest_file="$2" candidate tmp timeout
  timeout="${LEIKWAN_DOWNLOAD_TIMEOUT:-15}"
  tmp="${dest_file}.tmp.$$"
  rm -f "$tmp"
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    info "正在尝试下载：${candidate}"
    if curl -fL --retry 1 --connect-timeout "$timeout" --max-time "$timeout" -o "$tmp" "$candidate"; then
      mv -f "$tmp" "$dest_file"
      ok "下载成功：${candidate}"
      return 0
    fi
    warn "下载失败，尝试下一个镜像"
  done < <(github_url_candidates "$raw_url")
  rm -f "$tmp"
  fail "全部下载地址均失败：${raw_url}"
  return 1
}

main() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "请使用 root 运行，例如：curl -fsSL ${PROJECT_GITHUB}/raw/main/scripts/bootstrap.sh | sudo bash"
    exit 1
  fi
  command -v curl >/dev/null 2>&1 || { fail "缺少 curl，请先安装 curl。"; exit 1; }
  local tmp
  tmp="$(mktemp)"
  download_with_fallback "$RAW_SCRIPT_URL" "$tmp"
  install -m 755 "$tmp" "$INSTALL_PATH"
  rm -f "$tmp"
  ln -sf "$INSTALL_PATH" "$SHORTCUT_PATH"
  ok "已安装：${INSTALL_PATH}"
  ok "快捷命令：${SHORTCUT_PATH}"
  info "现在进入 Leikwan Toolkit 菜单。"
  exec bash "$INSTALL_PATH" "$@"
}

main "$@"
