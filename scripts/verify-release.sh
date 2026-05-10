#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

section() {
  echo
  echo "==> $*"
}

section "bash syntax"
bash -n leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh

section "shellcheck"
shellcheck leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh

section "git diff --check"
git diff --check

section "redaction check"
bash scripts/check-redaction.sh

section "smoke tests"
bash tests/smoke.sh

section "cli regression"
bash tests/cli-regression.sh

section "render regression"
bash tests/render-regression.sh

section "package regression"
bash tests/package-regression.sh

section "redaction regression"
bash tests/redaction-regression.sh

section "release package"
bash scripts/package-release.sh

echo
echo "[OK] release verification passed"
