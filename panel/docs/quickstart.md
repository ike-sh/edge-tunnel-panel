# 快速开始

## 安装主控

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.1.4-test
```

打开 `http://服务器IP:18080`，保存安装输出中的 Operator Token。

## 添加节点

进入 Web 的“节点”页面，点击“添加节点”，生成一键 Agent 命令，复制到被控服务器执行。

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | sudo bash -s -- \
  --version v0.1.4-test \
  --controller-url http://YOUR_CONTROLLER:18080 \
  --token YOUR_AGENT_TOKEN \
  --node-name edge-node-1 \
  --role backend \
  --enable-tasks \
  --enable-write-actions
```

执行后回到“节点”页面刷新，确认节点在线。

## 第一次配置

1. 创建“组网配置”。
2. 应用到目标节点。
3. 创建“公网入口”。
4. 创建“转发规则”。
5. 在“任务”页面查看执行结果。
