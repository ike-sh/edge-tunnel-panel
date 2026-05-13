# 网络与转发

`v0.2.7-test` 把组网和转发拆成两个清晰阶段。

## 组网阶段

```text
A 公网入口节点
<-> EasyTier
<-> B 落地执行节点
```

快速组网会自动生成：

- A 侧 listeners。
- B 侧 peers。
- 同一组网络名、网络密钥和 CIDR。
- 两个 `apply_network_profile` 任务。

## 转发阶段

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
- A 到 B 的传输方式。

## A 侧入口转发

任务：`apply_entry_forward_config`

路径：

```text
/etc/edge-tunnel/agent/forwards.d/{rule_id}-entry.json
/etc/edge-tunnel/agent/nftables/edge-tunnel-entry-forward.nft
```

作用：公网监听端口转发到 B 节点的 EasyTier IP 或公网 IP。

## B 侧落地转发

任务：`apply_landing_forward_config`

路径：

```text
/etc/edge-tunnel/agent/forwards.d/{rule_id}-landing.json
/etc/edge-tunnel/agent/nftables/edge-tunnel-landing-forward.nft
```

作用：B 内部端口转发到落地服务器 IP/域名:端口。

如果落地服务器地址是域名，B Agent 会解析为 IPv4 后写入 nftables。IPv6 落地目标暂不支持。

## nftables 预检

Agent 会执行固定 argv：

```bash
nft -c -f /etc/edge-tunnel/agent/nftables/edge-tunnel-entry-forward.nft
nft -f /etc/edge-tunnel/agent/nftables/edge-tunnel-entry-forward.nft
nft -c -f /etc/edge-tunnel/agent/nftables/edge-tunnel-landing-forward.nft
nft -f /etc/edge-tunnel/agent/nftables/edge-tunnel-landing-forward.nft
```

失败时任务页会展示 `nft_check_stderr` 和 `nft_content`。

## 真实测试

落地服务器：

```bash
python3 -m http.server 8080 --bind 0.0.0.0
```

面板：

```text
组网链路：edge-net
公网监听端口：18081
落地服务器地址：1.2.3.4 或 backend.example.com
落地服务器端口：8080
```

外部访问：

```bash
curl -v http://入口公网IP:18081/
```
