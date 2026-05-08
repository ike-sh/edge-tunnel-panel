# nftables 转发

v0.4 只管理本项目自己的表：

```text
table inet leikwan_forward
```

脚本不会 `flush ruleset`，也不会清空用户已有防火墙规则。

## cloud-entry

公网入口机 A 只配置一次入口端口池：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
```

生成的核心规则是：

```text
tcp dport 10000-19999 dnat ip to 10.198.1.1
```

注意这里不指定 DNAT 目标端口，因此会保持原始端口：

```text
A_PUBLIC_HOST:10001 -> 10.198.1.1:10001
A_PUBLIC_HOST:10002 -> 10.198.1.1:10002
```

A 不需要读取 `target_host`，也不需要为每个后端重复导入转发码。

## leikwan-relay

B 利群中转机负责所有后端目标：

```bash
sudo lq forward add
sudo lq forward edit service-a
sudo lq forward delete service-a
sudo lq forward apply-relay
```

B 侧根据 `forwards.tsv` 生成每个后端的 DNAT：

```text
10.198.1.1:ENTRY_PORT -> TARGET_HOST:TARGET_PORT
```

如果 `TARGET_HOST` 是域名，会先解析为 IPv4 并写入：

```text
/etc/leikwan-wg-toolkit/forwards/resolved.tsv
```

## TCP MSS clamp

EasyTier/tun 叠加 A/B 两侧 NAT 时，部分后端 TCP 协议会遇到 MTU/MSS 问题，表现为：

- 后端直连成功。
- 经 A -> EasyTier -> B 转发后有延迟、有握手迹象，但应用层连接失败。

脚本默认在 A 和 B 的 `leikwan_forward` 表中加入：

```text
tcp flags syn tcp option maxseg size set 1320
```

该规则位于 `forward` hook，随 `/etc/leikwan-wg-toolkit/nft/leikwan-forward.nft` 和 `leikwan-nft-forward.service` 持久化，不需要手工创建临时 `lq_mss` 表。

默认 MSS clamp 是 `1320`。如仍不稳定，可降到 `1280` 或故障兜底值 `1200`：

```bash
sudo install -d -m 700 /etc/leikwan-wg-toolkit/nft
printf 'TCP_MSS_CLAMP=1280\nENABLE_MSS_CLAMP=true\n' | sudo tee /etc/leikwan-wg-toolkit/nft/mss.env >/dev/null
```

也可以临时用环境变量覆盖：

```bash
sudo env LEIKWAN_TCP_MSS_CLAMP=1200 lq forward apply-relay
```

## ip_forward

A 和 B 都需要：

```text
net.ipv4.ip_forward=1
```

脚本写入独立文件：

```text
/etc/sysctl.d/99-leikwan-forward.conf
```
