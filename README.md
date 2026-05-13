# Edge Tunnel Panel

Edge Tunnel Panel 是一个基于 EasyTier 的 TCP/UDP 隧道组网 Web 面板，用于把没有公网 IPv4 的 NAT 后服务器接入公网入口节点，并在主控面板里管理节点、组网、转发规则、任务和状态。

当前版本：`v0.2.4-test`

## 适用场景

- 被控服务器没有公网 IPv4，只能主动连接外部服务。
- 服务器只有 SSH NAT 端口，业务端口无法直接暴露。
- 需要一台公网服务器作为入口节点，把请求转发到后端节点。
- 需要先通过 EasyTier 建立入口节点和后端节点之间的 overlay 网络。
- 需要从 Web 面板查看节点在线状态、Peer、延迟、丢包、隧道和路由。

## 架构

- **Controller**：Go HTTP API、JSON 文件存储、任务下发、Web 静态文件服务。
- **Agent**：安装在节点上，主动注册、心跳上报、轮询固定 action 任务。
- **Web**：React + Vite 面板，默认中文界面。
- **EasyTier**：负责入口节点和后端节点之间的 overlay 组网。
- **nftables**：第一版转发规则由 Agent 结构化生成，不接受 raw nft。

## 快速安装 Controller

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.2.4-test
```

安装完成后打开：

```text
http://服务器IP:18080
```

测试版默认不强制 Web Operator Token。生产环境可启用严格鉴权。

## 添加节点

1. 打开 Web，进入“节点”。
2. 点击“添加节点”。
3. 面板会显示一张“新节点接入”卡片。
4. 通常只需要修改节点名称，然后点击“获取一键安装命令”。
5. 复制 root 命令到被控服务器执行。
6. 执行完成后回到“节点”页面，等待 30 秒或点击刷新。

示例命令：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- \
  --version v0.2.4-test \
  --controller-url http://YOUR_CONTROLLER:18080 \
  --token YOUR_AGENT_TOKEN \
  --node-name edge-node-1 \
  --enable-tasks \
  --enable-write-actions
```

节点用途不再由“角色”字段决定，而是在组网和转发流程中选择入口节点、后端节点。

## 快速组网

1. 确认至少两个节点在线。
2. 进入“组网配置”。
3. 使用“快速组网”选择一个公网入口节点和一个后端节点。
4. 面板自动生成同一组 `network_name`、`network_secret`、CIDR、listeners 和 peers。
5. 入口节点 listeners 默认是 `tcp://0.0.0.0:11010` 和 `udp://0.0.0.0:11010`，peers 为空。
6. 后端节点 peers 自动指向入口公网 IP：`tcp://入口公网IP:11010`、`udp://入口公网IP:11010`。
7. Controller 创建两个 `apply_network_profile` 任务，并生成一张组网卡片。
8. 等待 10~20 秒后点击“验证组网”，或到“任务”页面查看结果。

组网卡片会展示入口节点、后端节点、Peer 数量、延迟、丢包、隧道、路由和状态。

## EasyTier 虚拟 IP

`v0.2.4-test` 生成的 EasyTier systemd 启动参数默认包含：

```text
-d -i 10.144.0.0/16
```

`-d` 用于启用 DHCP/虚拟 IP，`-i` 指定虚拟网段。Agent 会解析 `easytier-cli node` 输出并上报虚拟 IP。若组网已成功但虚拟 IP 仍显示“未分配”，请重新应用组网配置或检查 EasyTier 版本兼容性。

## 转发规则 MVP

当前版本提供单端口 TCP/UDP 转发规则 MVP。产品链路是：外部客户端 -> 入口节点公网 IP:入口端口 -> 入口节点 nftables DNAT/SNAT -> 后端节点 EasyTier 虚拟 IP:目标端口 -> 后端服务。

1. 先完成快速组网并确认后端节点有 EasyTier 虚拟 IP。
2. 进入“转发规则”。
3. 创建规则：选择入口节点、后端节点、监听端口、目标端口和协议。
4. 默认目标 IP 使用后端节点的 EasyTier 虚拟 IP，并自动去掉 CIDR 前缀，例如 `10.144.0.2/16` 会作为 `10.144.0.2` 写入转发规则。
5. 点击“应用规则”，Controller 会在入口节点创建 `apply_forward_config` 任务。
6. Agent 写入 `/etc/edge-tunnel/agent/forward.json` 和 `/etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft`。
7. Agent 先执行 `nft -c -f` 语法检查，通过后再执行 `nft -f` 加载规则；如果检查失败，任务结果会展示 stderr 和生成的 nft 内容。
8. 可点击“验证规则”创建 `verify_forward_rules` 任务。

限制：第一版只支持单端口规则，不支持端口池、限速、计费或用户系统。
真实测试示例：

```bash
# 后端节点
python3 -m http.server 8080 --bind 0.0.0.0

# 入口节点检查
nft list table inet edge_tunnel_forward
cat /proc/sys/net/ipv4/ip_forward

# 外部客户端
curl -v http://入口公网IP:18081/
```

## 如何确认组网成功

- 节点页 EasyTier 状态为“运行中”。
- 组网状态为“组网成功”。
- Peer 数量大于 0。
- 延迟有数值，例如 `146.8 ms`。
- 丢包较低，例如 `0.0%`。
- 隧道显示 `udp,tcp` 或 `tcp,udp`。
- 路由显示 `DIRECT` 或可用路径。

命令行也可以在 Agent 服务器上验证：

```bash
easytier-cli peer
easytier-cli route
```

## 卸载

Controller 保留数据卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- --uninstall
```

Controller 彻底删除：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- --purge
```

Agent 彻底删除并清理 EasyTier service/config：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- --purge
```

如果要同时删除 `easytier-core` 和 `easytier-cli`：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- --purge --remove-easytier-binaries
```

## 安全边界

- Agent 不接受任意 `command`、`cmd`、`shell`、`script`。
- Agent 不接受 `raw_nft`、`raw_iptables`、`raw_ip_route`。
- 写入动作必须是固定 action 映射到固定 Go 函数和固定 argv。
- Token、任务输出和错误信息会做 redaction。
- 任务输出会限制大小。

## 开发验证

```bash
cd panel/controller && go test ./... -v -count=1 -timeout=30s
cd ../agent && go test ./... -v -count=1 -timeout=30s
cd ../..
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build
VERSION=v0.2.4-test bash panel/scripts/build-release.sh
```
