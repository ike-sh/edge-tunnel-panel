#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PANEL_DIR="${ROOT_DIR}/panel"
DIST_DIR="${PANEL_DIR}/dist"

GOOS_VALUE="${GOOS:-$(go env GOOS)}"
GOARCH_VALUE="${GOARCH:-$(go env GOARCH)}"
GOEXE_VALUE="$(GOOS="${GOOS_VALUE}" GOARCH="${GOARCH_VALUE}" go env GOEXE)"

mkdir -p "${DIST_DIR}"

echo "[INFO] Building controller for ${GOOS_VALUE}/${GOARCH_VALUE}"
(
  cd "${PANEL_DIR}/controller"
  GOOS="${GOOS_VALUE}" GOARCH="${GOARCH_VALUE}" go build -o "${DIST_DIR}/leikwan-controller${GOEXE_VALUE}" ./cmd/leikwan-controller
)

echo "[INFO] Building agent for ${GOOS_VALUE}/${GOARCH_VALUE}"
(
  cd "${PANEL_DIR}/agent"
  GOOS="${GOOS_VALUE}" GOARCH="${GOARCH_VALUE}" go build -o "${DIST_DIR}/leikwan-agent${GOEXE_VALUE}" ./cmd/leikwan-agent
)

echo "[INFO] Building web assets"
(
  cd "${PANEL_DIR}/controller"
  npm --prefix web install
  npm --prefix web run build
)

rm -rf "${DIST_DIR}/web"
mkdir -p "${DIST_DIR}/web"
cp -R "${PANEL_DIR}/controller/web/dist/." "${DIST_DIR}/web/"

echo "[OK] Panel release files written to ${DIST_DIR}"
