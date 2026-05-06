# leikwan-wg-toolkit

`leikwan-wg-toolkit` 是“利群三机链式代理部署工具”。

目标链路：

```text
客户端 -> 公网入口机:30000 -> WireGuard UDP -> 利群中转机:10.198.1.1:30000 -> Xray Reality -> 海外落地机:30004 -> Internet
```

公网入口机到利群中转机之间只使用原生 WireGuard UDP。本项目不会加入 FRP、UoT/Phantun、WireGuard over WSS、OpenVPN TCP、SoftEther、gost、udp2raw 等 TCP/fake TCP 隧道方案。

## 快速命令

```bash
sudo bash wg-toolkit.sh
lq
LQ
bash wg-toolkit.sh --dry-run
bash wg-toolkit.sh --validate
bash wg-toolkit.sh --doctor
bash wg-toolkit.sh --doctor --verbose
bash wg-toolkit.sh --show-wg-identity
bash wg-toolkit.sh --show-wg-identity --role leikwan
bash wg-toolkit.sh --rebuild-outputs
bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption '<VLESSENC_ENCRYPTION>'
sudo bash wg-toolkit.sh --pbr-apply
sudo bash wg-toolkit.sh --pbr-refresh-domains
bash wg-toolkit.sh --pbr-show
sudo bash wg-toolkit.sh --pbr-audit
sudo bash wg-toolkit.sh --pbr-import-existing
bash wg-toolkit.sh --help
bash wg-toolkit.sh --version
sudo bash wg-toolkit.sh --uninstall
```

首次运行 `sudo bash wg-toolkit.sh` 后，会自动安装 `lq` / `LQ` 快捷命令；之后可直接运行 `lq` 进入工具。快捷命令路径为 `/usr/local/bin/lq` 和 `/usr/local/bin/LQ`，推荐日常使用小写：

```bash
lq
```

如果快捷命令失效，可以重新运行：

```bash
sudo bash wg-toolkit.sh
```

然后进入“高级功能 -> 安装 / 修复快捷命令”。

`--dry-run` 会进入同一套菜单，但角色部署只生成配置预览，不安装、不写入、不启动服务。dry-run 里的参数卡片会明确标注“不能用于真实部署”，避免误复制预览参数。

`--validate` 会自动检查 wg、xray、realm、DNS、IPv6 防火墙、端口监听和已知链路连通性，输出完整报告。

`--doctor` 默认输出简洁摘要；需要完整分组报告时使用 `--doctor --verbose`。doctor 不会进入交互 read，outputs 缺失时只提示修复命令。

## Release Notes

### 0.2.4-alpha

- 新增 `lq` / `LQ` 快捷命令，默认托管到 `/usr/local/bin/`，卸载时只清理本项目创建的快捷命令。
- 主菜单和极速部署向导增加项目启动横幅，显示作者、版本和 GitHub 地址；非交互命令保持机器可读输出。

### 0.2.3-alpha

- 新增公网入口机 `nftables` / `iptables` 内核转发模式，`nftables` 为默认推荐。
- 保留 `realm-leikwan` 用户态转发作为兼容方案。
- README/docs 脱敏，真实公网 IP、公钥、UUID、VLESSENC 和客户端链接统一改为占位符或 RFC5737 示例地址。
- 新增 `scripts/check-redaction.sh`，打包前自动检查文档脱敏。

## 一键安装

raw.githubusercontent.com：

```bash
curl -fsSL https://raw.githubusercontent.com/leikwan/leikwan-wg-toolkit/main/wg-toolkit.sh -o wg-toolkit.sh && sudo bash wg-toolkit.sh
```

强制 IPv4：

```bash
curl -4 -fsSL https://raw.githubusercontent.com/leikwan/leikwan-wg-toolkit/main/wg-toolkit.sh -o wg-toolkit.sh && sudo bash wg-toolkit.sh
```

ghfast 备用：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/leikwan/leikwan-wg-toolkit/main/wg-toolkit.sh -o wg-toolkit.sh && sudo bash wg-toolkit.sh
```

## 默认参数

- WG 网段：`10.198.1.0/24`
- 利群中转机：`wg0`，`10.198.1.1/24`
- 公网入口机：`wg1`，`10.198.1.2/24`
- 公网入口机 WireGuard：`8301/udp`
- 客户端入口：`30000`
- 海外落地 Reality：`30004`
- MTU：`1280`
- PersistentKeepalive：`25`
- IPv4 PBR 静态规则优先级：`15000`
- IPv4 PBR 域名 DDNS 规则优先级：`15005`

## 服务与路径

为避免污染用户已有服务，项目使用带 `leikwan` 标识的服务、配置和日志路径：

- Xray 配置：`/usr/local/etc/xray/leikwan/config.json`
- Xray 推荐服务：`xray-leikwan.service`
- realm 服务：`realm-leikwan.service`
- realm 配置：`/etc/leikwan-wg-toolkit/realm/realm-leikwan.toml`
- Xray 日志：`/var/log/xray-leikwan-access.log`、`/var/log/xray-leikwan-error.log`
- realm 日志：`/var/log/realm-leikwan.log`
- 脚本日志：`/var/log/leikwan-wg-toolkit.log`
- 备份目录：`/var/backups/leikwan-wg-toolkit`
- 每次角色部署输出：`/root/leikwan-wg-toolkit-output.txt`
- 角色参数输出目录：`/etc/leikwan-wg-toolkit/outputs/`
- 公网入口机参数：`/etc/leikwan-wg-toolkit/outputs/cloud-entry.env`
- 海外落地机参数：`/etc/leikwan-wg-toolkit/outputs/landing-server.env`
- 利群中转机参数：`/etc/leikwan-wg-toolkit/outputs/leikwan-relay.env`
- 客户端链接：`/etc/leikwan-wg-toolkit/outputs/client-link.txt`
- 快捷命令：`/usr/local/bin/lq`、`/usr/local/bin/LQ`
- 利群 WG Key：`/etc/wireguard/wg0_privatekey`、`/etc/wireguard/wg0_publickey`
- 公网入口 WG Key：`/etc/wireguard/wg1_privatekey`、`/etc/wireguard/wg1_publickey`
- IPv4 PBR 静态规则：`/etc/leikwan-wg-toolkit/pbr/static-routes.conf`
- IPv4 PBR 域名规则：`/etc/leikwan-wg-toolkit/pbr/domain-routes.conf`
- IPv4 PBR 线路组：`/etc/leikwan-wg-toolkit/pbr/route-groups.conf`
- IPv4 PBR 域名状态：`/var/lib/leikwan-wg-toolkit/pbr/domain-state.conf`

如果检测到已有 `xray.service`，脚本会让用户三选一：

1. 备份并覆盖 `xray.service`
2. 创建独立 `xray-leikwan.service`（默认推荐）
3. 取消

## GitHub 下载 fallback

realm 和 Xray 的 GitHub Release 下载按以下顺序 fallback：

1. GitHub 直连
2. `ghfast`
3. `ghproxy`
4. 本地文件路径

如果 Release API 查询不到资产，也会允许输入本地安装包路径。

## 主菜单

```text
--------------------------------------------------
  Leikwan WG Toolkit
  利群三机链式代理部署工具
  Author : ike-sh
  Version: 0.2.4-alpha
  GitHub : https://github.com/ike-sh/leikwan-wg-toolkit
--------------------------------------------------

1. 极速部署向导
2. 查看复制参数 / 客户端链接
3. 一键诊断 doctor
4. 高级功能
0. 退出
```

普通用户只需要前 3 项。原来的完整功能都放在“高级功能”里：

```text
查看 / 生成本机 WireGuard 身份
部署总览 / 下一步提示
公网入口机部署
利群中转机部署
海外落地机部署
导入参数文件
IPv4 多出口策略路由
链路测试
DNS / IPv4 优先修复
IPv6 入站安全收口
查看状态
备份 / 恢复
卸载
安装 / 修复快捷命令
```

## 推荐部署顺序

最推荐的三步记法：

1. 落地机生成 `LANDING_*`，利群生成 `LEIKWAN_PUBLIC_KEY`。
2. 公网入口机粘贴 `LEIKWAN_PUBLIC_KEY`，输出 `CLOUD_*`。
3. 回利群导入 `LANDING_*` + `CLOUD_*`，生成 `CLIENT_LINK` 并按需启用 PBR。

最推荐直接进入菜单 1“极速部署向导”。向导会先识别当前机器角色，再只显示这台机器需要的步骤，避免跨机器菜单把人绕晕。

海外落地机向导：

```text
1. 部署 / 更新 Reality 落地
2. 查看 LANDING 参数
3. doctor
```

公网入口机向导：

```text
1. 导入 / 输入 LEIKWAN_PUBLIC_KEY
2. 部署 / 更新 WireGuard + 转发
3. 查看 CLOUD 参数
4. doctor
```

利群中转机向导：

```text
1. 查看 / 生成 LEIKWAN_PUBLIC_KEY
2. 导入 CLOUD 参数
3. 导入 LANDING 参数
4. 完成链式代理部署
5. 指定 Reality 落地机出口
6. 查看客户端链接
7. doctor
```

脚本每一步都会用醒目的复制区块输出下一步要去哪里做什么。

## WireGuard 身份稳定性

WireGuard key 不再从临时配置里反复生成。默认文件：

```text
/etc/wireguard/wg0_privatekey
/etc/wireguard/wg0_publickey
/etc/wireguard/wg1_privatekey
/etc/wireguard/wg1_publickey
```

如果 key 文件存在，脚本复用它；如果 key 文件不存在但 `wg0.conf` / `wg1.conf` 有 `PrivateKey`，脚本会提取并补写 key 文件。如果 key 文件和 conf 里的 `PrivateKey` 冲突，会让用户选择使用哪一个，默认取消。

查看或生成本机身份：

```bash
sudo bash wg-toolkit.sh --show-wg-identity
sudo bash wg-toolkit.sh --show-wg-identity --role leikwan
sudo bash wg-toolkit.sh --show-wg-identity --role cloud
```

`--show-wg-identity` 是纯 CLI 输出，不会进入交互菜单。如果同时存在 `wg0` 和 `wg1`，会输出两组身份。

重置 key 只能在“高级功能 -> 查看 / 生成本机 WireGuard 身份 -> 重置本机 WireGuard Key”里单独执行，并需要二次确认。重置会导致对端 Peer 失效。

## 查看参数与重建 outputs

主菜单 `2. 查看复制参数 / 客户端链接` 会按当前角色显示：

- 海外落地机：`LANDING_*`
- 公网入口机：`CLOUD_*`
- 利群中转机：`LEIKWAN_PUBLIC_KEY`、已导入的 `CLOUD_*` / `LANDING_*`、`CLIENT_LINK`

升级旧版本、手动恢复配置、或 outputs 丢失时，可以从当前已运行配置重建输出文件：

```bash
sudo bash wg-toolkit.sh --rebuild-outputs
```

它会尝试重建 `/etc/leikwan-wg-toolkit/outputs/` 和 `/root/leikwan-wg-toolkit-output.txt`。如果旧 `/root/leikwan-wg-toolkit-output.txt` 已有 `CLIENT_LINK`，会自动迁移到 `client-link.txt`，并从链接反解析 `ENTRY_UUID`、`CLOUD_ENDPOINT`、`CLIENT_ENTRY_PORT`、`VLESSENC_ENCRYPTION`。

服务端配置里的 `VLESSENC_DECRYPTION` 不能反推客户端用的 `VLESSENC_ENCRYPTION`。缺少 `VLESSENC_ENCRYPTION` 时，脚本会生成 partial `leikwan-relay.env`，但不会生成 `client-link.txt`：

```bash
sudo bash wg-toolkit.sh --rebuild-outputs \
  --vlessenc-encryption '<VLESSENC_ENCRYPTION>' \
  --cloud-endpoint <CLOUD_PUBLIC_IP> \
  --client-entry-port 30000 \
  --landing-address <LANDING_PUBLIC_IP> \
  --landing-port 30004
```

`--rebuild-outputs` 参数优先级：CLI 参数、`/etc/leikwan-wg-toolkit/outputs/*.env`、`/root/leikwan-wg-toolkit-output.txt`、`CLIENT_LINK` 反解析、当前 wg/xray/realm 配置。

## 参数文件导入

如果不想手工逐项复制，可以把另一台机器生成的 env 文件传过来，然后在“极速部署向导”对应步骤或“高级功能 -> 导入参数文件”导入。支持路径或直接粘贴：

```text
KEY=value
```

利群中转机部署时会优先读取：

```text
/etc/leikwan-wg-toolkit/outputs/cloud-entry.env
/etc/leikwan-wg-toolkit/outputs/landing-server.env
/root/leikwan-wg-toolkit-output.txt
```

缺少必填字段时，脚本会明确提示缺什么，不会让用户盲填一长串参数。

## 公网入口机部署

高级功能菜单：

```text
公网入口机部署
```

功能：

- 安装 WireGuard。
- 创建 `/etc/wireguard/wg1.conf`。
- 地址 `10.198.1.2/24`。
- 监听 `8301/udp`。
- Peer 使用利群中转机 PublicKey。
- Peer `AllowedIPs = 10.198.1.1/32`。
- 启用 `wg-quick@wg1`。
- 选择公网入口转发方式。

### 公网入口机转发模式

默认只转发 TCP `30000`，不默认开放 UDP `30000`。

1. `nftables` 内核转发（推荐）
   - 无用户态监听进程。
   - 适合公网入口机检测更严格的环境。
   - 需要 `net.ipv4.ip_forward=1`。
   - 规则由 `leikwan-forward-nft.service` 加载，只管理 `leikwan_nat` / `leikwan_filter` 表。

2. `iptables` 内核转发
   - 兼容旧系统。
   - 需要 `net.ipv4.ip_forward=1`。
   - 规则由 `leikwan-forward-iptables.service` 精确添加/删除，不依赖 `iptables-persistent`。

3. `realm` 用户态转发
   - 兼容性好。
   - 会有 `realm-leikwan` 进程监听 `30000`。

4. 不配置转发
   - 只部署 WireGuard，转发由用户自行处理。

输出：

```text
CLOUD_PUBLIC_KEY=...
CLOUD_ENDPOINT=...
CLOUD_WG_PORT=8301
CLIENT_ENTRY_PORT=30000
FORWARD_MODE=nftables
FORWARD_TARGET=10.198.1.1:30000
```

验收：

```bash
wg show
ping -c 3 10.198.1.1
nc -vz 10.198.1.1 30000
sudo bash wg-toolkit.sh --doctor
nft list ruleset | grep -A20 leikwan
iptables -t nat -S | grep 10.198.1.1 || true
```

## 海外落地机部署

高级功能菜单：

```text
海外落地机部署
```

功能：

- 安装 Xray。
- 生成 Reality UUID。
- 执行 `xray x25519` 生成 Reality PrivateKey/PublicKey。
- 生成 shortId。
- 写入 `/usr/local/etc/xray/leikwan/config.json`。
- Reality inbound 默认监听 `0.0.0.0:30004`。
- `xray run -test` 通过后启动 `xray-leikwan.service`。

输出给利群：

```text
LANDING_ADDRESS=...
LANDING_PORT=30004
LANDING_UUID=...
LANDING_PUBLIC_KEY=...
LANDING_SHORT_ID=...
LANDING_SERVER_NAME=www.microsoft.com  # 示例 serverName
LANDING_FLOW=xtls-rprx-vision
```

Reality PrivateKey 只保存在落地机配置中，不输出给利群复制。

验收：

```bash
systemctl status xray-leikwan --no-pager
ss -lntup | grep 30004
/usr/local/bin/xray run -test -config /usr/local/etc/xray/leikwan/config.json
```

## 利群中转机部署

高级功能菜单：

```text
利群中转机部署
```

功能：

- 安装 WireGuard。
- 创建 `/etc/wireguard/wg0.conf`。
- 地址 `10.198.1.1/24`。
- 输入 `CLOUD_PUBLIC_KEY`、`CLOUD_ENDPOINT`、`CLOUD_WG_PORT`。
- `Endpoint = CLOUD_ENDPOINT:CLOUD_WG_PORT`
- `AllowedIPs = 10.198.1.2/32`
- `PersistentKeepalive = 25`
- 启动 `wg-quick@wg0`。
- 安装 Xray。
- 生成 `ENTRY_UUID`。
- 执行 `xray vlessenc`，自动解析或手动选择 X25519 参数。
- 写入 `/usr/local/etc/xray/leikwan/config.json`。
- inbound 监听 `10.198.1.1:30000`。
- outbound 连接海外落地机 Reality。
- routing 阻断 bittorrent。

输出客户端导入链接：

```text
vless://<ENTRY_UUID>@<CLOUD_PUBLIC_IP>:30000?type=raw&security=none&encryption=<VLESSENC_ENCRYPTION>#Leikwan-WG-Xray-Reality
```

脚本会同时写入：

```text
/etc/leikwan-wg-toolkit/outputs/leikwan-relay.env
/etc/leikwan-wg-toolkit/outputs/client-link.txt
/root/leikwan-wg-toolkit-output.txt
```

客户端链接只包含 `VLESSENC_ENCRYPTION`，不会把服务端 `VLESSENC_DECRYPTION` 写进链接。可随时从主菜单“查看复制参数 / 客户端链接”重新显示。

验收：

```bash
wg show
ss -lntup | grep 30000
ip route get LANDING_ADDRESS
nc -vz LANDING_ADDRESS LANDING_PORT
systemctl status xray-leikwan --no-pager
```

## DNS / IPv4 优先修复

高级功能里的“DNS / IPv4 优先修复”会保留原逻辑：

- 备份 `/etc/gai.conf`
- 添加 `precedence ::ffff:0:0/96  100`
- 如果存在 systemd-resolved，写入 DNS drop-in
- 关闭 LLMNR 和 MulticastDNS
- 测试 `getent ahosts raw.githubusercontent.com`

`raw.githubusercontent.com` 能通即可；`github.com` 主站可能仍因出口路由不可达。Release 下载推荐 ghfast 镜像或本地安装包。

## IPv4 多出口策略路由

高级功能里的“IPv4 多出口策略路由”是独立的 IPv4 PBR 模块，主要用于利群中转机把指定目标 IP/CIDR/域名走指定 IPv4 出口，尤其是 Reality 海外落地机 IP。

它不会接管整机默认路由，不修改 `main` 默认路由，不删除系统已有默认网关，也不引入 FRP/UoT/WSS/OpenVPN/gost/udp2raw。

内置常见线路组会根据本机 IPv4 自动识别，例如：

- 检测到 `10.7.x.x` 显示 `9929`
- 检测到 `10.8.x.x` 显示 `CN2`

示例：指定落地机 `<LANDING_PUBLIC_IP>` 走 `T_9929`：

```text
<LANDING_PUBLIC_IP> -> T_9929
```

添加后验收：

```bash
ip route get <LANDING_PUBLIC_IP>
ip rule show | grep 15000
```

域名 DDNS 规则只解析 A 记录，不处理 AAAA。自动刷新使用 systemd timer：

```text
leikwan-pbr-ddns.timer
```

默认每 5 分钟刷新一次。

如果机器上已有手工 PBR 规则，可以先审计再导入：

```bash
ip rule show | grep <LANDING_PUBLIC_IP>
```

示例：

```text
15000: from all to <LANDING_PUBLIC_IP> lookup T_9929
```

导入到项目：

```bash
sudo bash wg-toolkit.sh --pbr-import-existing
```

验证：

```bash
sudo bash wg-toolkit.sh --pbr-show
sudo bash wg-toolkit.sh --pbr-audit
ip route get <LANDING_PUBLIC_IP>
```

PBR apply / 卸载只删除项目配置或状态文件记录过的精确规则，不会按 priority `15000` / `15005` 全删，也不会删除未托管的手工规则。

## IPv6 入站安全收口

高级功能里的“IPv6 入站安全收口”不禁用 IPv6，只创建 IPv6 入站防火墙：

- 允许 `lo`
- 允许 `ESTABLISHED,RELATED`
- 允许 `ipv6-icmp`
- 允许 `tcp/22`
- 其他 IPv6 入站 DROP
- 关闭 LLMNR 和 MulticastDNS
- 持久化到 `/etc/iptables/rules.v6`

## 卸载

高级功能里的“卸载”分角色卸载：

- 公网入口机：删除本项目创建的 `wg1`、`leikwan-forward-nft.service`、`leikwan-forward-iptables.service`、`realm-leikwan.service` 和本项目转发规则。
- 利群中转机：删除本项目创建的 `wg0`，Xray 配置删除需要二次确认。
- 海外落地机：Xray 配置删除需要二次确认。
- 可单独删除本项目托管的 IPv4 PBR 运行中规则，未托管同 priority 规则会保留。
- 可单独删除 IPv6 `V6_LOCKDOWN`。
- 可删除本项目创建的 `lq` / `LQ` 快捷命令；如果同名文件不是本项目创建，会 WARN 并保留。

卸载不会删除用户已有的非本项目服务，也不会卸载软件包。Xray 二进制默认保留。
