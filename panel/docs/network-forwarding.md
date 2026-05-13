# Network Forwarding

v0.2.10-test 的转发链路：

```text
外部客户端
-> A 公网服务器公网端口
-> A nftables
-> EasyTier 隧道或 B 公网直连
-> B 节点
-> B nftables
-> 落地服务器 IP/域名:端口
```

## 转发规则

用户只需要填写：

- 组网链路
- 公网监听端口
- 落地服务器 IP/域名
- 落地服务器端口
- 协议 TCP / UDP / TCP+UDP
- A 到 B 的传输方式：EasyTier 隧道或 B 公网直连

Controller 会自动创建两侧任务：

- A 侧：`apply_entry_forward_config`
- B 侧：`apply_landing_forward_config`

## nftables

A 侧表：

```bash
nft list table ip edge_tunnel_entry_forward
```

B 侧表：

```bash
nft list table ip edge_tunnel_landing_forward
```

v0.2.8-test 起模板使用 `table ip`、numeric priority 和 `dnat to IP:PORT`，不再生成 output chain。

## MSS clamp

v0.2.10-test 默认启用 MSS clamp，单独渲染到：

```bash
nft list table ip edge_tunnel_mss
```

默认 MTU 为 `1380`，自动模式优先使用 `rt mtu`，不支持时可回退到固定 MSS。
