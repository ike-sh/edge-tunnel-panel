# Edge Tunnel Panel

Edge Tunnel Panel 是一个基于 EasyTier 的 TCP/UDP 隧道组网 Web 面板，用于把没有公网 IPv4 的 NAT 后服务器接入公网入口节点，并通过固定 Agent action 管理组网、转发、任务和状态。

当前版本：`v0.2.7-test`

## 适用场景

- 被控服务器没有公网 IPv4，只能主动连接外部服务。
- 服务器只有 SSH NAT 端口，业务端口无法直接暴露。
- 需要一台公网服务器作为 A 入口节点。
- 需要通过 EasyTier 把 A 公网入口节点与 B 落地执行节点组网。
- 需要把公网端口转发到 B 节点后面的落地服务器 IP/域名和端口。

## 架构

- **Controller**：Go HTTP API、JSON 文件存储、任务下发、Web 静态文件服务。
- **Agent**：安装在节点上，主动注册、心跳上报、轮询固定 action 任务。
- **Web**：React + Vite 面板，默认中文界面。
- **EasyTier**：负责 A 与 B 之间的 overlay 组网。
- **nftables**：Agent 结构化生成 A/B 两侧转发规则，不接受 raw nft。

## 快速安装 Controller

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.2.7-test
```

安装完成后打开：

```text
http://服务器IP:18080
```

测试版默认不强制 Web Operator Token。生产环境可启用严格鉴权。

## 添加节点

1. 打开 Web，进入“节点”。
2. 点击“添加节点”。
3. 在“新节点接入”卡片里填写节点名称。
4. 点击“获取一键安装命令”。
5. root 登录服务器时复制 root 命令；普通用户复制 sudo 命令。
6. 执行完成后回到“节点”页面，等待 30 秒或点击刷新。

示例命令：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- \
  --version v0.2.7-test \
  --controller-url http://YOUR_CONTROLLER:18080 \
  --token YOUR_AGENT_TOKEN \
  --node-name edge-node-1 \
  --enable-tasks \
  --enable-write-actions
```

节点用途不再由“角色”字段决定，而是在组网和转发流程中选择 A 入口节点、B 落地执行节点。

## 快速组网

1. 确认至少两个节点在线。
2. 进入“组网配置”。
3. 使用“快速组网”选择 A 公网入口节点和 B 落地执行节点。
4. 面板自动生成同一组 `network_name`、`network_secret`、CIDR、listeners 和 peers。
5. 入口节点 listeners 默认是 `tcp://0.0.0.0:11010` 和 `udp://0.0.0.0:11010`，peers 为空。
6. 后端节点 peers 自动指向入口公网 IP，例如 `tcp://入口公网IP:11010` 和 `udp://入口公网IP:11010`。
7. Controller 创建两个 `apply_network_profile` 任务，并生成一张组网卡片。
8. 系统会在约 20 秒后自动验证；组网卡片会显示“组网成功 / 组网失败”。

## 转发规则 MVP

`v0.2.7-test` 的转发模型是双阶段：

```text
外部客户端
-> A 公网服务器公网端口
-> A nftables
-> EasyTier 隧道或 B 公网直连
-> B 节点
-> B nftables
-> 落地服务器 IP/域名:端口
```

用户只需要填写：

- 组网链路。
- 公网监听端口。
- 落地服务器 IP/域名。
- 落地服务器端口。
- 协议 TCP / UDP / TCP+UDP。
- A 到 B 的传输方式：EasyTier 隧道或 B 公网直连。

点击“创建并应用转发”后，Controller 会创建两个任务：

- `apply_entry_forward_config`：运行在 A 公网入口节点，把公网端口转发到 B。
- `apply_landing_forward_config`：运行在 B 落地执行节点，把内部端口转发到落地服务器 IP/域名:端口。

A/B 两侧会分别写入：

```text
/etc/edge-tunnel/agent/forwards.d/{rule_id}-entry.json
/etc/edge-tunnel/agent/forwards.d/{rule_id}-landing.json
/etc/edge-tunnel/agent/nftables/edge-tunnel-entry-forward.nft
/etc/edge-tunnel/agent/nftables/edge-tunnel-landing-forward.nft
```

B 侧支持把落地域名解析为 IPv4 后写入 nftables。IPv6 落地目标暂不支持。

真实测试示例：

```bash
# 落地服务器
python3 -m http.server 8080 --bind 0.0.0.0

# A/B 节点检查
nft list table inet edge_tunnel_entry_forward
nft list table inet edge_tunnel_landing_forward
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
VERSION=v0.2.7-test bash panel/scripts/build-release.sh
```
