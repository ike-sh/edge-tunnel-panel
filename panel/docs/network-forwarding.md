# 网络转发

## 组网配置

`v0.2.2-test` 已支持把组网配置下发到节点：

- 推荐使用“快速组网”：选择公网入口节点和后端节点，面板自动生成 listeners 和 peers。
- 入口节点 listeners 默认是 `tcp://0.0.0.0:11010`、`udp://0.0.0.0:11010`，peers 自动留空。
- 后端节点 peers 自动指向入口公网 IP：`tcp://入口公网IP:11010`、`udp://入口公网IP:11010`。
- Controller 创建 `apply_network_profile` 任务。
- 任务 payload 包含完整 `network_profile` 和目标 `node`。
- Agent 写入 `/etc/edge-tunnel/agent/network-profile.json`。
- Agent 写入 `/etc/edge-tunnel/agent/easytier.toml`。
- Agent 在缺少 `easytier-core` 时尝试自动安装 EasyTier v2.4.5。
- Agent 使用 Go 内置 zip 解压，不依赖系统 `unzip`。
- Agent 生成 `edge-tunnel-easytier.service`，并用固定 `systemctl` 参数启动。

如果 GitHub 下载失败，任务会明确返回 URL 和错误原因；如果磁盘空间不足，任务会提示清理空间或调整 Agent 状态目录。可以配置代理、手动安装 EasyTier，或稍后重试。

## 组网成功判定

执行“验证组网”后，Agent 会固定调用：

- `systemctl is-active edge-tunnel-easytier.service`
- `easytier-cli node`
- `easytier-cli peer`
- `easytier-cli route`

面板会展示远端 Peer 数量、最佳延迟、丢包、隧道类型和路由类型。`peer_count > 0` 且路由为 `DIRECT` 或可用路径时，可认为 EasyTier peer 层已经连通。

## 公网入口

公网入口定义节点上的监听地址、端口范围、协议、域名和 DDNS 配置。

## 转发规则

- `target_mode=local`：入口节点本地或可直连地址。
- `target_mode=overlay`：通过 EasyTier overlay 到后端节点。

Agent 后续会根据结构化配置生成 nftables 规则，不接受 raw nftables payload。
