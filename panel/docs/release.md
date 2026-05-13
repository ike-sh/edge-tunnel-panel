# Release

构建测试版 release：

```bash
VERSION=v0.2.1-hotfix bash panel/scripts/build-release.sh
```

输出：

- `panel/dist/edge-tunnel-panel-v0.2.1-hotfix-linux-amd64.tar.gz`
- `panel/dist/edge-tunnel-panel-v0.2.1-hotfix-linux-arm64.tar.gz`
- `panel/dist/SHA256SUMS`

每个包根目录包含：

- `edge-tunnel-controller`
- `edge-tunnel-agent`
- `web/`
- `docs/`
- `examples/`
- `scripts/`
- `VERSION`
