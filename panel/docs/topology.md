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

## v0.2.0-test 组网流程

1. 节点页添加 Agent。
2. 节点上线后进入“组网配置”。
3. 创建组网配置并应用到节点。
4. Agent 写入 EasyTier 配置和 systemd service。
5. 任务页查看 `apply_network_profile` 结果。
6. 节点页刷新查看 EasyTier 状态。

## 角色

- `entry`：公网入口节点。
- `relay`：中继节点。
- `exit`：出口节点。
- `backend`：后端节点。
