# 快速开始

## 安装主控

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.1.9-test
```

打开 `http://服务器IP:18080`。

## 添加节点

进入 Web 的“节点”页面，点击“添加节点”，生成一键 Agent 命令，复制到被控服务器执行。

## 创建并应用组网配置

1. 确认节点已上线。
2. 进入“组网配置”。
3. 创建组网配置。
4. 在配置卡片中选择目标节点。
5. 点击“应用到节点”。
6. 到“任务”页面查看 `apply_network_profile` 结果。
7. 如果提示下载失败或磁盘空间不足，请按任务页提示处理后重试。
8. 回到“节点”页面刷新查看 EasyTier 状态。

## 节点预检

节点上线后可在“节点”页面打开“节点操作”，先执行“节点预检”。预检会检查 root、磁盘空间、系统命令、EasyTier 二进制、systemd 目录和 Controller 连通性。

## 删除测试节点

节点卡片的“危险操作”里可以删除节点记录。这个操作只删除主控面板记录，不会卸载远端 Agent。需要卸载时请到对应服务器执行 `install-agent.sh --purge`。
