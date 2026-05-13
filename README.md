# Edge Tunnel Panel

Edge Tunnel Panel 是一个基于 EasyTier 的 TCP/UDP 隧道组网 Web 面板，用于把没有公网 IPv4 的 NAT 后服务器接入公网入口节点，并在主控面板里管理节点、组网、转发、出口策略、DDNS 和任务。

当前版本：`v0.1.6-test`

## 典型场景

- 被控服务器没有公网 IPv4。
- 服务器只有 SSH NAT 端口，无法直接暴露业务端口。
- 需要一台公网服务器作为入口节点。
- 需要单节点直接转发，或多节点通过 EasyTier 隧道转发。

## 架构

- **Controller**：主控 API、JSON 存储、任务下发、Web 静态文件服务。
- **Agent**：安装在被控节点，主动注册、上报状态、轮询固定任务。
- **Web**：浏览器面板，默认中文，提供“添加节点”一键命令入口。
- **EasyTier**：节点间 overlay 组网。
- **nftables**：结构化生成 TCP/UDP 转发规则。
- **PBR**：结构化生成 Linux 出口策略。
- **DDNS**：作为节点/公网入口的内置配置能力。

## 快速安装 Controller

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.1.6-test
```

安装完成后打开：

```text
http://服务器IP:18080
```

## 添加节点

1. 打开 Web，保存安装输出中的 Operator Token。
2. 进入“节点”页面，点击“添加节点”。
3. 填写 Controller 地址、节点名称、角色和版本。
4. 点击“生成一键命令”。
5. 复制命令到被控服务器执行。
6. 回到“节点”页面刷新，查看在线状态。

示例命令：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | sudo bash -s -- \
  --version v0.1.6-test \
  --controller-url http://YOUR_CONTROLLER:18080 \
  --token YOUR_AGENT_TOKEN \
  --node-name edge-node-1 \
  --role backend \
  --enable-tasks \
  --enable-write-actions
```

## 组网配置

1. 确认节点已上线。
2. 进入“组网配置”。
3. 创建组网配置，填写名称、网络名、CIDR、协议偏好和可选 peers/listeners。
4. 在配置卡片中选择目标节点，点击“应用到节点”。
5. 进入“任务”页面查看 `apply_network_profile` 结果。
6. ???????? `curl`/`wget`/`unzip`????????????????????? EasyTier ????
7. 回到“节点”页面刷新，查看 EasyTier 状态。

## 卸载

Controller 保留数据卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- --uninstall
```

Controller 彻底删除：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- --purge
```

Agent 保留数据卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | sudo bash -s -- --uninstall
```

Agent 彻底删除：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | sudo bash -s -- --purge
```

## 安全边界

- Agent 不接受任意 shell 命令。
- Agent 只执行固定 action。
- 拒绝危险字段：`command`、`cmd`、`shell`、`script`、`raw_nft`、`raw_iptables`、`raw_ip_route`。
- Token 会在任务输出和错误中 redaction。
- 写入动作需要显式启用 `EDGE_ENABLE_WRITE_ACTIONS=true`。

## 当前限制

- `v0.1.6-test` 是测试版。
- EasyTier 自动下载/安装后续增强。
- DDNS provider 后续增强。
- PBR 需要 root 权限和 Linux `nftables` / `iproute2`。

## 后续规划

参考成熟转发面板的设计思路，后续计划增强：

- 节点管理体验增强。
- 隧道/转发规则管理。
- 端口转发 / 隧道转发两种模式。
- 转发规则批量启停。
- 节点批量下发。
- TCP/UDP 转发状态检查。
- 隧道/转发流量统计。
- 转发规则分组。
- 节点分组。
- 分组权限。
- 限速/配额。
- 节点分享或多面板对接。
- 动态最优路径。

## 开发验证

```bash
cd panel/controller && go test ./... -v -count=1 -timeout=30s
cd ../agent && go test ./... -v -count=1 -timeout=30s
cd ../..
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build
VERSION=v0.1.6-test bash panel/scripts/build-release.sh
```
