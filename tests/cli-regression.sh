#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export LEIKWAN_STATE_DIR="${TMP_DIR}/state"
export LEIKWAN_BACKUP_DIR="${TMP_DIR}/backups"
export LEIKWAN_RUN_DIR="${TMP_DIR}/run"
export LEIKWAN_LOG_DISABLED=1
export LEIKWAN_NO_CLEAR=1
mkdir -p "$LEIKWAN_RUN_DIR"

run_cli() {
  local out rc
  set +e
  out="$(bash leikwan-toolkit.sh "$@" 2>&1)"
  rc=$?
  set -e
  if (( rc != 0 )); then
    echo "FAIL: command returned ${rc}: $*" >&2
    echo "$out" >&2
    exit 1
  fi
  if grep -q "错误：脚本在第" <<<"$out"; then
    echo "FAIL: global trap triggered: $*" >&2
    echo "$out" >&2
    exit 1
  fi
  [[ -n "$out" ]] || { echo "FAIL: empty output: $*" >&2; exit 1; }
}

run_cli --version
run_cli --help
run_cli init --dry-run
run_cli init --plan
run_cli plan
run_cli status
run_cli --status
run_cli port check
run_cli --port-check
run_cli ddns status
run_cli update status
run_cli config list
run_cli output show
run_cli pbr domain list

echo "[OK] cli regression passed"
