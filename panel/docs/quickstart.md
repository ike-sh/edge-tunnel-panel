# 快速开始

1. 安装 Controller：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | bash -s -- --version v0.3.1
```

2. 打开 Web：`http://服务器公网IP:18080`。
3. 进入“节点”，生成 Agent 一键命令。大陆机器可选择“国内加速轮询”，命令会携带 `EDGE_GITHUB_MIRRORS`。
4. 进入“组网链路”：
   - EasyTier 链路：A/B 无直接可达时使用。
   - 直连链路：前海 IX、IPLC、公网或专线互通时使用。
5. 进入“转发规则”，选择链路，填写公网监听端口、落地服务器 IP/域名、落地端口，创建并应用。
6. 如 B 节点需要多出口，进入“出口策略 / PBR”，先识别出口线路，再选择线路组应用策略。
7. 出现问题时进入“诊断”，运行一键诊断并复制 Markdown 报告。

## 卸载

Controller：`--uninstall` 保留数据，`--purge` 彻底删除。
Agent：`--uninstall` 保留配置，`--purge` 删除 Agent 配置和 EasyTier service/config，`--remove-easytier-binaries` 额外删除 easytier-core/easytier-cli。
