#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PANEL_DIR="${ROOT_DIR}/panel"
BIN_SRC="${PANEL_DIR}/dist/leikwan-controller"
BIN_DST="/usr/local/bin/leikwan-controller"
CONFIG_DIR="/etc/leikwan-panel"
DATA_DIR="/var/lib/leikwan-panel"
ENV_FILE="${CONFIG_DIR}/controller.env"
SERVICE_DST="/etc/systemd/system/leikwan-controller.service"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[FAIL] Please run as root: sudo bash panel/scripts/install-controller.sh" >&2
  exit 1
fi

if [[ ! -x "${BIN_SRC}" ]]; then
  echo "[INFO] Controller binary not found in panel/dist; building local binary."
  (
    cd "${PANEL_DIR}/controller"
    go build -o "${BIN_SRC}" ./cmd/leikwan-controller
  )
fi

install -m 0755 "${BIN_SRC}" "${BIN_DST}"
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}"
chmod 0750 "${CONFIG_DIR}" "${DATA_DIR}"

if [[ -n "${LEIKWAN_CONTROLLER_TOKEN:-}" ]]; then
  umask 077
  printf 'LEIKWAN_CONTROLLER_TOKEN=%s\n' "${LEIKWAN_CONTROLLER_TOKEN}" >"${ENV_FILE}"
  chmod 0600 "${ENV_FILE}"
  echo "[OK] Wrote ${ENV_FILE}"
else
  echo "[WARN] LEIKWAN_CONTROLLER_TOKEN is not set."
  echo "[INFO] No weak token was generated. Create ${ENV_FILE} manually before starting:"
  echo "       sudo install -m 0600 /dev/null ${ENV_FILE}"
  echo "       sudo sh -c 'echo LEIKWAN_CONTROLLER_TOKEN=your-strong-token > ${ENV_FILE}'"
fi

install -m 0644 "${PANEL_DIR}/examples/leikwan-controller.service" "${SERVICE_DST}"
systemctl daemon-reload

echo "[OK] Installed ${BIN_DST}"
echo "[OK] Installed ${SERVICE_DST}"
if [[ -f "${ENV_FILE}" ]]; then
  echo "[INFO] Start with: sudo systemctl enable --now leikwan-controller.service"
else
  echo "[WARN] Controller service was not started because token is not configured."
fi
