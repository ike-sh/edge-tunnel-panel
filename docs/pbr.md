# IPv4 多出口策略路由 / PBR

PBR 用来把指定后端 IPv4 固定到某个出口线路，例如 `T_CN2` 或 `T_9929`。它只处理 IPv4，不接管整机默认路由。

菜单：

```text
IPv4 多出口策略路由 / PBR
1. 添加静态 PBR
2. 从现有转发目标添加 PBR
3. 应用 PBR
4. 查看 PBR
0. 返回
```

## 静态 PBR

静态 PBR 只接受 IPv4 或 CIDR：

```text
203.0.113.10
203.0.113.0/24
```

如果输入域名，例如 `tw.example.com`，脚本会提示：

```text
[WARN] 静态 PBR 只接受 IPv4 或 CIDR。如果要给域名 / DDNS 添加 PBR，请选择“从现有转发目标添加 PBR”。
```

## 从转发目标添加 PBR

当后端是 DDNS / 域名时，使用第 2 项：

1. 脚本展示 enabled 转发目标列表。
2. 输入编号或名称。
3. 如果 `target_host` 是 IP，直接写入 `target_ip/32`。
4. 如果 `target_host` 是域名，先解析当前 IPv4，再写入 `resolved_ip/32`。
5. 选择线路组：`CN2 -> T_CN2`、`9929 -> T_9929` 或自定义路由表。

写入规则会记录来源转发名和 `target_host`。以后 `pbr_apply` 会重新解析来源域名；IP 变化时更新对应 PBR 规则。

## 配置文件

```text
/etc/leikwan-toolkit/pbr/static-routes.conf
```

普通静态规则格式：

```text
203.0.113.10/32 CN2
```

来自转发目标的动态规则格式：

```text
203.0.113.20/32 CN2 forward Hinet tw.example.com
```

## 与转发目标的关系

`lq forward apply-relay --auto-fix-route` 会同步 `forwards.tsv` 中的 `out_iface` 和 `route_table` 元数据。

- 实际出口接口和配置不一致时，脚本会 WARN，因为 nftables `oifname` 可能不匹配。
- 出口接口一致但 route_table 元数据不同，只提示 INFO；这通常不会单独导致转发失败。

应用：

```bash
sudo lq --pbr-apply
sudo lq forward apply-relay --auto-fix-route
```
