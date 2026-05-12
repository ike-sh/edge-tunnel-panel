# 组网与转发

Leikwan Panel `3.0.0-alpha.4` 提供最小可测试的 Network / Entry / Forward 流程。

## 角色

- Entry：公网入口节点，接收公网端口流量。
- Relay：中转节点，负责转发到目标服务。
- Target：落地/后端服务地址，只需要填写 `target_host:target_port`，不需要 Agent。

## 基础流程

1. 添加 Entry / Relay Agent 节点。
2. 创建 Network Profile。
3. 创建 Entry，选择 entry node、relay node 和端口池。
4. 创建 Forward，填写监听端口、目标地址、目标端口和协议。
5. 点击 Apply。
6. 在任务中心查看 entry/relay 任务。

## Apply 做什么

Entry apply 会向 entry/relay 节点创建固定 action 任务，例如：

- `install_easytier`
- `configure_easytier_network`
- `start_easytier`
- `apply_entry_ports`
- `reload_firewall_rules`
- `verify_config`

Forward apply 会向 entry/relay 节点创建固定 action 任务，例如：

- `apply_entry_ports`
- `apply_forward_rules`
- `reload_firewall_rules`
- `verify_config`

不会创建 backend/landing 任务。

## 安全边界

- 不接受自定义 shell 命令。
- 不接受 raw nft / iptables / ip route。
- 不做公网入口平滑切换。
- 不做 relay restart 自动化。
- Shell Core `leikwan-toolkit.sh` 不被修改。