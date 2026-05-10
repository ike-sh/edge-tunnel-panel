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

run_ok() {
  local out
  out="$("$@" 2>&1)"
  if grep -q "错误：脚本在第" <<<"$out"; then
    echo "FAIL: global trap triggered: $*" >&2
    echo "$out" >&2
    exit 1
  fi
}

run_fail_clean() {
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if (( rc == 0 )); then
    echo "FAIL: expected non-zero: $*" >&2
    echo "$out" >&2
    exit 1
  fi
  if grep -q "错误：脚本在第" <<<"$out"; then
    echo "FAIL: global trap triggered: $*" >&2
    echo "$out" >&2
    exit 1
  fi
  grep -Eq "用法|缺少|未知" <<<"$out" || {
    echo "FAIL: missing friendly error for: $*" >&2
    echo "$out" >&2
    exit 1
  }
}

bash -n leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
run_ok bash leikwan-toolkit.sh --version
run_ok bash leikwan-toolkit.sh --help

version="$(bash leikwan-toolkit.sh --version)"
[[ "$version" == "leikwan-toolkit 1.3.0" ]] || { echo "FAIL: version output: ${version}" >&2; exit 1; }

help_text="$(bash leikwan-toolkit.sh --help)"
grep -q "init" <<<"$help_text"
grep -q "config export" <<<"$help_text"
grep -q "output generate" <<<"$help_text"
grep -q "port check" <<<"$help_text"

run_ok bash leikwan-toolkit.sh init --dry-run
run_ok bash leikwan-toolkit.sh init --plan
run_ok bash leikwan-toolkit.sh wizard --dry-run
run_ok bash leikwan-toolkit.sh quickstart --dry-run
run_ok bash leikwan-toolkit.sh plan
run_ok bash leikwan-toolkit.sh status
run_ok bash leikwan-toolkit.sh --status
run_ok bash leikwan-toolkit.sh port check
run_ok bash leikwan-toolkit.sh ddns status
run_ok bash leikwan-toolkit.sh update status
run_ok bash leikwan-toolkit.sh config list
run_ok bash leikwan-toolkit.sh output show
run_ok bash leikwan-toolkit.sh pbr domain list

run_fail_clean bash leikwan-toolkit.sh config inspect
run_fail_clean bash leikwan-toolkit.sh config import
run_fail_clean bash leikwan-toolkit.sh output unknown

echo "[OK] smoke passed"
