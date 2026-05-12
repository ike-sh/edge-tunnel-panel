# Leikwan Panel 3.0.0-alpha.4

`3.0.0-alpha.4` 是安装链路和中文 Web 面板收敛版。

## 本轮修复

- Controller 一键安装支持 `curl | bash` / `sudo bash` / 本地脚本执行。
- 安装脚本不再直接依赖未定义的 `BASH_SOURCE[0]`。
- alpha 阶段默认 source ref 为 `panel-3-alpha`，release 缺失时 fallback 到同一 ref 源码构建。
- Controller systemd service 使用 `--web-dir` 前，会校验 binary 是否支持该参数。
- Web build 会安装到 `/var/lib/leikwan-panel/web`。
- Web UI 主要页面中文化，并优化 Add Agent 命令框体验。

## 安装命令

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/panel-3-alpha/panel/scripts/install-controller.sh | sudo bash
```

Agent 通过 Web 面板 `添加节点` 页面生成一键命令。

## 安全边界

- 不接受任意命令字符串。
- 不执行 `shell -c` / `bash -c` / `eval`。
- 不做 raw nft / iptables / ip route 输入。
- 不做公网入口平滑切换。
- 不做 relay restart 自动化。
- 不做 backend node 管理。
- 不修改 `leikwan-toolkit.sh`。

## 已知限制

这是 alpha 版本，UI 和真实落地规则仍需继续实机打磨。建议先在测试 VPS 上验证。