#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
PACKAGE_VERSION="$(grep -E '^TOOL_VERSION=' "${ROOT_DIR}/wg-toolkit.sh" | head -n 1 | cut -d= -f2 | tr -d '"')"
PACKAGE_NAME="leikwan-wg-toolkit-${PACKAGE_VERSION}"
STAGING_DIR="${DIST_DIR}/${PACKAGE_NAME}"
PACKAGE_PATH="${DIST_DIR}/${PACKAGE_NAME}.tar.gz"
SHA_PATH="${PACKAGE_PATH}.sha256"

cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "FAIL: shellcheck not found" >&2
  exit 1
fi

shellcheck wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
bash scripts/check-redaction.sh

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$STAGING_DIR"

cp wg-toolkit.sh uninstall.sh README.md "$STAGING_DIR/"
cp -R docs "$STAGING_DIR/docs"
mkdir -p "$STAGING_DIR/scripts"
cp scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh "$STAGING_DIR/scripts/"

bash scripts/check-redaction.sh

tar -czf "$PACKAGE_PATH" -C "$DIST_DIR" "$PACKAGE_NAME"

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
echo
echo "安全一键安装："
echo "curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq"
echo
echo "管道安装（只安装，不自动进菜单）："
echo "curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/scripts/bootstrap.sh | bash"
echo "lq"
echo
echo "下载到本地再执行："
echo "curl -fsSL -o /root/wg-toolkit.sh https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/wg-toolkit.sh && chmod +x /root/wg-toolkit.sh && ln -sf /root/wg-toolkit.sh /usr/local/bin/lq && lq"
echo
echo "Release 包安装："
echo "curl -fsSL -o /tmp/leikwan-wg-toolkit.tar.gz https://github.com/ike-sh/leikwan-wg-toolkit/releases/latest/download/leikwan-wg-toolkit-${PACKAGE_VERSION}.tar.gz && tar -xzf /tmp/leikwan-wg-toolkit.tar.gz -C /root && cp /root/leikwan-wg-toolkit-${PACKAGE_VERSION}/wg-toolkit.sh /root/wg-toolkit.sh && chmod +x /root/wg-toolkit.sh && ln -sf /root/wg-toolkit.sh /usr/local/bin/lq && lq"
