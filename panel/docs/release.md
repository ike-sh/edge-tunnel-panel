# Release

当前版本：`v0.2.7-test`

## 构建

```bash
VERSION=v0.2.7-test bash panel/scripts/build-release.sh
```

产物：

```text
panel/dist/edge-tunnel-panel-v0.2.7-test-linux-amd64.tar.gz
panel/dist/edge-tunnel-panel-v0.2.7-test-linux-arm64.tar.gz
panel/dist/SHA256SUMS
```

每个 tarball 根目录包含：

```text
edge-tunnel-controller
edge-tunnel-agent
web/
docs/
examples/
scripts/
VERSION
```

构建脚本会强制交叉编译 Linux ELF，并打包 Web、docs、examples 和 scripts。
