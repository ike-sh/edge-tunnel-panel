# 网络转发

## 组网配置

`v0.1.5-test` 已支持把组网配置下发到节点：

- Controller 创建 `apply_network_profile` 任务。
- 任务 payload 包含完整 `network_profile` 和目标 `node`。
- Agent 写入 `/etc/edge-tunnel/agent/easytier.toml`。
- Agent 写入 `edge-tunnel-easytier.service` 并用固定 `systemctl` 参数启动。

如果任务结果提示 `easytier-core not found`，需要先在节点上安装 EasyTier。

## 公网入口

公网入口定义节点上的监听地址、端口范围、协议、域名和 DDNS 配置。

## 转发规则

- `target_mode=local`：入口节点本地或可直连地址。
- `target_mode=overlay`：通过 EasyTier overlay 到后端节点。

Agent 后续会根据结构化配置生成 nftables 规则，不接受 raw nftables payload。
