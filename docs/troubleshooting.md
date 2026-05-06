# 排错说明

排错顺序：

```text
公网入口机 -> WireGuard UDP -> 利群中转机 Xray inbound -> 海外落地机 Reality -> 客户端链接
```

## 先跑 doctor

日常排错先跑简洁诊断：

```bash
bash wg-toolkit.sh --doctor
```

它会先识别当前角色，只输出核心摘要，例如：

```text
[OK] 角色：leikwan-relay
[OK] WG：handshake 14 秒前
[OK] Xray：10.198.1.1:30000
[OK] PBR：216.45.59.72 -> T_9929
[OK] 客户端链接：存在
```

需要完整分组报告时再跑：

```bash
bash wg-toolkit.sh --doctor --verbose
bash wg-toolkit.sh --validate
```

`--doctor --verbose` 和 `--validate` 会检查：

```bash
bash wg-toolkit.sh --doctor --verbose
```

- `wg` / `xray` / `realm` 命令
- `wg show`
- `wg0` / `wg1`
- `xray-leikwan.service`、`xray.service`
- `realm-leikwan.service`
- `/usr/local/etc/xray/leikwan/config.json`
- `/etc/leikwan-wg-toolkit/realm/realm-leikwan.toml`
- 默认端口 `8301`、`30000`、`30004`
- `raw.githubusercontent.com` DNS
- IPv4 优先规则
- IPv6 `V6_LOCKDOWN`
- WG 内网 ping
- 能解析到落地机时测试 `nc -vz LANDING_ADDRESS LANDING_PORT`
- Xray 配置测试
- GitHub/raw/ghfast 可达性

## 极速部署和高级功能

默认主菜单只有 4 个入口：

```text
1. 极速部署向导
2. 查看复制参数 / 客户端链接
3. 一键诊断 doctor
4. 高级功能
0. 退出
```

普通用户优先走“极速部署向导”。高级功能用于手动部署、导入参数、PBR、DNS、IPv6、备份恢复和卸载。

## dry-run 预演

部署前可以先生成预览：

```bash
bash wg-toolkit.sh --dry-run
```

dry-run 不安装、不写入、不启动服务，只显示即将写入的配置和服务 unit。输出里应显示：

```text
[DRY-RUN] 跳过启动 wg-quick@...
[DRY-RUN] 跳过启动 realm-leikwan.service
[DRY-RUN] 跳过启动 xray-leikwan.service
```

如果 dry-run 显示“已启动”，就是 bug。

## WireGuard PublicKey 变了怎么办

当前版本默认把 key 固定保存到：

```text
/etc/wireguard/wg0_privatekey
/etc/wireguard/wg0_publickey
/etc/wireguard/wg1_privatekey
/etc/wireguard/wg1_publickey
```

查看本机身份：

```bash
sudo bash wg-toolkit.sh --show-wg-identity
sudo bash wg-toolkit.sh --show-wg-identity --role leikwan
sudo bash wg-toolkit.sh --show-wg-identity --role cloud
```

这个命令是直接输出，不会进入菜单。自动模式会优先显示已存在的 `wg0` / `wg1` 身份；两者都存在时会同时显示。

如果 key 文件和 `wg0.conf` / `wg1.conf` 中的 `PrivateKey` 不一致，脚本会提示冲突并默认取消。不要直接重跑部署试图“修好”，先决定使用 key 文件还是 conf 文件。

如果已经误重置，必须把新的 PublicKey 更新到对端 Peer：

- 利群 `LEIKWAN_PUBLIC_KEY` 变了：去公网入口机更新 Peer。
- 公网入口 `CLOUD_PUBLIC_KEY` 变了：回利群中转机更新 Peer。

## outputs 或 CLIENT_LINK 丢失

升级旧版本、手动恢复配置，或 `/etc/leikwan-wg-toolkit/outputs/` 被误删时，先尝试重建：

```bash
sudo bash wg-toolkit.sh --rebuild-outputs
```

脚本会从当前 WireGuard、realm、Xray 配置重建：

```text
/etc/leikwan-wg-toolkit/outputs/cloud-entry.env
/etc/leikwan-wg-toolkit/outputs/landing-server.env
/etc/leikwan-wg-toolkit/outputs/leikwan-relay.env
/etc/leikwan-wg-toolkit/outputs/client-link.txt
/root/leikwan-wg-toolkit-output.txt
```

在利群中转机上，如果 `CLIENT_LINK` 缺失但 Xray 配置存在，`--doctor` 只输出 WARN 和修复命令，不会阻塞式询问。

当前版本的 `--doctor` 不会进入交互，也不会要求输入 `VLESSENC_ENCRYPTION`。如果 outputs 缺失，它只会提示修复命令：

```bash
sudo bash wg-toolkit.sh --rebuild-outputs
sudo bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption 'mlkem...'
```

注意：服务端配置里的 `VLESSENC_DECRYPTION` 不能反推客户端链接需要的 `VLESSENC_ENCRYPTION`。如果旧输出里也没有，重建会生成 partial `leikwan-relay.env`，但不会生成 `client-link.txt`，并输出 WARN。

如果旧 `/root/leikwan-wg-toolkit-output.txt` 中已有：

```text
CLIENT_LINK=vless://...
```

`--rebuild-outputs` 或菜单“查看复制参数 / 客户端链接”会自动迁移到：

```text
/etc/leikwan-wg-toolkit/outputs/client-link.txt
```

迁移时会从 `vless://ENTRY_UUID@host:port?...encryption=...` 反解析并回填：

```text
ENTRY_UUID
CLOUD_ENDPOINT
CLIENT_ENTRY_PORT
VLESSENC_ENCRYPTION
```

## 公网入口机

验收命令：

```bash
wg show
ping -c 3 10.198.1.1
nc -vz 10.198.1.1 30000
ss -lntup | grep 30000
systemctl status realm-leikwan --no-pager
```

如果 `latest handshake` 为空，优先检查：

- 云安全组是否放行 `8301/udp`
- 本机防火墙是否放行 `8301/udp`
- 利群中转机 `Endpoint = CLOUD_ENDPOINT:CLOUD_WG_PORT` 是否正确
- 双方 PublicKey 是否复制错
- `wg-quick@wg0` / `wg-quick@wg1` 是否启动

如果 `nc -vz 10.198.1.1 30000` 失败，说明利群中转机上的 Xray inbound 可能未监听。

## 利群中转机

验收命令：

```bash
wg show
ss -lntup | grep 30000
ip route get LANDING_ADDRESS
nc -vz LANDING_ADDRESS LANDING_PORT
systemctl status xray-leikwan --no-pager
/usr/local/bin/xray run -test -config /usr/local/etc/xray/leikwan/config.json
```

常见问题：

- `ss` 看不到 `10.198.1.1:30000`：检查 `xray-leikwan.service` 和配置测试输出。
- 到落地机 `nc` 失败：检查海外落地机安全组和 Reality 端口。
- 客户端连接失败：确认 `xray vlessenc` 选择的是 X25519 那组，且客户端链接使用的是 `VLESSENC_ENCRYPTION`。

### Xray JSON 测试失败

部署写入 Xray 配置后会执行：

```bash
/usr/local/bin/xray run -test -config /usr/local/etc/xray/leikwan/config.json
```

测试失败不会启动服务。脚本会打印包含 `decryption`、`realitySettings`、`vnext` 等关键字附近的配置片段。

常见原因：

- `xray vlessenc` 输出里的 `"decryption": "..."` 被连同外层双引号复制进变量。
- Reality PublicKey / ShortId 填错。
- JSON 手工改坏。

正确摘要应显示：

```text
VLESSENC_DECRYPTION=mlkem...
```

不应显示：

```text
VLESSENC_DECRYPTION="mlkem..."
```

## 海外落地机

验收命令：

```bash
systemctl status xray-leikwan --no-pager
ss -lntup | grep 30004
/usr/local/bin/xray run -test -config /usr/local/etc/xray/leikwan/config.json
```

Reality PrivateKey 不要复制出去。利群中转机只需要：

```text
LANDING_ADDRESS
LANDING_PORT
LANDING_UUID
LANDING_PUBLIC_KEY
LANDING_SHORT_ID
LANDING_SERVER_NAME
LANDING_FLOW
```

如果误把 PrivateKey 当 PublicKey 填到利群中转机，Reality 握手会失败。

## Xray 服务选择

检测到已有 `xray.service` 时，脚本会提示：

1. 备份并覆盖
2. 创建独立 `xray-leikwan.service`（推荐）
3. 取消

优先选择独立服务。这样不会覆盖用户已有 Xray unit，也更容易卸载。

查看日志：

```bash
journalctl -u xray-leikwan -e --no-pager
tail -n 100 /var/log/xray-leikwan-error.log
```

## realm

本项目只创建：

```text
realm-leikwan.service
/etc/leikwan-wg-toolkit/realm/realm-leikwan.toml
/var/log/realm-leikwan.log
```

检查：

```bash
systemctl status realm-leikwan --no-pager
journalctl -u realm-leikwan -e --no-pager
ss -lntup | grep 30000
```

### realm 安装包只有 realm-slim

`zhboner/realm` 的部分 Release 包解压后可执行文件叫 `realm-slim`。脚本会按以下优先级查找：

```text
realm
realm-slim
realm*
```

并统一安装到：

```text
/usr/local/bin/realm
```

如果仍失败，脚本会输出解压目录的文件列表。可以手动检查上传的 tar.gz 是否匹配当前架构。

## GitHub 下载失败

脚本下载顺序：

```text
GitHub 直连 -> ghfast -> ghproxy -> 本地文件路径
```

如果服务器无法访问 GitHub Release，可以提前上传安装包，然后在脚本提示时输入本地路径。

DNS 修复菜单只要求 `raw.githubusercontent.com` 可解析/可达即可。`github.com` 主站可能仍因出口路由不可达。

### github.com 超时但 raw 可用

`raw.githubusercontent.com` 和 `github.com` 不是同一个访问路径。很多服务器能下载 raw 文件，但访问 GitHub 主站页面或 Release 跳转会因为出口路由、SNI、CDN、TLS 握手或中间网络策略超时。

本项目判断脚本下载时优先看 raw 是否可用。Release 下载则会按直连、ghfast、ghproxy、本地文件路径 fallback。

## 为什么不集成 FRP/UoT/WSS

本项目只允许公网入口机到利群中转机之间使用原生 WireGuard UDP。不会集成：

```text
FRP
UoT/Phantun
WireGuard over WSS
OpenVPN TCP
SoftEther
gost
udp2raw
```

原因是这些 TCP/fake TCP 隧道在本场景下实测延迟高、排错面大，还容易把问题从 UDP 链路转移到额外封装层。工具的定位是把一条原生 WG UDP 链路和 Xray Reality 链路做稳。

## IPv6 入站安全收口

高级功能里的“IPv6 入站安全收口”不禁用 IPv6，只创建入站防火墙：

```text
允许 lo
允许 ESTABLISHED/RELATED
允许 ipv6-icmp
允许 tcp/22
其他 IPv6 入站 DROP
```

查看：

```bash
ip6tables -S V6_LOCKDOWN
ip6tables -S INPUT
cat /etc/iptables/rules.v6
```

如果业务需要 IPv6 公网入站，需要先添加允许规则，或在卸载菜单中单独删除 `V6_LOCKDOWN`。

### 为什么 IPv6 入站只放 22

利群链式代理主链路不依赖 IPv6 公网入站。默认只允许 `tcp/22` 是为了保留 SSH 管理入口，同时把不需要的 IPv6 暴露面收住。

如果你确实需要 IPv6 业务入站，应在启用前明确添加对应允许规则，而不是默认全开。

## xray-leikwan 与已有 xray.service

`xray-leikwan.service` 是本项目推荐使用的独立服务：

- 使用 `/usr/local/etc/xray/leikwan/config.json`
- 日志写入 `/var/log/xray-leikwan-access.log` 和 `/var/log/xray-leikwan-error.log`
- 卸载时只处理本项目标记的配置和 unit

已有 `xray.service` 可能属于用户原有业务。脚本检测到它时会三选一：

1. 备份并覆盖
2. 创建独立 `xray-leikwan.service`（推荐）
3. 取消

除非你明确知道原有 `xray.service` 可以被接管，否则选择独立服务。

## doctor 角色识别

`--doctor` 会先识别当前机器角色：

- `wg0` 且 `10.198.1.1`：`leikwan-relay`
- `wg1` 且 `10.198.1.2`：`cloud-entry`
- Xray Reality inbound `0.0.0.0:30004`：`landing-server`
- 多个角色共存：`multiple`
- 无法判断：`unknown`

doctor 只对当前角色必需组件报 WARN/FAIL。比如在利群中转机上，不会因为 `realm-leikwan` 或 `8301/udp` 不存在而报 WARN；这些属于公网入口机。

## 恢复

危险操作前会备份到：

```text
/var/backups/leikwan-wg-toolkit
```

恢复后按需重启：

```bash
systemctl restart wg-quick@wg0
systemctl restart wg-quick@wg1
systemctl restart xray-leikwan
systemctl restart realm-leikwan
```

## IPv4 PBR 常见问题

### 检测不到 9929 / CN2

脚本根据本机 IPv4 地址自动匹配线路组：

```bash
ip -4 addr show
```

例如：

- `10.7.x.x` 匹配 `9929`
- `10.8.x.x` 匹配 `CN2`

如果本机没有对应网段地址，菜单 1 不会显示该线路。添加规则时可以选择“其他”查看全部内置线路组，但如果本机实际没有该网关，应用路由表可能失败。

### ip route get 仍走默认出口

检查：

```bash
sudo bash wg-toolkit.sh --pbr-audit
sudo bash wg-toolkit.sh --pbr-show
ip rule show | grep -E '15000|15005'
cat /etc/leikwan-wg-toolkit/pbr/static-routes.conf
cat /etc/leikwan-wg-toolkit/pbr/domain-routes.conf
grep 'T_' /etc/iproute2/rt_tables
```

然后重新应用：

```bash
sudo bash wg-toolkit.sh --pbr-apply
ip route get 目标IPv4
```

注意：本模块不会修改 `main` 默认路由。只有命中 priority `15000` / `15005` 的目标才会走指定出口。

### 已有手工 priority 15000 / 15005 规则

先审计：

```bash
sudo bash wg-toolkit.sh --pbr-audit
```

如果看到未托管规则，例如：

```text
15000: from all to 216.45.59.72 lookup T_9929
```

可以导入到项目：

```bash
sudo bash wg-toolkit.sh --pbr-import-existing
sudo bash wg-toolkit.sh --pbr-show
```

导入后脚本只会把对应目标写入 `/etc/leikwan-wg-toolkit/pbr/static-routes.conf`，不会删除原规则。后续 `--pbr-apply` 会识别它，避免重复添加。

### 为什么不能按 priority 全删

同一台机器上可能有用户手工创建的 priority `15000` / `15005` 规则，或者其他业务也用了这两个优先级。

本项目删除规则时只看自己的账本：

```text
/etc/leikwan-wg-toolkit/pbr/static-routes.conf
/var/lib/leikwan-wg-toolkit/pbr/domain-state.conf
```

不会执行 `while ip rule del priority 15000` 这类全删逻辑。

### 域名规则没有生效

域名 PBR 只解析 A 记录，不处理 AAAA。

检查：

```bash
getent ahostsv4 example.com
sudo bash wg-toolkit.sh --pbr-refresh-domains
ip rule show | grep 15005
cat /var/lib/leikwan-wg-toolkit/pbr/domain-state.conf
systemctl status leikwan-pbr-ddns.timer --no-pager
```

如果域名解析失败，脚本会保留旧规则并输出 WARN，不会删除旧的可用出口规则。

`domain-state.conf` 是域名规则的安全边界。刷新域名时只删除这个状态文件里记录过的旧 A 记录，解析失败时保留旧状态和旧规则。

### rt_tables 缺失或异常

Debian 13 上如果 `/etc/iproute2/rt_tables` 缺失或不完整，脚本会补齐基础表：

```text
255 local
254 main
253 default
0 unspec
```

并追加项目表名：

```text
T_9929
T_CN2
```

不会清空系统已有路由表定义。

### 删除 PBR 规则会影响用户规则吗

卸载菜单里的“仅删除 IPv4 PBR 规则”会先显示两组摘要：

- 将删除的本项目托管规则
- 同 priority 但未托管、会保留的规则

它只删除本项目配置或状态文件中存在的目标，并且只处理精确的 priority `15000` / `15005` 规则。

它不会删除用户其他 priority 的 `ip rule`，也不会删除 main 默认路由或系统默认网关。

删除 `/etc/iproute2/rt_tables` 中本项目追加的 `T_` 表名需要二次确认。

### doctor 提示 LANDING_ADDRESS 出口不一致

检查项目配置：

```bash
grep LANDING_ADDRESS /root/leikwan-wg-toolkit-output.txt
cat /etc/leikwan-wg-toolkit/pbr/static-routes.conf
ip route get LANDING_ADDRESS
```

如果系统已有同目标但不同出口的手工规则，菜单“一键为当前 Reality 落地机指定出口”会提示冲突。未确认接管前，脚本不会重复添加冲突规则。
