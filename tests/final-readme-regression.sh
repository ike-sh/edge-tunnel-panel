#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

grep -q "1.4.0" README.md
grep -q "LTS" README.md
grep -q "功能冻结" README.md
grep -q "lq init" README.md
grep -q "A 公网入口" README.md
grep -q "B 利群主机" README.md
grep -q "DDNS" README.md

echo "[OK] final README regression passed"
