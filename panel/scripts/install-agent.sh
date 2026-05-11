#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PANEL_DIR="${ROOT_DIR}/panel"
BIN_SRC="${PANEL_DIR}/dist/leikwan-agent"
BIN_DST="/usr/local/bin/leikwan-agent"
CONFIG_DIR="/etc/leikwan-agent"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
SERVICE_DST="/etc/systemd/system/leikwan-agent.service"

controller_url=""
token=""
node_name=""
role="unknown"
test_once=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --controller) controller_url="${2:-}"; shift 2 ;;
    --token) token="${2:-}"; shift 2 ;;
    --name) node_name="${2:-}"; shift 2 ;;
    --role) role="${2:-}"; shift 2 ;;
    --test-once) test_once=1; shift ;;
    *) echo "[FAIL] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[FAIL] Please run as root: sudo bash panel/scripts/install-agent.sh --controller URL --token TOKEN --name NAME --role ROLE" >&2
  exit 1
fi

if [[ -z "${controller_url}" || -z "${token}" || -z "${node_name}" ]]; then
  echo "[FAIL] Missing required arguments: --controller, --token, --name" >&2
  exit 1
fi

if [[ ! -x "${BIN_SRC}" ]]; then
  echo "[INFO] Agent binary not found in panel/dist; building local binary."
  (
    cd "${PANEL_DIR}/agent"
    go build -o "${BIN_SRC}" ./cmd/leikwan-agent
  )
fi

install -m 0755 "${BIN_SRC}" "${BIN_DST}"
mkdir -p "${CONFIG_DIR}"
chmod 0750 "${CONFIG_DIR}"

"${BIN_DST}" --init-config --config "${CONFIG_FILE}" --controller-url "${controller_url}" --token "${token}" --node-name "${node_name}" --role "${role}"
chmod 0600 "${CONFIG_FILE}"

install -m 0644 "${PANEL_DIR}/examples/leikwan-agent.service" "${SERVICE_DST}"
systemctl daemon-reload

echo "[OK] Installed ${BIN_DST}"
echo "[OK] Wrote ${CONFIG_FILE}"
echo "[OK] Installed ${SERVICE_DST}"
echo "[INFO] This script does not modify lq, nftables, EasyTier, DDNS, entries.tsv, forwards.tsv, or PBR."

if (( test_once == 1 )); then
  "${BIN_DST}" --config "${CONFIG_FILE}" --once
fi

echo "[INFO] Start with: sudo systemctl enable --now leikwan-agent.service"
