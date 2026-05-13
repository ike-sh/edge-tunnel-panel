# 安全说明

## Token

- Web/API 使用 Operator Token；测试模式可关闭严格鉴权。
- Agent 使用 Controller Token 注册、上报和轮询任务。
- 日志、任务输出和错误信息会做 redaction。

## Agent action allowlist

Agent 只执行固定 action，例如：

- `collect_agent_status`
- `run_node_preflight`
- `verify_easytier_status`
- `verify_network_connectivity`
- `apply_network_profile`
- `install_or_update_easytier`
- `apply_forward_config`
- `verify_forward_rules`

## 禁止 payload

Controller 和 Agent 会拒绝危险字段：

- `command`
- `cmd`
- `shell`
- `script`
- `raw_nft`
- `raw_iptables`
- `raw_ip_route`

## Root 权限

Agent 需要 root 权限来写 systemd、nftables 和 EasyTier 配置。写入动作应只在可信节点开启。
