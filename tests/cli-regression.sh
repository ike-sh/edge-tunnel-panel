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

validate_json_cli() {
  local out
  out="$(bash leikwan-toolkit.sh "$@" 2>&1)"
  if grep -q "错误：脚本在第" <<<"$out"; then
    echo "FAIL: global trap triggered: $*" >&2
    echo "$out" >&2
    exit 1
  fi
  if command -v jq >/dev/null 2>&1; then
    jq . >/dev/null <<<"$out" || { echo "FAIL: invalid JSON: $*" >&2; echo "$out" >&2; exit 1; }
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync(0,"utf8"));' >/dev/null <<<"$out" || { echo "FAIL: invalid JSON: $*" >&2; echo "$out" >&2; exit 1; }
  else
    grep -q '^{.*' <<<"$(tr -d '\n' <<<"$out")" || { echo "FAIL: JSON validator unavailable and output is not object-like" >&2; echo "$out" >&2; exit 1; }
  fi
}

run_cli --version
run_cli --help
run_cli init --dry-run
run_cli init --plan
run_cli plan
run_cli status
validate_json_cli status --json
run_cli --status
validate_json_cli --status-json
validate_json_cli doctor --json
validate_json_cli --doctor-json
run_cli port check
run_cli --port-check
run_cli ddns status
run_cli update status
run_cli config list
run_cli output show
run_cli logs
run_cli logs ddns
run_cli logs apply
run_cli logs update
run_cli logs doctor
run_cli pbr domain list

echo "[OK] cli regression passed"
