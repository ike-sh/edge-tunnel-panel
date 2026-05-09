# Leikwan Toolkit

`leikwan-toolkit` v0.4.0-alpha 是“公网入口 + 利群主机 + 后端目标”的三段 TCP/UDP 转发组网工具。

- 传输层：EasyTier
- 转发层：nftables
- 策略路由：IPv4 PBR
- 运维能力：MSS clamp、doctor 诊断、一键卸载、旧路径迁移/清理

仓库地址：[https://github.com/ike-sh/leikwan-toolkit](https://github.com/ike-sh/leikwan-toolkit)

## 安装

推荐安装：

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
```

GitHub 慢时可启用镜像轮询：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

唯一主脚本安装到 `/root/leikwan-toolkit.sh`，快捷命令 `/usr/local/bin/lq` 和 `/usr/local/bin/LQ` 都指向它。

Release 包名：

```text
leikwan-toolkit-0.4.0-alpha.tar.gz
```

Release URL：

```text
https://github.com/ike-sh/leikwan-toolkit/releases/latest/download/leikwan-toolkit-0.4.0-alpha.tar.gz
```

## Banner

```text
Leikwan Toolkit
利群快速组网工具
Author : ike-sh
Version: 0.4.0-alpha
GitHub : https://github.com/ike-sh/leikwan-toolkit
```

## 快速组网

菜单路径：`主菜单 -> 快速组网（分步提示）`

```text
1. 我现在在利群主机：先执行 DNS / IPv4 优先修复
2. 我现在在利群主机：生成 / 新增公网入口网络码
3. 我现在在公网入口：粘贴利群网络码，部署本机入口
4. 我现在在利群主机：粘贴公网入口返回码，完成接入
5. 我现在在公网入口：配置入口端口池
6. 我现在在利群主机：添加后端转发目标
7. IPv4 多出口策略路由 / PBR
8. 查看完整分步说明
0. 返回
```

新增第二台公网入口的正确流程：

1. B 利群主机执行第 2 项，脚本复用现有 EasyTier network name / secret，不覆盖 `network.env`，不重启 relay，并自动推荐新的入口名、EasyTier IP 和 8000-9000 内监听端口。新生成的网络码默认建议 EasyTier `tcp,udp`，TCP 和 UDP 使用同一个端口，例如 `8301`。
2. 新 A 公网入口执行第 3 项，粘贴 B 的网络码并部署本机入口。
3. 新 A 执行第 5 项，配置本机入口端口池。
4. B 执行第 4 项，粘贴 A 返回的 ENTRY 入口码；默认只保存 `entries.tsv`，不会自动重启 relay。
5. B 进入 `利群主机 -> 公网入口列表管理` 查看或测试入口。

如果需要立即应用新入口，脚本会明确提示重启 EasyTier relay 会短暂中断所有已接入入口，并要求用户确认；建议在维护窗口执行。

EasyTier IP 和公网地址不要混填：

- EasyTier IP：虚拟网 IP，例如 `10.198.1.3`。
- 公网地址 / DDNS：例如 `home.ike-nicholas.xyz`，应填写在“本机公网 IP / 域名”。

端口概念要分清：

- EasyTier 组网端口：例如 `8301` / `8302`，TCP 和 UDP 都使用利群推荐的 `8000-9000` 白名单端口，用于 A 和 B 建立 EasyTier peer。
- 业务公网入口端口：例如 `10001` / `10002`，用于外部客户端访问业务转发，不受 EasyTier `8000-9000` 限制。

## 转发目标

B 侧管理路径：`利群主机 -> 转发目标管理`

修改、删除、启用/禁用、测试单个转发目标都会先显示列表，并支持输入编号或名称。添加转发目标时，公网入口端口会按入口端口池推荐下一个未使用端口；后端目标端口没有默认值，必须输入 `1-65535`。

每个转发目标默认同时创建 TCP 和 UDP 转发：同一个 `entry_port` 会同时处理 `tcp dport` 和 `udp dport`。如果后端服务只有 TCP，UDP 规则存在也不会影响 TCP；如果后端服务支持 UDP，外部 UDP 可以走同一个公网入口端口。

DDNS / 域名后端是支持的。`apply-relay` 每次都会重新解析域名并刷新 `resolved.tsv` 和 nftables 规则；解析失败时，如果存在上次解析 IP，会继续使用旧 IP 并 WARN。

## PBR

菜单路径：`IPv4 多出口策略路由 / PBR`

```text
1. 添加静态 PBR
2. 从现有转发目标添加 PBR
3. 删除 PBR 规则
4. 应用 PBR
5. 查看 PBR
0. 返回
```

静态 PBR 只接受 IPv4 或 CIDR。域名 / DDNS 后端需要固定线路时，使用“从现有转发目标添加 PBR”，脚本会解析当前 IPv4 并写入 `resolved_ip/32 -> route_table`，后续应用 PBR 时会刷新来源域名。

删除 PBR 规则会先展示当前规则列表，支持输入编号、CIDR 或裸 IP；裸 IP 会按 `/32` 匹配。删除后脚本会重新应用 PBR。来自 DDNS / forward 的规则删除的是当前解析 IP 对应的 PBR 记录；如果同一 CIDR 有多条不同路由表规则，请用编号精确删除。

## 路径迁移

新路径：

```text
/etc/leikwan-toolkit
/var/backups/leikwan-toolkit
/var/log/leikwan-toolkit.log
```

如果检测到旧名称目录，新目录不存在时会自动迁移；新旧都存在时优先使用新目录，并提示旧目录可清理。

## 下载排错

`doctor` 会检查 GitHub / apt 域名是否解析到 `198.18.x.x` fake-ip，以及 `curl`、`jq`、`tar`、`unzip` 是否存在。若 OpenClash / Mihomo / sing-box fake-ip DNS 没有透明代理接管本机流量，GitHub 或 apt 可能连接超时；可临时改用 `223.5.5.5` / `119.29.29.29`，或在路由器中让该主机直连 / 正确透明代理。apt 源返回 403 时，请换源或手动安装 deb。无法安装 `unzip` 时，优先使用 EasyTier `tar.gz` / `tgz` 包或本地 `easytier-core`、`easytier-cli` 二进制。

## 卸载

交互卸载：

```text
lq
主菜单 -> 卸载全部
```

CLI 卸载：

```bash
bash /root/leikwan-toolkit.sh --uninstall
```

卸载逻辑内置在主脚本中，会清理本工具创建的 EasyTier 服务、nftables 转发表、快捷命令、状态目录、备份目录、日志、PBR 规则和历史路径。

## GitHub About 建议

Description:

```text
Role-based Debian toolkit for Leikwan TCP/UDP chaining with EasyTier, nftables, IPv4 PBR, MSS clamp, and diagnostics.
```

Topics:

```text
debian shell-script easytier nftables tcp-forwarding udp-forwarding pbr mss-clamp network-toolkit proxy-toolkit leikwan diagnostics
```

## 文档

- [工作流](docs/workflow.md)
- [PBR](docs/pbr.md)
- [排错](docs/troubleshooting.md)
- [验收测试](docs/acceptance-test.md)
- [多公网入口](docs/multi-entry.md)
- [forwards.tsv](docs/forwards.tsv.md)
