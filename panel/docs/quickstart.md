# 快速开始

## 安装主控

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.2.5-test
```

打开 `http://服务器IP:18080`。

## 添加节点

进入“节点”页面，点击“添加节点”。面板会创建一张“新节点接入”卡片，默认启用任务轮询和写入动作。通常只需要填写节点名称，然后点击“获取一键安装命令”，复制 root 命令到被控服务器执行。

## 快速组网

1. 至少接入两个在线节点。
2. 进入“组网配置”。
3. 在“快速组网”里选择公网入口节点和后端节点。
4. 保持默认端口 `11010` 和协议 `tcp+udp`。
5. 点击“创建并应用组网”。
6. 面板会创建一个组网卡片，并下发入口节点和后端节点两个 `apply_network_profile` 任务。
7. 等待 10~20 秒后点击“验证组网”。
8. 组网卡片应显示 Peer、延迟、丢包、隧道和路由。

## 创建转发规则

1. 确认后端节点已有 EasyTier 虚拟 IP。
2. 进入“转发规则”。
3. 选择一条已经显示“组网成功”的组网链路。
4. 只填写公网监听端口、后端落地端口和协议。
5. 目标 IP 默认自动使用组网链路中后端节点的虚拟 IP，并自动去掉 CIDR。
6. 点击“创建并应用转发”。
7. 到“任务”页面查看 `apply_forward_config` 和 `verify_forward_rules` 结果。

## 排障入口

- 节点页：“节点预检”“验证 EasyTier 状态”“验证组网”。
- 任务页：按节点、失败状态或 EasyTier 相关任务筛选。
- 服务器命令：`systemctl status edge-tunnel-easytier --no-pager`、`easytier-cli peer`、`easytier-cli route`。
