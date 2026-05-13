# 转发规则

v0.3.1-test 的转发链路：

```text
外部用户 -> A 公网入口 -> A nftables -> EasyTier 或 B 公网/专线直连 -> B nftables -> 落地服务器 IP/域名:端口
```

## EasyTier 模式

A 侧转发到 B 的 EasyTier 虚拟 IP，中继端口默认等于公网监听端口。

## 直连模式

A 侧转发到组网链路中填写的 B 可达地址。适合前海 IX、IPLC、公网互通或内网专线互通。

## 启用 / 停用

启用会重新下发 A/B 两侧 nftables。停用会删除对应的入口/落地 nftables 表。当前 MVP 仍建议同一节点同一阶段只保留一条 active 转发规则。

## 排查

```bash
nft list table ip edge_tunnel_entry_forward
nft list table ip edge_tunnel_landing_forward
cat /proc/sys/net/ipv4/ip_forward
```
