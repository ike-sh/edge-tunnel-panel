# Release

构建测试版 release：

```bash
VERSION=v0.2.6-test bash panel/scripts/build-release.sh
```

输出：

- `panel/dist/edge-tunnel-panel-v0.2.6-test-linux-amd64.tar.gz`
- `panel/dist/edge-tunnel-panel-v0.2.6-test-linux-arm64.tar.gz`
- `panel/dist/SHA256SUMS`

每个包根目录包含：

- `edge-tunnel-controller`
- `edge-tunnel-agent`
- `web/`
- `docs/`
- `examples/`
- `scripts/`
- `VERSION`

发布包中的 Go 二进制应为 Linux ELF，安装脚本会在安装前执行 `--version` 做架构可执行性校验。
