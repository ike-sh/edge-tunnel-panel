# 网络与转发

## 快速组网

主流程是“快速组网”：选择一个公网入口节点和一个后端节点，面板自动生成入口 listeners 和后端 peers。

- 入口节点：监听 `tcp://0.0.0.0:11010`、`udp://0.0.0.0:11010`，peers 为空。
- 后端节点：listeners 保持默认，peers 指向入口公网 IP。
- 两端使用同一组 `network_name`、`network_secret` 和 CIDR。
- 创建后系统会自动等待约 20 秒并验证组网。

## EasyTier 虚拟 IP

Agent 生成的 EasyTier 启动参数包含 `-d` 和 `-i CIDR`，用于启用 DHCP/虚拟 IP。转发规则默认使用后端节点的 EasyTier 虚拟 IP 作为目标地址。

## 转发规则 MVP

`v0.2.6-test` 支持单端口 TCP/UDP 转发规则。链路是：外部客户端 -> 入口节点公网 IP:公网监听端口 -> 入口节点 nftables DNAT/SNAT -> EasyTier -> 后端落地地址:后端落地端口 -> 后端服务。

后端落地地址来源：

- `backend_easytier_ip`：默认，使用后端 EasyTier 虚拟 IP。
- `backend_private_ip`：使用后端节点上报的第一个内网 IP。
- `manual`：手动填写目标地址。Controller 可保存 IPv4 或域名；Agent 当前 nftables 落地只支持 IPv4。

点击“创建并应用转发”时，Controller 会创建规则并只向入口节点下发 `apply_forward_config` 任务。Agent 会写入：

- `/etc/edge-tunnel/agent/forward.json`
- `/etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft`

Agent 使用固定 argv 执行：

```bash
nft -c -f /etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft
nft -f /etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft
```

不支持 raw nft payload。

## 预检和诊断

`apply_forward_config` 会做以下检查：

- 后端落地地址必须是 IPv4 Host，不能带 CIDR。
- 公网监听端口不能已有进程监听。
- 已有 nft table 中不能存在相同监听端口规则。
- `nft -c` 必须通过才会加载规则。

失败时任务页会显示 `nft_check_stderr`、`nft_content`、监听端口、目标地址和目标端口。

## 真实转发测试

后端节点启动测试服务：

```bash
python3 -m http.server 8080 --bind 0.0.0.0
```

面板创建转发规则：选择组网链路 `edge-net`，公网监听端口 `18081`，后端落地端口 `8080`，目标地址默认使用后端虚拟 IP。

入口节点检查：

```bash
nft list table inet edge_tunnel_forward
cat /proc/sys/net/ipv4/ip_forward
```

外部客户端测试：

```bash
curl -v http://入口公网IP:18081/
```
