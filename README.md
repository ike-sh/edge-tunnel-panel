# Edge Tunnel Panel

当前版本：`v0.2.9-test`

Edge Tunnel Panel 是一个基于 EasyTier 的 TCP/UDP 隧道组网与转发管理面板。它面向没有公网 IPv4 的 NAT 后服务器，通过公网入口节点、EasyTier 隧道、nftables 转发和 PBR 出口策略，把外部访问转发到指定落地服务器。

## 典型链路

```text
外部客户端
-> A 公网服务器公网端口
-> A nftables
-> EasyTier 隧道或 B 公网直连
-> B 节点
-> B nftables
-> 落地服务器 IP/域名:端口
```

## 快速开始

安装 Controller：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.2.9-test
```

打开 Web：

```text
http://服务器IP:18080
```

在“节点”页面点击“添加节点”，生成 Agent 一键命令并复制到被控服务器执行。

## 推荐流程

1. 添加 A 公网入口节点和 B 落地执行节点。
2. 进入“组网配置”，使用快速组网选择 A 和 B。
3. 等待组网卡片显示“组网成功”。
4. 进入“转发规则”，选择组网链路。
5. 填写公网监听端口、落地服务器 IP/域名、落地服务器端口和协议。
6. 点击“创建并应用转发”。
7. 如需指定 B 节点出口线路，进入“出口策略 / PBR”。
8. 识别网卡，选择转发规则、出口接口和网关，创建并应用策略。

## 转发 MVP

转发规则会生成两阶段任务：

- `apply_entry_forward_config`：运行在 A 节点，把公网端口转发到 B。
- `apply_landing_forward_config`：运行在 B 节点，把内部端口转发到落地服务器。

当前 nftables 模板使用：

- `table ip edge_tunnel_entry_forward`
- `table ip edge_tunnel_landing_forward`
- numeric priority：`-100` / `100`
- `dnat to IP:PORT`
- 不生成 output chain

## 出口策略 / PBR

PBR 用于 B 落地执行节点上的转发流量出口选择，适合多网卡、多公网 IP、CN2/9929/普通线路切换等场景。

v0.2.9-test 的限制：

- 每个节点只允许一条启用中的 PBR 策略。
- 完整支持 `source_type=forward`。
- `domain` / `static` 已保留模型，后续接入 DDNS/domain sync。
- 不支持 IPv6 PBR。
- 不接受任意 shell、命令字符串或 raw nft/raw route。

PBR 会结构化生成：

- `/etc/edge-tunnel/agent/pbr.d/{policy_id}.json`
- `/etc/edge-tunnel/agent/nftables/edge-tunnel-pbr.nft`
- `ip rule` / `ip route table`

## MTU / MSS clamp

EasyTier、tun、多层 NAT 和转发场景下，TCP 可能因为 MTU/MSS 不合适出现卡顿、部分网页打不开或大包异常。

v0.2.9-test 默认：

- MTU：`1380`
- MSS clamp：启用
- MSS 模式：`auto`

可在组网高级参数中调整为：

- `auto`：优先使用 `rt mtu`
- `fixed`：固定 MSS 值，未填写时按 `MTU - 40`
- `disabled`：不生成 MSS clamp

## 常用验证

A 节点：

```bash
nft list table ip edge_tunnel_entry_forward
cat /proc/sys/net/ipv4/ip_forward
```

B 节点：

```bash
nft list table ip edge_tunnel_landing_forward
nft list table ip edge_tunnel_pbr
ip rule show
ip route show table 20000
cat /proc/sys/net/ipv4/ip_forward
```

落地服务测试：

```bash
python3 -m http.server 8080 --bind 0.0.0.0
curl -v http://A公网IP:18081/
```

## 安全边界

- Agent 不接受任意 shell。
- 只执行固定 action。
- payload 中拒绝危险字段。
- token 和任务输出会做 redaction 与长度限制。
- 所有 nft/ip/systemctl 操作使用固定 argv。

## 开发验证

```bash
cd panel/controller && go test ./... -v -count=1 -timeout=30s
cd ../agent && go test ./... -v -count=1 -timeout=30s
cd ../..
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build
VERSION=v0.2.9-test bash panel/scripts/build-release.sh
```
