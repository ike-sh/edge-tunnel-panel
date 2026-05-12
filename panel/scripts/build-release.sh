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

build_go() {
  local module="$1" package="$2" arch="$3" output="$4" ldflags="$5"
  command -v "$GO_BIN" >/dev/null 2>&1 || [ -x "$GO_BIN" ] || { printf '[build-release] ERROR: go not found\n' >&2; exit 1; }
  (cd "$ROOT/$module" && GOOS=linux GOARCH="$arch" CGO_ENABLED=0 "$GO_BIN" build -trimpath -ldflags "$ldflags" -o "$output" "$package")
}

package_arch() {
  local arch="$1"
  local stage="$WORK_DIR/linux-$arch"
  rm -rf "$stage"
  mkdir -p "$stage"
  local controller_ldflags="-X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Version=${VERSION} -X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Commit=${COMMIT} -X github.com/ike-sh/edge-tunnel-panel/panel/controller/internal/controller.Date=${BUILD_DATE}"
  local agent_ldflags=""
  build_go "panel/controller" "./cmd/edge-tunnel-controller" "$arch" "$stage/edge-tunnel-controller" "$controller_ldflags"
  build_go "panel/agent" "./cmd/edge-tunnel-agent" "$arch" "$stage/edge-tunnel-agent" "$agent_ldflags"
  cp -a "$ROOT/panel/controller/web/dist" "$stage/web"
  cp -a "$ROOT/panel/docs" "$stage/docs"
  cp -a "$ROOT/panel/examples" "$stage/examples"
  cp -a "$ROOT/panel/scripts" "$stage/scripts"
  printf '%s\n' "$VERSION" >"$stage/VERSION"
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
