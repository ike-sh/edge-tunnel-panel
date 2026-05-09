# IPv4 多出口策略路由 / PBR

PBR 用来把指定后端 IPv4 固定到某个出口线路，例如 `T_CN2` 或 `T_9929`。它只处理 IPv4，不接管整机默认路由。

菜单：

```text
IPv4 多出口策略路由 / PBR
1. 添加静态 PBR
2. 从现有转发目标添加 PBR
3. 删除 PBR 规则
4. 应用 PBR
5. 查看 PBR
6. 返回
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

## 删除 PBR 规则

使用第 3 项删除规则。脚本会先展示当前 PBR 规则列表：

```text
编号  目标网段                 路由表      来源
1. 203.0.113.107/32         T_CN2      static
2. 203.0.113.154/32         T_CN2      static
3. 198.51.100.158/32        T_CN2      forward:Hinet tw.example.com
```

可以输入编号、完整 CIDR，或裸 IP。裸 IP 会按 `/32` 匹配。删除前会确认，确认后从 `static-routes.conf` 删除对应行并重新应用 PBR。

如果规则来自 DDNS / forward，删除的是当前解析 IP 对应的 PBR 记录。若同一 CIDR 有多条不同路由表规则，按 CIDR 输入会要求改用编号，避免误删其他线路。

也可以使用 CLI：

```bash
sudo lq pbr delete 203.0.113.154/32
sudo lq --pbr-delete 203.0.113.154
```

## 配置文件

```text
/etc/leikwan-toolkit/pbr/static-routes.conf
```

普通静态规则格式：

```text
203.0.113.10/32 CN2
203.0.113.10/32 CN2 static
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
