#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
PACKAGE_VERSION="$(grep -E '^TOOL_VERSION=' "${ROOT_DIR}/wg-toolkit.sh" | head -n 1 | cut -d= -f2 | tr -d '"')"
PACKAGE_NAME="leikwan-wg-toolkit-${PACKAGE_VERSION}"
PACKAGE_PATH="${DIST_DIR}/${PACKAGE_NAME}.tar.gz"
SHA_PATH="${PACKAGE_PATH}.sha256"

cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "FAIL: shellcheck not found" >&2
  exit 1
fi

shellcheck wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh
bash scripts/check-redaction.sh

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

tar -czf "$PACKAGE_PATH" \
  wg-toolkit.sh \
  uninstall.sh \
  README.md \
  docs \
  scripts/package-release.sh \
  scripts/check-redaction.sh

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$PACKAGE_PATH" >"$SHA_PATH"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$PACKAGE_PATH" >"$SHA_PATH"
else
  echo "FAIL: sha256sum or shasum not found" >&2
  exit 1
fi

echo "Package: ${PACKAGE_PATH}"
echo "SHA256:  ${SHA_PATH}"
