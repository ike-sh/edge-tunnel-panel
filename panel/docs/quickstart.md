# 快速开始

## 安装主控

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.1.5-test
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
7. 如果提示 `easytier-core not found`，先手动安装 EasyTier 或等待后续自动安装功能。
8. 回到“节点”页面刷新查看 EasyTier 状态。
