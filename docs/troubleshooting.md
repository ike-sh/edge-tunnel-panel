# 排错

v0.4.0-alpha 主线是 EasyTier 传输 + nftables 四层 TCP 转发。脚本不部署后端业务，只负责：

```text
client -> A 公网入口端口 -> EasyTier -> B 利群主机 -> 后端目标
```

## 安装失败

确认使用新仓库：

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
```

安装目标应为：

```text
/root/leikwan-toolkit.sh
/usr/local/bin/lq -> /root/leikwan-toolkit.sh
/usr/local/bin/LQ -> /root/leikwan-toolkit.sh
```

GitHub 慢时设置：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

## 公网入口角色误用

主菜单“公网入口”只管理 A 本机。如果当前机器是 B 利群主机，查看公网入口状态会提示进入：

```text
利群主机 -> 公网入口列表管理
```

B 侧删除、启用/禁用、修改权重、测试公网入口都会先展示列表，并支持编号选择。

## 转发目标端口

后端目标端口没有默认值，必须输入 `1-65535`。空输入会提示：

```text
[WARN] 后端目标端口不能为空，请输入 1-65535。
```

添加转发目标时，公网入口端口提示会显示入口端口池或常见范围，并推荐下一个未使用端口。

## DDNS / 域名后端

域名后端是支持的。添加时脚本会显示当前解析 IP：

```text
[INFO] 检测到后端目标是域名，当前解析为：203.0.113.20
[INFO] 每次 apply-relay 会重新解析域名并刷新 nftables 规则。
[INFO] 如果该域名需要固定走 CN2 / 9929，请到 PBR 菜单选择“从现有转发目标添加 PBR”。
```

`resolved.tsv` 会保存 `target_host`、`resolved_ip` 和 `last_resolved_at`。解析失败时：

- 有上次 IP：继续使用上次 IP 并 WARN。
- 无上次 IP：跳过该转发目标并 WARN。

## PBR 输入域名

静态 PBR 只接受 IPv4 / CIDR。域名后端需要固定出口时，进入：

```text
IPv4 多出口策略路由 / PBR -> 从现有转发目标添加 PBR
```

脚本会从转发目标解析当前 IP，写入 `resolved_ip/32 -> route_table`，后续应用 PBR 时刷新来源域名。

## 有 ping 但 TCP 不通

在 B 执行：

```bash
sudo lq forward apply-relay --auto-fix-route
sudo lq --doctor --verbose
```

重点看：

- A 入口端口池是否包含该 entry_port。
- B relay nftables 是否有 DNAT。
- 后端目标 TCP 是否可达。
- `out_iface` 是否和实际出口 dev 一致。
- MSS clamp 是否启用。

MSS clamp 配置：

```bash
sudo install -d -m 700 /etc/leikwan-toolkit/nft
printf 'TCP_MSS_CLAMP=1280\nENABLE_MSS_CLAMP=true\n' | sudo tee /etc/leikwan-toolkit/nft/mss.env >/dev/null
sudo lq forward apply-relay
```

## 旧目录

新状态目录是 `/etc/leikwan-toolkit`。如果存在旧名称目录，新目录不存在时会自动迁移；新旧都存在时优先使用新目录，并提示旧目录可清理。
