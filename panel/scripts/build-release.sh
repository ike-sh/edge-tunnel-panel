#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${VERSION:-}"
DIST_DIR="$ROOT/panel/dist"
WORK_DIR="$DIST_DIR/work"

if [ -z "$VERSION" ]; then
  VERSION="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null || true)"
fi
VERSION="${VERSION:-0.1.0-dev}"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
BUILD_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
GO_BIN="${GO_BIN:-go}"
if ! command -v "$GO_BIN" >/dev/null 2>&1; then
  for candidate in "/mnt/host/d/Program Files/Go/bin/go.exe" "/mnt/d/Program Files/Go/bin/go.exe" "/d/Program Files/Go/bin/go.exe" "/c/Program Files/Go/bin/go.exe"; do
    if [ -x "$candidate" ]; then
      GO_BIN="$candidate"
      break
    fi
  done
fi

log() { printf '[build-release] %s\n' "$*"; }
die() {
  printf '[build-release] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

find_npm() {
  if command -v npm >/dev/null 2>&1; then
    printf 'npm\n'
    return 0
  fi
  for candidate in "/mnt/host/d/Program Files/nodejs/npm" "/mnt/host/c/Program Files/nodejs/npm" "/c/Program Files/nodejs/npm" "/d/Program Files/nodejs/npm"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  if command -v npm.cmd >/dev/null 2>&1; then
    printf 'npm.cmd\n'
    return 0
  fi
  for candidate in "/mnt/host/d/Program Files/nodejs/npm.cmd" "/mnt/host/c/Program Files/nodejs/npm.cmd" "/c/Program Files/nodejs/npm.cmd" "/d/Program Files/nodejs/npm.cmd"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

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

find_powershell() {
  if command -v powershell.exe >/dev/null 2>&1; then
    printf 'powershell.exe\n'
    return 0
  fi
  if command -v pwsh.exe >/dev/null 2>&1; then
    printf 'pwsh.exe\n'
    return 0
  fi
  for candidate in "/mnt/host/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" "/mnt/host/c/Program Files/PowerShell/7/pwsh.exe" "/c/Program Files/PowerShell/7/pwsh.exe"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

native_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
    return
  fi
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$path"
    return
  fi
  case "$path" in
    /mnt/host/*)
      local rest="${path#/mnt/host/}"
      local drive="${rest%%/*}"
      local tail="${rest#*/}"
      drive="$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')"
      printf '%s:\\%s\n' "$drive" "$(printf '%s' "$tail" | sed 's#/#\\#g')"
      ;;
    /mnt/[a-zA-Z]/*)
      local rest="${path#/mnt/}"
      local drive="${rest%%/*}"
      local tail="${rest#*/}"
      drive="$(printf '%s' "$drive" | tr '[:lower:]' '[:upper:]')"
      printf '%s:\\%s\n' "$drive" "$(printf '%s' "$tail" | sed 's#/#\\#g')"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

go_output_path() {
  local output="$1"
  if "$GO_BIN" env GOHOSTOS 2>/dev/null | grep -qx 'windows'; then
    native_path "$output"
  else
    printf '%s\n' "$output"
  fi
}

build_go() {
  local module="$1" package="$2" arch="$3" output="$4" ldflags="$5"
  command -v "$GO_BIN" >/dev/null 2>&1 || [ -x "$GO_BIN" ] || { printf '[build-release] ERROR: go not found\n' >&2; exit 1; }
  local native_output
  native_output="$(go_output_path "$output")"
  if "$GO_BIN" env GOHOSTOS 2>/dev/null | grep -qx 'windows'; then
    local native_go native_dir
    local ps_cmd
    ps_cmd="$(find_powershell)" || die "PowerShell is required to drive Windows Go cross-compilation"
    native_go="$(native_path "$GO_BIN")"
    native_dir="$(native_path "$ROOT/$module")"
    local ps_script native_script
    ps_script="$WORK_DIR/go-build-$arch-$$.ps1"
    cat >"$ps_script" <<'PWSH'
param(
  [string]$GoBin,
  [string]$WorkDir,
  [string]$Output,
  [string]$Package,
  [string]$Arch,
  [string]$Ldflags
)
      $ErrorActionPreference = "Stop"
      $env:CGO_ENABLED = "0"
      $env:GOOS = "linux"
      $env:GOARCH = $Arch
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
      Set-Location -LiteralPath $WorkDir
      $BuildArgs = @("build", "-trimpath")
      if ($Ldflags) {
        $BuildArgs += @("-ldflags", $Ldflags)
      }
      $BuildArgs += @("-o", $Output, $Package)
      & $GoBin @BuildArgs
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
PWSH
    native_script="$(native_path "$ps_script")"
    "$ps_cmd" -NoProfile -ExecutionPolicy Bypass -File "$native_script" "$native_go" "$native_dir" "$native_output" "$package" "$arch" "$ldflags"
  else
    (cd "$ROOT/$module" && env CGO_ENABLED=0 GOOS=linux GOARCH="$arch" "$GO_BIN" build -trimpath -ldflags "$ldflags" -o "$output" "$package")
  fi
}

verify_linux_elf() {
  local path="$1" arch="$2" label="$3"
  test -s "$path" || die "missing $label binary for linux/$arch"
  local file_cmd
  if ! file_cmd="$(find_file_cmd)"; then
    log "warning: file command not found; skipping ELF check for $label linux/$arch"
    return
  fi
  local info
  local inspect_path="$path"
  case "$file_cmd" in
    *.exe) inspect_path="$(native_path "$path")" ;;
  esac
  info="$("$file_cmd" "$inspect_path")"
  log "$info"
  case "$info" in
    *PE32+*) die "$label binary is not linux/$arch ELF" ;;
  esac
  case "$arch" in
    amd64)
      case "$info" in
        *"ELF 64-bit"*x86-64*) ;;
        *) die "$label binary is not linux/amd64 ELF" ;;
      esac
      ;;
    arm64)
      case "$info" in
        *"ELF 64-bit"*aarch64*|*"ELF 64-bit"*AArch64*|*"ELF 64-bit"*ARM*aarch64*) ;;
        *) die "$label binary is not linux/arm64 ELF" ;;
      esac
      ;;
  esac
}

package_arch() {
  local arch="$1"
  local stage="$WORK_DIR/linux-$arch"
  rm -rf "$stage"
  mkdir -p "$stage"
  local controller_ldflags="-X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Version=${VERSION} -X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Commit=${COMMIT} -X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Date=${BUILD_DATE} -X main.version=${VERSION}"
  local agent_ldflags="-X main.version=${VERSION}"
  build_go "panel/controller" "./cmd/edge-tunnel-controller" "$arch" "$stage/edge-tunnel-controller" "$controller_ldflags"
  build_go "panel/agent" "./cmd/edge-tunnel-agent" "$arch" "$stage/edge-tunnel-agent" "$agent_ldflags"
  verify_linux_elf "$stage/edge-tunnel-controller" "$arch" "controller"
  verify_linux_elf "$stage/edge-tunnel-agent" "$arch" "agent"
  cp -a "$ROOT/panel/controller/web/dist" "$stage/web"
  cp -a "$ROOT/panel/docs" "$stage/docs"
  cp -a "$ROOT/panel/examples" "$stage/examples"
  cp -a "$ROOT/panel/scripts" "$stage/scripts"
  printf '%s\n' "$VERSION" >"$stage/VERSION"
  chmod +x "$stage/edge-tunnel-controller" "$stage/edge-tunnel-agent"
  chmod +x "$stage/scripts/"*.sh
  (cd "$stage" && tar -czf "$DIST_DIR/edge-tunnel-panel-${VERSION}-linux-${arch}.tar.gz" .)
}

rm -rf "$DIST_DIR"
mkdir -p "$WORK_DIR"
log "building web"
NPM_CMD="$(find_npm)" || die "npm is required to build Web. Install Node.js or add npm to PATH."
(cd "$ROOT" && if [ -f panel/controller/web/package-lock.json ]; then
  "$NPM_CMD" --prefix panel/controller/web ci
else
  "$NPM_CMD" --prefix panel/controller/web install
fi
"$NPM_CMD" --prefix panel/controller/web run build)

log "building linux/amd64"
package_arch amd64
log "building linux/arm64"
package_arch arm64

(cd "$DIST_DIR" && sha256sum edge-tunnel-panel-"$VERSION"-linux-*.tar.gz > SHA256SUMS)

log "created:"
ls -1 "$DIST_DIR"/edge-tunnel-panel-"$VERSION"-linux-*.tar.gz "$DIST_DIR/SHA256SUMS"
log "install controller:"
log "curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash"
