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

### 0.2.9-alpha

- 修复多落地机状态语义：添加 landing profile 不再等于切换 Xray 出站，只有“切换当前落地机”会事务化改写 outbound。
- 切换 landing 会先显示编号列表和确认摘要，再执行 `xray run -test`、`nc`、重启服务；失败自动回滚，不更新 current/outputs。
- doctor、部署总览和 PBR 默认以利群中转机的 Xray 实际 outbound 为准，并提示 current.env 与实际出站是否一致。
- 海外落地机输出新增 `LANDING_DIRECT_LINK`，仅用于直连 Reality 测试，不是最终三机链式客户端链接。

### 0.2.7-alpha

- 新增 `BBR / 系统优化`，可查看拥塞控制状态、启用 `bbr + fq`，也可只删除本项目 sysctl 文件恢复默认。
- 新增多落地机配置管理，支持保存多个 `landing-*.env`、测试、切换 active landing，并在切换失败时回滚 Xray 配置。
- 公网入口转发目标支持 `direct-leikwan-xray`、`ix-qianhai`、`ix-shanghai` 和自定义目标；IX 示例只使用 `<IX_QIANHAI_ENDPOINT>` / `<IX_SHANGHAI_ENDPOINT>` 占位符。
- 新增 `--refresh-forward-target`，用于 nftables/iptables 模式下刷新域名转发目标解析。

### 0.2.6-alpha

- 新增 UDP / WireGuard 质量检测，用 30 秒 ping 采样、握手时间和 `wg transfer` 增量判断 UDP 是否稳定。
- 新增多公网入口机管理，可保存多个 `entry-*.env`、测试入口质量、推荐最佳入口并生成多条客户端链接。
- 公网入口机支持家宽 DDNS 入口模式，`cloud-entry.env` 会记录 `CLOUD_ENDPOINT_TYPE=ddns`。
- IPv4 PBR 增加 Reality 落地机出口质量测试，可比较 `main`、`T_9929`、`T_CN2` 和已配置线路组。
- 新增断点续跑状态 `/etc/leikwan-wg-toolkit/state.json` 和脱敏故障报告 `/root/leikwan-debug-report.txt`。

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
- 多入口参数目录：`/etc/leikwan-wg-toolkit/entries/`
- 多入口客户端链接：`/etc/leikwan-wg-toolkit/outputs/client-links.txt`
- 多落地机目录：`/etc/leikwan-wg-toolkit/landings/`
- 公网入口转发目标目录：`/etc/leikwan-wg-toolkit/forward-targets/`
- 断点续跑状态：`/etc/leikwan-wg-toolkit/state.json`
- 脱敏故障报告：`/root/leikwan-debug-report.txt`
- 快捷命令：`/usr/local/bin/lq`、`/usr/local/bin/LQ`
- BBR sysctl：`/etc/sysctl.d/99-leikwan-bbr.conf`
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
  Version: 0.2.9-alpha
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
UDP / WireGuard 质量检测
多公网入口机管理
BBR / 系统优化
多落地机管理
公网入口转发目标管理
生成脱敏故障报告
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

`--rebuild-outputs` 参数优先级：CLI 参数、`/etc/leikwan-wg-toolkit/outputs/*.env`、`/root/leikwan-wg-toolkit-output.txt`、`CLIENT_LINK` 反解析、当前 wg/xray/realm/nftables/iptables 配置。

公网入口机如果 outputs 丢失，`doctor` 会优先尝试从 `wg1`、`wg1.conf`、`realm-leikwan.toml`、nftables/iptables 项目转发配置中无交互重建 `cloud-entry.env`。无法安全重建时才提示手动运行 `--rebuild-outputs`。

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
FORWARD_TARGET_MODE=direct-leikwan-xray
FORWARD_TARGET_ADDRESS=10.198.1.1
FORWARD_TARGET_PORT=30000
FORWARD_TARGET_RESOLVED_IP=10.198.1.1
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

公网入口机部署时 `CLOUD_ENDPOINT` 支持三种来源：

1. 自动检测公网 IPv4。
2. 手动输入公网 IPv4。
3. 输入 DDNS 域名。

选择 DDNS 时，`cloud-entry.env` 会写入：

```text
CLOUD_ENDPOINT_TYPE=ddns
CLOUD_ENDPOINT=<DDNS_DOMAIN>
```

doctor 会检查域名 A 记录解析，并提示家宽上行、运营商 UDP QoS 或 NAT 变化可能影响入口质量。

### 公网入口转发目标

默认转发目标仍是：

```text
direct-leikwan-xray: 10.198.1.1:30000
```

高级功能里的“公网入口转发目标管理”可以切换为：

- `ix-qianhai`：前海 IX 目标，地址由用户输入，例如 `<IX_QIANHAI_ENDPOINT>`。
- `ix-shanghai`：上海 IX 目标，地址由用户输入，例如 `<IX_SHANGHAI_ENDPOINT>`。
- `custom`：自定义 IP/域名 + 端口。

选择 IX 目标会绕过利群本机 `10.198.1.1:30000` Xray 入口，请确认 IX 侧已经提供兼容服务。`nftables` / `iptables` DNAT 只能写 IP，域名目标会先解析 A 记录并保存 `FORWARD_TARGET_RESOLVED_IP`；域名变化后运行：

```bash
sudo bash wg-toolkit.sh --refresh-forward-target
```

`realm` 模式可以直接使用域名 remote。

## UDP / WireGuard 质量检测

高级功能里的“UDP / WireGuard 质量检测”用于判断公网入口机到利群中转机的原生 WG UDP 链路是否稳定。它会检查：

- `wg show` 最新握手时间。
- 对端 WG IP 的 30 秒 ping 采样、丢包率、min/avg/max/mdev。
- `wg transfer` 计数是否增长。
- 如果本机已有 `iperf3`，会提示可选压测命令，但不会强制安装。

结论会用 `[OK] UDP 正常`、`[WARN] 疑似 UDP QoS`、`[WARN] 疑似入口机线路差` 或 `疑似利群侧出口问题` 这类提示归类。UoT/Phantun 这类方案虽然可用于某些 UDP QoS 场景，但不适合进入本项目默认跨境主线；本工具只把它作为背景解释，不集成实现。

## 多公网入口机

高级功能里的“多公网入口机管理”把入口参数保存到：

```text
/etc/leikwan-wg-toolkit/entries/entry-<name>.env
```

每个入口包含：

```text
ENTRY_NAME=
CLOUD_PUBLIC_KEY=
CLOUD_ENDPOINT=
CLOUD_WG_PORT=
CLIENT_ENTRY_PORT=
FORWARD_MODE=
LAST_RTT=
LAST_PACKET_LOSS=
ENABLED=yes
```

利群中转机可以添加多个入口 Peer。脚本追加 Peer 时不会覆盖旧 Peer；如果多个入口复用同一个 WG 地址，需要按实际网络规划确认不会冲突。入口管理支持查看、删除、质量测试、推荐最佳入口，并可生成多条 `CLIENT_LINK` 到：

```text
/etc/leikwan-wg-toolkit/outputs/client-links.txt
```

## BBR / 系统优化

高级功能里的“BBR / 系统优化”只管理本项目独立文件：

```text
/etc/sysctl.d/99-leikwan-bbr.conf
```

普通用户推荐使用“启用 BBR + fq”即可。它写入：

```text
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
```

判断 BBR 是否启用以 sysctl 为准：`net.ipv4.tcp_congestion_control=bbr` 且 `net.core.default_qdisc=fq` 即视为启用。`tcp_bbr` 是否出现在 `lsmod` 只作为 INFO，因为有些内核会内建模块而不在 `lsmod` 中列出。

恢复时只删除 `99-leikwan-bbr.conf` 并执行 `sysctl --system`，不会删除用户已有的其他 BBR/sysctl 文件。如果选择执行利群官方 `optimize.sh`，脚本会要求输入 `YES` 二次确认，下载到 `/root/optimize.sh`，显示 `sha256sum`，并在执行前备份 `sysctl -a`。

## 多落地机管理

高级功能里的“多落地机管理”把每个落地保存为：

```text
/etc/leikwan-wg-toolkit/landings/landing-<name>.env
```

添加 landing profile 只保存参数，不会修改利群 Xray outbound，也不会重启 `xray-leikwan`。如果要真正切换出站，必须进入：

```text
高级功能 -> 多落地机管理 -> 切换当前落地机
```

当前激活落地是“利群中转机”的状态记录，保存在：

```text
/etc/leikwan-wg-toolkit/landings/current
/etc/leikwan-wg-toolkit/landings/current.env
```

切换 active landing 时，脚本会先展示编号列表和确认摘要，然后备份当前 Xray 配置，生成临时配置并执行 `xray run -test`，再用 `nc` 测试目标 `LANDING_ADDRESS:LANDING_PORT`。全部通过后才覆盖配置、重启 `xray-leikwan`、更新 `current.env`、outputs 和 `client-link.txt`；失败会回滚旧配置。

切换落地不会改变客户端入口的 `ENTRY_UUID` / `VLESSENC_ENCRYPTION`，通常客户端链接不需要变化。菜单里的“查看当前链式客户端链接”会显示：

```text
ACTIVE_LANDING_NAME=
ACTIVE_LANDING_ADDRESS=
ACTIVE_LANDING_PORT=
CLIENT_LINK=
```

如果 `current.env` 与 Xray 实际 outbound 不一致，doctor 和部署总览会输出 WARN。可用“切换当前落地机”重新应用目标落地，或用“从 Xray 实际 outbound 修复 current 状态”只修复状态记录，不改 Xray 配置、不重启服务。

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
LANDING_DIRECT_LINK=vless://<LANDING_UUID>@<LANDING_PUBLIC_IP>:30004?type=raw&security=reality&pbk=<LANDING_PUBLIC_KEY>&fp=chrome&sni=www.microsoft.com&sid=<LANDING_SHORT_ID>&flow=xtls-rprx-vision#Landing-Direct-Test
```

`LANDING_DIRECT_LINK` 是直连落地 Reality 测试链接，不是三机链式代理最终客户端链接。最终 `CLIENT_LINK` 由利群中转机生成，入口是公网入口机地址。Reality PrivateKey 只保存在落地机配置中，不输出给利群复制。

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

PBR 子菜单里的“一键为当前 Reality 落地机指定出口”默认读取 Xray 实际 outbound。如果 `current.env` 与 Xray outbound 不一致，脚本会提示并默认继续使用真正生效的 Xray outbound，避免给未生效的 landing 写错 PBR。

“测试落地机出口质量”可选择当前 Xray 实际 outbound，也可从 landing profile 列表选择任意落地机。它会对 `<LANDING_PUBLIC_IP>:LANDING_PORT` 分别查看 `main`、`T_9929`、`T_CN2` 和已配置线路组的路由，结合 `nc` 可达性和可选 ping/mtr 输出推荐线路组。确认后可一键把当前 Reality 落地机写入静态 PBR 规则，例如：

```text
<LANDING_PUBLIC_IP>/32 9929
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

## 断点续跑与脱敏故障报告

脚本会在 `/etc/leikwan-wg-toolkit/state.json` 记录当前角色、已完成步骤、缺少字段和下一步建议。再次进入 `lq` 主菜单时，会先从 outputs、`client-link.txt`、Xray outbound 和 PBR 配置重新校验状态；只有确实缺少字段时，才提示继续上次流程、查看状态或忽略。已完成的利群中转机会显示“无需操作，链路已完成”。

如果 PBR 规则当前已生效但 `leikwan-pbr.service` 未安装，doctor 会提示重启后规则可能丢失。修复路径是：`高级功能 -> IPv4 多出口策略路由 -> 安装 / 重启 PBR 开机恢复服务`。

高级功能里的“生成脱敏故障报告”会输出：

```text
/root/leikwan-debug-report.txt
```

报告会收集系统信息、地址/路由、`wg show`、leikwan 服务状态、端口监听、nft/iptables 项目规则、Xray 配置测试、`doctor --verbose` 和 outputs 字段完整性。生成前会把敏感内容替换为 `<PUBLIC_IP>`、`<WG_PUBLIC_KEY>`、`<UUID>`、`<VLESSENC>`、`<CLIENT_LINK>` 等占位符，便于发给别人排查而不泄露真实参数。

## 卸载

高级功能里的“卸载”分角色卸载：

- 公网入口机：删除本项目创建的 `wg1`、`leikwan-forward-nft.service`、`leikwan-forward-iptables.service`、`realm-leikwan.service` 和本项目转发规则。
- 利群中转机：删除本项目创建的 `wg0`，Xray 配置删除需要二次确认。
- 海外落地机：Xray 配置删除需要二次确认。
- 可单独删除本项目托管的 IPv4 PBR 运行中规则，未托管同 priority 规则会保留。
- 可单独删除 IPv6 `V6_LOCKDOWN`。
- 可删除本项目创建的 `lq` / `LQ` 快捷命令；如果同名文件不是本项目创建，会 WARN 并保留。

卸载不会删除用户已有的非本项目服务，也不会卸载软件包。Xray 二进制默认保留。
