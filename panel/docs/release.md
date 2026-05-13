# Release

当前版本：`v0.3.0-ui-test`

```bash
VERSION=v0.3.0-ui-test bash panel/scripts/build-release.sh
```

产物：

```text
panel/dist/edge-tunnel-panel-v0.3.0-ui-test-linux-amd64.tar.gz
panel/dist/edge-tunnel-panel-v0.3.0-ui-test-linux-arm64.tar.gz
panel/dist/SHA256SUMS
```

v0.3.0-ui-test 重点重构 Web UI：新增侧栏、顶部状态栏、表格列表、详情抽屉、统一状态标签和更紧凑的转发/PBR/任务排障页面。



## Credits

Web UI 布局和交互思路参考 bqlpfy/flux-panel，原项目使用 Apache-2.0 License。详见 panel/docs/credits.md。
