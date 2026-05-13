# 网络转发

## 组网配置

`v0.2.0-test` 已支持把组网配置下发到节点：

- Controller 创建 `apply_network_profile` 任务。
- 任务 payload 包含完整 `network_profile` 和目标 `node`。
- Agent 写入 `/etc/edge-tunnel/agent/network-profile.json`。
- Agent 写入 `/etc/edge-tunnel/agent/easytier.toml`。
- Agent 在缺少 `easytier-core` 时尝试自动安装 EasyTier v2.4.5。
- Agent 使用 Go 内置 zip 解压，不依赖系统 `unzip`。
- Agent 生成 `edge-tunnel-easytier.service`，并用固定 `systemctl` 参数启动。

如果 GitHub 下载失败，任务会明确返回 URL 和错误原因；如果磁盘空间不足，任务会提示清理空间或调整 Agent 状态目录。可以配置代理、手动安装 EasyTier，或稍后重试。

## 公网入口

公网入口定义节点上的监听地址、端口范围、协议、域名和 DDNS 配置。

## 转发规则

- `target_mode=local`：入口节点本地或可直连地址。
- `target_mode=overlay`：通过 EasyTier overlay 到后端节点。

Agent 后续会根据结构化配置生成 nftables 规则，不接受 raw nftables payload。
