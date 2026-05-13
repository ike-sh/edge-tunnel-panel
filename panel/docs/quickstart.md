# 快速开始

## 安装主控

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.2.2-test
```

打开 `http://服务器IP:18080`。

## 添加节点

进入 Web 的“节点”页面，点击“添加节点”，生成一键 Agent 命令，复制到被控服务器执行。

## 快速组网

1. 确认节点已上线。
2. 进入“组网配置”。
3. 在“快速组网”里选择公网入口节点和后端节点。
4. 监听端口默认 `11010`，协议默认 `tcp+udp`。
5. 点击“创建并应用组网”。
6. Controller 会自动创建入口节点和后端节点两个 `apply_network_profile` 任务。
7. 到“任务”页面按节点筛选查看结果。
8. 如果提示下载失败或磁盘空间不足，请按任务页提示处理后重试。
9. 回到“节点”页面刷新查看 EasyTier 状态和 Peer 数量。

入口节点 peers 会自动留空；后端节点 peers 会自动指向入口公网 IP 的 `11010/tcp` 和 `11010/udp`。

## 验证组网成功

快速组网任务完成后等待 10~20 秒，回到“节点”页面打开“节点操作”，点击“验证组网”。

成功时面板会显示：

- 组网状态：组网成功
- Peer 数量大于 0
- 延迟，例如 `146.8 ms`
- 丢包，例如 `0.0%`
- 隧道，例如 `udp,tcp`
- 路由，例如 `DIRECT`

命令行可用 `easytier-cli peer` 和 `easytier-cli route` 辅助确认。

## 节点预检

节点上线后可在“节点”页面打开“节点操作”，先执行“节点预检”。预检会检查 root、磁盘空间、系统命令、EasyTier 二进制、systemd 目录和 Controller 连通性。

## 删除测试节点

节点卡片的“危险操作”里可以删除节点记录。这个操作只删除主控面板记录，不会卸载远端 Agent。需要卸载时请到对应服务器执行 `install-agent.sh --purge`。
