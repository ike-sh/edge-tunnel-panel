# 排错

v0.4.0-alpha 主线是 EasyTier 传输 + nftables 四层 TCP/UDP 转发。脚本不部署后端业务，只负责：

```text
client -> A 公网入口端口 -> EasyTier -> B 利群主机 -> 后端目标
```

默认情况下，EasyTier 组网和业务转发都使用 TCP+UDP。旧 TCP-only 配置仍兼容，不会被自动改成双协议。

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

## EasyTier 下载 / apt 依赖异常

先运行：

```bash
sudo lq --doctor --verbose
```

重点看：

- `raw.githubusercontent.com`、`api.github.com`、`cn.archive.ubuntu.com` 是否解析到 `198.18.x.x`。
- `curl`、`jq`、`tar`、`unzip` 是否存在。
- apt 源更新是否返回 403。

如果 DNS 解析到了 `198.18.x.x` fake-ip，通常是 OpenClash / Mihomo / sing-box fake-ip DNS。若本机流量没有被透明代理接管，GitHub / apt 会超时。可临时改用真实 DNS，例如 `223.5.5.5` / `119.29.29.29`，或在路由器中让该主机直连 / 正确透明代理。

如果 apt 源返回 403，请换源或手动安装对应 deb 包。若无法安装 `unzip`，脚本会跳过 zip 包并优先尝试 `tar.gz` / `tgz` 资产；也可以上传本地 EasyTier 包，或直接提供本地 `easytier-core` 与 `easytier-cli` 二进制。

## 公网入口角色误用

主菜单“公网入口”只管理 A 本机。如果当前机器是 B 利群主机，查看公网入口状态会提示进入：

```text
利群主机 -> 公网入口列表管理
```

B 侧删除、启用/禁用、修改权重、测试公网入口都会先展示列表，并支持编号选择。

## 新增入口不应影响旧入口

新增第二台公网入口时，B 侧“生成 / 新增公网入口网络码”会复用已有 EasyTier network name / secret，不会覆盖 `/etc/leikwan-toolkit/easytier/network.env`，也不会重启 `easytier-relay`。

B 粘贴 A 返回的 ENTRY 入口码时，默认只保存 `entries.tsv`。如果要立即应用，脚本会提示重启 relay 会短暂中断所有已接入入口，并要求确认；建议在维护窗口应用。

如果发现旧入口掉线，优先检查是否手动重启过 `easytier-relay`、service peer 列表是否同时包含所有 enabled entries，以及 `entries.tsv` 是否还保留旧入口行。

新入口默认使用 `tcp,udp`，relay service 中应能看到同一入口的两个 peer，例如 `tcp://host:8301` 和 `udp://host:8301`。旧 `tcp` 入口只生成 TCP peer，这是兼容行为。

## EasyTier IP 填写错误

A 部署入口时：

- “本机 EasyTier IP”只能填虚拟 IPv4，例如 `10.198.1.3`。
- “本机公网 IP / 域名”才填写公网地址或 DDNS，例如 `home.ike-nicholas.xyz`。

如果把 DDNS 填到 EasyTier IP 栏，脚本会提示这是域名而不是虚拟 IP，并继续显示网络码中的默认值，避免把非法输入写成下一轮默认值。

## 转发目标端口

后端目标端口没有默认值，必须输入 `1-65535`。空输入会提示：

```text
[WARN] 后端目标端口不能为空，请输入 1-65535。
```

添加转发目标时，公网入口端口提示会显示入口端口池或常见范围，并推荐下一个未使用端口。

请区分两类端口：

- EasyTier 组网端口：例如 `8301`，TCP 和 UDP 都校验在 `8000-9000`，用于 A/B peer 建链。
- 业务公网入口端口：例如 `10001`，用于外部客户端访问后端业务，A 侧端口池会同时 DNAT TCP 和 UDP。

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

## 删除错误 PBR 规则

进入：

```text
IPv4 多出口策略路由 / PBR -> 删除 PBR 规则
```

删除菜单会先展示当前规则列表，支持输入编号、CIDR 或裸 IP；裸 IP 会按 `/32` 匹配。删除后脚本会重新应用 PBR。

如果规则来自 DDNS / forward，删除的是当前解析 IP 对应的 PBR 记录。若同一 CIDR 有多条不同路由表规则，请用编号精确删除，避免删错线路。

## 有 ping 但 TCP 不通

在 B 执行：

```bash
sudo lq forward apply-relay --auto-fix-route
sudo lq --doctor --verbose
```

重点看：

- A 入口端口池是否包含该 entry_port。
- A 入口端口池是否同时有 TCP / UDP DNAT。
- B relay nftables 是否同时有 TCP / UDP DNAT。
- 后端目标 TCP 是否可达。
- `out_iface` 是否和实际出口 dev 一致。
- MSS clamp 是否启用。

## UDP 探测未确认

`doctor` 会尝试 `nc -uvz -w 3 host port`，但 UDP 是无连接协议，失败不一定代表业务不可用。UDP 探测失败时脚本只 WARN，最终仍应结合 EasyTier peer / ping 和实际业务测试判断。

如果 UDP 不通但 TCP 正常，常见原因是安全组或家宽路由器只放行了 TCP。请同时开放：

- EasyTier 端口 TCP+UDP，例如 `8301`。
- 业务入口端口 TCP+UDP，例如 `10001-10020` 或具体端口。

MSS clamp 配置：

```bash
sudo install -d -m 700 /etc/leikwan-toolkit/nft
printf 'TCP_MSS_CLAMP=1280\nENABLE_MSS_CLAMP=true\n' | sudo tee /etc/leikwan-toolkit/nft/mss.env >/dev/null
sudo lq forward apply-relay
```

## 旧目录

新状态目录是 `/etc/leikwan-toolkit`。如果存在旧名称目录，新目录不存在时会自动迁移；新旧都存在时优先使用新目录，并提示旧目录可清理。
