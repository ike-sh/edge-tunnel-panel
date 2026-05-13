# 拓扑说明

## 单节点直接转发

```text
客户端 -> 公网入口节点 -> 本机或局域网目标服务
```

适合目标服务就在入口节点上，或入口节点能直接访问目标地址。

## 多节点隧道转发

```text
客户端 -> 公网入口节点 -> EasyTier overlay -> 后端节点 -> 目标服务
```

适合后端节点没有公网 IPv4，只能主动接入主控和 overlay 网络。

## v0.2.2-test 组网流程

1. 节点页添加 Agent。
2. 节点上线后进入“组网配置”。
3. 在“快速组网”里选择公网入口节点和后端节点。
4. 面板自动给入口节点下发 listeners，peers 为空。
5. 面板自动给后端节点下发 listeners，并把 peers 指向入口公网 IP。
6. Agent 写入 EasyTier 配置和 systemd service。
7. 任务页查看两个 `apply_network_profile` 结果。
8. 节点页刷新查看 EasyTier 状态和 Peer 数量。

如果服务显示运行中但 Peer 为 0，优先检查入口节点安全组是否放行 `11010/tcp` 和 `11010/udp`。

## 组网状态

“验证组网”会解析 EasyTier peer 和 route 输出：

- `network_ok=true`：服务运行且发现远端 Peer。
- `peer_count`：只统计远端 Peer，不包含 Local。
- `best_latency_ms`：远端 Peer 的最佳延迟。
- `packet_loss`：Peer 表格中的丢包率。
- `tunnels`：例如 `udp,tcp`。
- `route_type`：例如 `DIRECT`。

## 角色

- `entry`：公网入口节点。
- `relay`：中继节点。
- `exit`：出口节点。
- `backend`：后端节点。
