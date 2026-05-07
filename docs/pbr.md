# IPv4 多出口策略路由 / PBR

PBR 用于让指定目标 IP/CIDR 走指定利群出口线路，不接管整机默认路由。

## 配置

静态规则：

```text
/etc/leikwan-wg-toolkit/pbr/static-routes.conf
```

格式：

```text
203.0.113.30/32 CN2
198.51.100.20/32 9929
```

优先级：

```text
15000
```

## 应用

```bash
sudo lq --pbr-apply
```

菜单：

```text
高级功能 -> IPv4 多出口策略路由
```

## 与 forwards.tsv 的关系

`forwards.tsv` 可以给每个 target 填写 `route_table`，例如：

```text
T_CN2
T_9929
```

nftables 负责四层转发，PBR 负责目标出口选择。PBR 不会删除非本项目创建的规则，也不会改系统默认网关。

## 回滚

删除 `static-routes.conf` 中对应行后重新执行：

```bash
sudo lq --pbr-apply
```

如需完全清理，请使用卸载菜单中的项目规则清理流程。
