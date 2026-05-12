# Leikwan Panel 历史预览说明

这个文件保留用于旧链接兼容。当前推荐版本是 `3.0.0-alpha.4`。

Shell Core 继续保持 `1.4.0 LTS`，负责本机转发能力。Panel 是独立的 Controller / Agent / Web 面板线。

## 当前边界

`3.0.0-alpha.4` 支持真实 alpha apply，但仍然不接受任意命令字符串，不执行 `shell -c` / `bash -c` / `eval`，不暴露 raw nft / iptables / ip route 输入。

Agent 只能执行固定 action。写动作必须满足：

- Agent 配置 `enable_write_actions=true`
- Operator token 授权
- action 在白名单中
- payload 通过本地校验

## 只读 API 示例

```bash
curl http://127.0.0.1:18080/api/v1/health
curl http://127.0.0.1:18080/api/v1/nodes
curl http://127.0.0.1:18080/api/v1/events
```

## Agent 上报

Agent 主动连接 Controller。Controller 不需要 SSH 到节点，Controller 离线不会影响已有转发。