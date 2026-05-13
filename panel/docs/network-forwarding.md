# 网络与转发

## 快速组网

主流程是“快速组网”：选择一个公网入口节点和一个后端节点，面板自动生成入口 listeners 和后端 peers。

- 入口节点：监听 `tcp://0.0.0.0:11010`、`udp://0.0.0.0:11010`，peers 为空。
- 后端节点：listeners 保持默认，peers 指向入口公网 IP。
- 两端使用同一组 `network_name`、`network_secret` 和 CIDR。
- 完成后会生成组网卡片，用于查看状态、Peer、延迟、丢包、隧道和路由。

## EasyTier 虚拟 IP

Agent 生成的 EasyTier 启动参数包含 `-d` 和 `-i CIDR`，用于启用 DHCP/虚拟 IP。后续转发规则默认使用后端节点的 EasyTier 虚拟 IP 作为目标地址。

## 转发规则 MVP

`v0.2.3-test` 支持单端口 TCP/UDP 转发规则：

- 协议：`tcp`、`udp`、`both`。
- 入口节点：接收公网请求。
- 后端节点：提供目标服务。
- 目标 IP：默认使用后端节点 EasyTier 虚拟 IP，也可以手动填写。
- 目标端口：后端服务端口。

应用规则时 Controller 只向入口节点下发 `apply_forward_config` 任务。Agent 会写入：

- `/etc/edge-tunnel/agent/forward.json`
- `/etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft`

Agent 使用固定 argv 执行：

```bash
nft -c -f /etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft
nft -f /etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft
```

不支持 raw nft payload。

## 验证规则

点击“验证规则”会创建 `verify_forward_rules` 任务，检查 nftables table 是否存在、规则是否包含目标、以及 IPv4 forwarding 状态。
