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
sudo lq forward edit hk
sudo lq forward delete hk
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

## ip_forward

A 和 B 都需要：

```text
net.ipv4.ip_forward=1
```

脚本写入独立文件：

```text
/etc/sysctl.d/99-leikwan-forward.conf
```
