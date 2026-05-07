# 三机链式部署流程

本文说明 `leikwan-wg-toolkit` 的三机角色、参数交换和推荐部署顺序。

## 链路结构

```text
客户端
  |
  | VLESS raw security=none，入口端口 30000
  v
公网入口机
  |
  | nftables/iptables/realm: 0.0.0.0:30000 -> 10.198.1.1:30000
  | WireGuard 原生 UDP，默认 8301/udp
  v
利群中转机
  |
  | Xray VLESS outbound + Reality
  v
海外落地机
  |
  v
Internet
```

公网入口机到利群中转机之间只使用原生 WireGuard UDP。

## 角色一：公网入口机

职责：

- 对公网暴露 `30000` 客户端入口。
- 运行 WireGuard `wg1`。
- 使用 `nftables` / `iptables` 内核转发，或兼容模式 `realm`，把公网入口转发到利群中转机的 WG 内网地址。

默认配置：

```text
wg1 地址：10.198.1.2/24
WireGuard ListenPort：8301/udp
Peer AllowedIPs：10.198.1.1/32
转发：0.0.0.0:30000/tcp -> 10.198.1.1:30000
默认模式：nftables
```

需要输入：

```text
利群中转机 PublicKey
```

输出：

```text
CLOUD_PUBLIC_KEY
CLOUD_ENDPOINT
CLOUD_WG_PORT
CLIENT_ENTRY_PORT
FORWARD_MODE
FORWARD_TARGET
FORWARD_TARGET_MODE
FORWARD_TARGET_ADDRESS
FORWARD_TARGET_PORT
FORWARD_TARGET_RESOLVED_IP
```

## 角色二：利群中转机

职责：

- 和公网入口机建立 WireGuard UDP。
- 在 `10.198.1.1:30000` 监听客户端入口流量。
- 通过 Xray Reality outbound 转发到海外落地机。
- 阻断 bittorrent。

WireGuard 默认配置：

```text
wg0 地址：10.198.1.1/24
Endpoint：CLOUD_ENDPOINT:CLOUD_WG_PORT
AllowedIPs：10.198.1.2/32
PersistentKeepalive：25
```

Xray inbound：

```text
listen：10.198.1.1
port：30000
protocol：vless
network：raw
security：none
decryption：VLESSENC_DECRYPTION
```

Xray outbound：

```text
protocol：vless
address：LANDING_ADDRESS
port：LANDING_PORT
encryption：none
flow：xtls-rprx-vision
network：raw
security：reality
serverName：LANDING_SERVER_NAME
publicKey：LANDING_PUBLIC_KEY
shortId：LANDING_SHORT_ID
fingerprint：chrome
spiderX：/
```

输入：

```text
CLOUD_PUBLIC_KEY
CLOUD_ENDPOINT
CLOUD_WG_PORT
LANDING_ADDRESS
LANDING_PORT
LANDING_UUID
LANDING_PUBLIC_KEY
LANDING_SHORT_ID
LANDING_SERVER_NAME
```

输出：

```text
LEIKWAN_PUBLIC_KEY
客户端导入链接
```

## 角色三：海外落地机

职责：

- 运行 Xray Reality inbound。
- 接收利群中转机 outbound。

默认配置：

```text
listen：0.0.0.0
port：30004
protocol：vless
decryption：none
network：raw
security：reality
target：www.microsoft.com:443
serverNames：[www.microsoft.com]
flow：xtls-rprx-vision
```

脚本会生成：

```text
Reality UUID
x25519 PrivateKey/PublicKey
shortId
```

输出给利群中转机：

```text
LANDING_ADDRESS
LANDING_PORT
LANDING_UUID
LANDING_PUBLIC_KEY
LANDING_SHORT_ID
LANDING_SERVER_NAME
LANDING_FLOW
```

不会输出 Reality PrivateKey。PrivateKey 只保存在海外落地机的 `/usr/local/etc/xray/leikwan/config.json` 中。

## 推荐执行顺序

最省心的方式是进入主菜单 `1. 极速部署向导`。新版向导会先识别当前机器角色，只显示这台机器需要做的几件事。

安装或进入菜单后会自动创建快捷命令。以后可以直接运行：

```bash
lq
```

大写 `LQ` 也会创建作为兼容入口；Linux 命令区分大小写，日常推荐小写 `lq`。

默认主菜单保持很短：

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

高级功能里保留完整手动部署、PBR、DNS、IPv6、BBR、多入口、多落地、转发目标、故障报告、备份、卸载、安装 / 修复快捷命令等入口。

### 1. 海外落地机先生成 Reality 参数

在海外落地机执行：

```text
极速部署向导 -> 部署 / 更新 Reality 落地
```

拿到：

```text
LANDING_ADDRESS
LANDING_PORT
LANDING_UUID
LANDING_PUBLIC_KEY
LANDING_SHORT_ID
LANDING_SERVER_NAME
LANDING_FLOW
```

输出文件：

```text
/etc/leikwan-wg-toolkit/outputs/landing-server.env
/root/leikwan-wg-toolkit-output.txt
```

### 2. 利群中转机生成 WireGuard 公钥

在利群中转机执行：

```text
极速部署向导 -> 查看 / 生成 LEIKWAN_PUBLIC_KEY
```

拿到：

```text
LEIKWAN_PUBLIC_KEY
```

WireGuard 身份文件固定为：

```text
/etc/wireguard/wg0_privatekey
/etc/wireguard/wg0_publickey
```

重复执行不会改变 `LEIKWAN_PUBLIC_KEY`。只有进入“高级功能 -> 查看 / 生成本机 WireGuard 身份 -> 重置本机 WireGuard Key”并二次确认才会重置。

CLI 直接查看，不进入交互菜单：

```bash
sudo bash wg-toolkit.sh --show-wg-identity --role leikwan
lq --show-wg-identity --role leikwan
```

### 3. 公网入口机部署

在公网入口机执行：

```text
极速部署向导 -> 导入 / 输入 LEIKWAN_PUBLIC_KEY
极速部署向导 -> 部署 / 更新 WireGuard + 转发
```

拿到：

```text
CLOUD_PUBLIC_KEY
CLOUD_ENDPOINT
CLOUD_WG_PORT
CLIENT_ENTRY_PORT
```

```text
/etc/leikwan-wg-toolkit/outputs/cloud-entry.env
/root/leikwan-wg-toolkit-output.txt
```

### 4. 回到利群中转机完成全链路

把 `cloud-entry.env` 和 `landing-server.env` 通过“极速部署向导”的导入步骤导入，也可以在“高级功能 -> 导入参数文件”里导入，或直接粘贴向导输出。利群中转机部署会优先读取：

```text
/etc/leikwan-wg-toolkit/outputs/cloud-entry.env
/etc/leikwan-wg-toolkit/outputs/landing-server.env
/root/leikwan-wg-toolkit-output.txt
```

然后执行：

```text
极速部署向导 -> 导入 CLOUD 参数
极速部署向导 -> 导入 LANDING 参数
极速部署向导 -> 完成链式代理部署
```

脚本会：

- 更新 `wg0`
- 启动 `wg-quick@wg0`
- 运行 `xray vlessenc`
- 写入 Xray 中转配置
- 测试配置
- 启动 `xray-leikwan.service`，或在用户明确选择“备份并覆盖”时写入带项目标记的 `xray.service`
- 输出客户端链接

最终输出：

```text
/etc/leikwan-wg-toolkit/outputs/leikwan-relay.env
/etc/leikwan-wg-toolkit/outputs/client-link.txt
/root/leikwan-wg-toolkit-output.txt
```

## CLIENT_LINK

最终链接格式：

```text
vless://<ENTRY_UUID>@<CLOUD_PUBLIC_IP>:30000?type=raw&security=none&encryption=<VLESSENC_ENCRYPTION>#Leikwan-WG-Xray-Reality
```

只使用 `VLESSENC_ENCRYPTION`，不要把 `VLESSENC_DECRYPTION` 放进客户端链接。

主菜单 `2. 查看复制参数 / 客户端链接` 可以随时重新显示最终链接。

如果从旧版本升级、手动恢复配置，或者 outputs 文件丢失，可以从当前已运行配置重建：

```bash
sudo bash wg-toolkit.sh --rebuild-outputs
```

重建会尽量从 WireGuard、realm、Xray 配置中恢复 `cloud-entry.env`、`landing-server.env`、`leikwan-relay.env` 和 `client-link.txt`。如果旧 `/root/leikwan-wg-toolkit-output.txt` 已有 `CLIENT_LINK`，会自动迁移。

如果无法从旧输出读取 `VLESSENC_ENCRYPTION`，脚本会生成 partial `leikwan-relay.env`，但不会生成 `client-link.txt`。这时补充客户端 encryption 后重跑：

```bash
sudo bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption '<VLESSENC_ENCRYPTION>'
```

## 断点续跑

工具会把当前角色、已完成步骤、缺少字段和下一步建议写入：

```text
/etc/leikwan-wg-toolkit/state.json
```

再次进入 `lq` 主菜单时，如果发现流程还没完成，会先显示：

```text
检测到未完成部署
```

用户可以选择继续上次流程、查看状态或忽略。这个提示只帮助减少三台机器之间来回复制时的断点遗忘，不会自动改动主链路配置。

## 多入口与 DDNS

公网入口机部署时，`CLOUD_ENDPOINT` 可以选择自动检测公网 IPv4、手动输入公网 IP，或填写 DDNS 域名。选择 DDNS 时会写入：

```text
CLOUD_ENDPOINT_TYPE=ddns
CLOUD_ENDPOINT=<DDNS_DOMAIN>
```

利群中转机的高级功能里可以管理多个公网入口，入口文件保存在：

```text
/etc/leikwan-wg-toolkit/entries/entry-<name>.env
```

多入口管理支持添加、删除、查看、测试质量、推荐最佳入口，并生成多条客户端链接。它会向 `wg0.conf` 追加 Peer，不覆盖旧 Peer。

## BBR、落地与转发目标

“BBR / 系统优化”只写入 `/etc/sysctl.d/99-leikwan-bbr.conf`，启用 `net.core.default_qdisc=fq` 和 `net.ipv4.tcp_congestion_control=bbr`。恢复时只删除这个文件，不动用户已有 sysctl。

“多落地机管理”把落地配置保存到：

```text
/etc/leikwan-wg-toolkit/landings/landing-<name>.env
/etc/leikwan-wg-toolkit/landings/current
/etc/leikwan-wg-toolkit/landings/current.env
```

添加 landing profile 只写 `landing-<name>.env`，不等于切换利群 Xray 出站。真正切换必须选择“切换当前落地机”：脚本会先展示编号列表和确认摘要，再生成临时 Xray 配置、执行 `xray run -test`、用 `nc` 测试落地端口，通过后才重启 `xray-leikwan` 并更新 `current/current.env`、outputs 和 `client-link.txt`；失败会回滚旧配置。

`current.env` 是利群中转机状态，不是海外落地机状态。海外落地机部署只输出 `LANDING_*` 和 `LANDING_DIRECT_LINK`；`LANDING_DIRECT_LINK` 只用于直连 Reality 测试，最终链式 `CLIENT_LINK` 仍由利群中转机生成。客户端入口参数通常不变，但 outputs 会增加 `ACTIVE_LANDING_NAME`、`ACTIVE_LANDING_ADDRESS`、`ACTIVE_LANDING_PORT`。

“公网入口转发目标管理”用于 cloud-entry 角色。默认仍是：

```text
direct-leikwan-xray -> 10.198.1.1:30000
```

可选 `ix-qianhai`、`ix-shanghai` 或 `custom`，IX 地址必须由用户输入，例如 `<IX_QIANHAI_ENDPOINT>` 或 `<IX_SHANGHAI_ENDPOINT>`。选择 IX target 会绕过利群本机 Xray 入口，请确认 IX 侧提供兼容服务。`nftables` / `iptables` 模式遇到域名 target 会先解析 A 记录，域名变化后运行：

```bash
sudo bash wg-toolkit.sh --refresh-forward-target
```

## 质量检测和故障报告

高级功能里的“UDP / WireGuard 质量检测”会用 30 秒 ping 采样、握手时间和 `wg transfer` 增量判断 WG UDP 链路质量。它只诊断原生 UDP，不引入 UoT/Phantun 或任何 TCP/fake TCP 隧道。

高级功能里的“生成脱敏故障报告”会写入：

```text
/root/leikwan-debug-report.txt
```

报告会脱敏公网 IP、公钥、UUID、VLESSENC、Reality key/shortId 和客户端链接，适合发给维护者排查。

## 角色向导

海外落地机看到：

```text
1. 部署 / 更新 Reality 落地
2. 查看 LANDING 参数
3. doctor
0. 返回
```

公网入口机看到：

```text
1. 导入 / 输入 LEIKWAN_PUBLIC_KEY
2. 部署 / 更新 WireGuard + 转发
3. 查看 CLOUD 参数
4. doctor
0. 返回
```

利群中转机看到：

```text
1. 查看 / 生成 LEIKWAN_PUBLIC_KEY
2. 导入 CLOUD 参数
3. 导入 LANDING 参数
4. 完成链式代理部署
5. 指定 Reality 落地机出口
6. 查看客户端链接
7. doctor
0. 返回
```

无法识别角色时，向导会让用户选择“海外落地机 / 公网入口机 / 利群中转机”。

## 幂等与备份

脚本重复执行时会复用已有 WireGuard PrivateKey，不会无故重复生成 peer 或重复插入 IPv6 规则。

所有写入前会显示摘要并要求确认，已有文件写入前会备份到：

```text
/var/backups/leikwan-wg-toolkit
```

快照备份包含：

- `/etc/wireguard`
- `/usr/local/etc/xray/leikwan/config.json`
- realm 配置
- 本项目 systemd realm 服务
- iptables rules
- DNS 修复相关配置
