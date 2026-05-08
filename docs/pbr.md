# IPv4 多出口策略路由 / PBR

PBR 用来把指定 IPv4 或 CIDR 目标固定走某个出口线路，例如 `T_CN2` 或 `T_9929`。它只影响你指定的目标，不接管整机默认路由。

## 添加静态规则

推荐使用菜单：

```text
高级功能 -> IPv4 多出口策略路由 / PBR -> 添加静态 PBR
```

目标必须是合法 IPv4 或 CIDR：

```text
203.0.113.30
203.0.113.0/24
```

单个 IPv4 会自动转为 `/32`。非法输入会被拒绝，例如：

```text
123456
abc
999.1.1.1
203.0.113.10/99
```

线路组使用选择式菜单：

```text
1. CN2 -> T_CN2
2. 9929 -> T_9929
3. 自定义路由表
0. 返回
```

脚本不会让普通用户裸输线路组，避免输错后写入坏规则。

## 配置文件

静态规则保存在：

```text
/etc/leikwan-wg-toolkit/pbr/static-routes.conf
```

格式：

```text
203.0.113.30/32 CN2
198.51.100.20/32 9929
```

项目使用 priority `15000`。历史配置里如果有坏目标，`--pbr-apply` 会跳过并输出 WARN，不会因为 `ip route` 报错退出。

## 应用规则

```bash
sudo lq --pbr-apply
```

如果需要非交互自动修正转发目标出口，可执行：

```bash
sudo lq forward apply-relay --auto-fix-route
```

## 与转发目标的关系

B 利群中转机执行 `lq forward add` / `lq forward edit` / `lq forward apply-relay` 时，脚本会自动执行：

```bash
ip route get TARGET_IP
```

并解析实际出口，例如：

```text
203.0.113.30 via 10.8.0.1 dev eth1 table T_CN2 src 10.8.1.42
```

此时会推荐写入：

```text
out_iface=eth1
route_table=T_CN2
```

如果 `forwards.tsv` 里误写为 `eth0/-`，但实际路由是 `eth1/T_CN2`，`lq forward apply-relay` 会在应用 nftables 前提示自动修正。这样可以避免 A 端口能到 B，但 B 转后端超时。

## 排错

如果外部访问入口端口无延迟、无响应，先在 B 上检查：

```bash
ip route get <TARGET_IP>
nft list table inet leikwan_forward
sudo lq --doctor
```

确认 nftables 里的 `oifname` 是否和 `ip route get` 的 `dev` 一致。脚本的 doctor 会输出：

```text
[OK] 转发目标 hk 出口一致：eth1 / T_CN2
```

或：

```text
[WARN] 转发目标 hk 出口不一致：配置 eth0/-，实际 eth1/T_CN2，可能导致节点无延迟/无法连接。
```
