# 安全边界

## Token

- Web/API 使用 Operator Token；测试模式可关闭严格鉴权。
- Agent 使用 Controller Token 注册、上报和轮询任务。
- 日志、任务输出和错误信息会做 redaction。

## Action allowlist

Agent 只执行固定 action，例如：

- `collect_agent_status`
- `verify_agent_config`
- `verify_easytier_status`
- `verify_network_connectivity`
- `apply_network_profile`
- `apply_entry_forward_config`
- `apply_landing_forward_config`
- `verify_forward_rules`
- `restart_easytier`

## 禁止 payload

Controller 和 Agent 都会拒绝危险字段：

- `command`
- `cmd`
- `shell`
- `script`
- `raw_nft`
- `raw_iptables`
- `raw_ip_route`

## 写入边界

- 不使用 `shell -c`。
- 不使用 `bash -c`。
- 不使用 `eval`。
- nftables、systemctl、sysctl 都通过固定 argv 调用。
- Agent 需要 root 权限写 systemd、nftables 和 EasyTier 配置。
