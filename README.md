# leikwan-wg-toolkit

`leikwan-wg-toolkit` v0.4 是一个面向“公网入口 + 利群中转”的纯四层 TCP 转发工具。

它只做两件事：

- 使用 EasyTier 让公网入口机和利群中转机进入同一个虚拟 IPv4 网络。
- 使用 nftables 把公网入口端口转发到任意后端 TCP 目标。

脚本不部署后端代理协议，不管理后端服务，也不生成任何客户端协议链接。后端可以是用户自备的任意 TCP 服务。

## 架构

```text
客户端
  -> cloud-entry 公网地址:ENTRY_PORT
  -> cloud-entry nftables DNAT
  -> leikwan-relay EasyTier IP:ENTRY_PORT
  -> leikwan-relay nftables DNAT/SNAT
  -> TARGET_HOST:TARGET_PORT
```

默认 EasyTier 虚拟网段：

| 项目 | 默认值 |
| --- | --- |
| EasyTier 网段 | `10.198.1.0/24` |
| 利群中转机 | `10.198.1.1` |
| 第一台公网入口机 | `10.198.1.2` |
| EasyTier 监听 | `tcp/8301` |

利群环境建议走 `8000-9000` 白名单端口段。本项目默认使用 `8301/tcp`，避免 EasyTier 官方示例端口 `11010` 在部分线路上出现高延迟。

## 快速开始

普通用户只需要走三步快速配对。

在利群中转机 B：

```bash
sudo bash wg-toolkit.sh pair relay-init
```

复制输出的 `LEIKWAN EASYTIER NETWORK` 整段配对码。

在公网入口机 A：

```bash
sudo bash wg-toolkit.sh pair entry-join
```

粘贴 B 生成的网络码，输入本机公网 IP 或域名，确认后脚本会安装并启动 EasyTier entry 服务，然后输出 `LEIKWAN EASYTIER ENTRY` 入口码。

回到利群中转机 B：

```bash
sudo bash wg-toolkit.sh pair relay-join
```

粘贴 A 生成的入口码，脚本会登记入口并启动 `easytier-relay.service`。

之后先在 A 公网入口机配置一次入口端口池。A 只做这一件事，后续新增 / 修改 / 删除后端都不需要再动 A。

在 A 公网入口机：

```bash
sudo bash wg-toolkit.sh entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
```

它会生成端口池 DNAT：

```text
A:10000-19999 -> 10.198.1.1:10000-19999
```

也就是保持原端口不变，把公网入口端口池转给 B 的 EasyTier IP。

然后在 B 利群中转机添加后端目标：

```bash
sudo bash wg-toolkit.sh forward add
```

按提示输入转发名称、入口端口、后端地址和端口。脚本会自动检测出口网卡 / 路由表，写入 TAB 格式 `forwards.tsv`，并应用 B 侧 nftables。

以后新增、修改、删除后端只在 B 上执行：

```bash
sudo bash wg-toolkit.sh forward add
sudo bash wg-toolkit.sh forward edit hk
sudo bash wg-toolkit.sh forward delete hk
sudo bash wg-toolkit.sh forward list
sudo bash wg-toolkit.sh forward apply-relay
```

菜单入口：

```text
主菜单 -> 快速转发
```

安全组需要放行：

- A 公网入口 EasyTier：`tcp/8301`
- A 公网入口端口池：默认 `tcp/10000-19999`

如果只想暴露少量端口，可以把端口池设置为 `10001-10020`。

## 多入口与多目标

入口配置位于：

```text
/etc/leikwan-wg-toolkit/entries/entries.tsv
```

格式：

```text
entry_name  public_host      et_ip        easytier_protocol  easytier_port  weight  enabled
aliyun      192.0.2.10       10.198.1.2   tcp                8301          100     true
tencent     198.51.100.20    10.198.1.3   tcp                8301          50      true
```

转发目标高级配置位于：

```text
/etc/leikwan-wg-toolkit/forwards/forwards.tsv
```

格式是 **8 列 TAB 分隔**。默认推荐在 B 上使用 `lq forward add/edit/delete` 或菜单生成，不建议手工空格对齐：

```text
name  entry_port  target_host     target_port  out_iface  route_table  enabled  comment
hk    10001       203.0.113.30    30004        eth1       T_CN2        true     hk-target
```

高级用户如果必须命令行写入，请用 `printf` 明确输出 TAB：

```bash
sudo install -d -m 700 /etc/leikwan-wg-toolkit/forwards
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  'hk' '10001' '203.0.113.30' '30004' 'eth1' 'T_CN2' 'true' 'hk-target' |
  sudo tee -a /etc/leikwan-wg-toolkit/forwards/forwards.tsv >/dev/null
```

如果字段没有用 TAB 分隔，脚本会拒绝解析和应用 nftables，避免悄悄生成空规则。

脚本会生成：

```text
/etc/leikwan-wg-toolkit/outputs/forward-endpoints.txt
/etc/leikwan-wg-toolkit/outputs/forward-endpoints.tsv
```

示例输出只包含 TCP 入口信息，不包含任何代理协议参数。

EasyTier/tun 转发默认启用 TCP MSS clamp：

```text
tcp flags syn tcp option maxseg size set 1320
```

这条规则会写入项目 nftables 表，随 `leikwan-nft-forward.service` 持久化，用于避免双 NAT + tun 场景下部分 TCP 后端出现“有延迟但无法建立应用层连接”。

默认 MSS 为实测稳定值 `1320`。如果个别线路仍不稳定，可临时用环境变量或配置文件降到 `1280` / `1200`：

```bash
sudo install -d -m 700 /etc/leikwan-wg-toolkit/nft
printf 'TCP_MSS_CLAMP=1280\nENABLE_MSS_CLAMP=true\n' | sudo tee /etc/leikwan-wg-toolkit/nft/mss.env >/dev/null
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
sudo lq forward apply-relay
```

## 诊断

```bash
sudo bash wg-toolkit.sh --doctor
sudo bash wg-toolkit.sh --doctor --verbose
```

doctor 只检查 v0.4 主线组件：

- EasyTier binary 和 systemd 服务
- EasyTier 虚拟 IP
- entry peer 可达性
- nftables 项目表
- forwards / entries 配置
- target TCP 可达性
- PBR / BBR / 基础网络状态

## 安全边界

- nftables 只管理 `table inet leikwan_forward`，不 flush 全局 ruleset。
- EasyTier 网络密钥只保存在本机配置和配对码中，故障报告会脱敏。
- `TARGET_HOST:TARGET_PORT` 是用户自备 TCP 服务，脚本不会识别或改写后端协议。
- 默认不依赖 EasyTier 公共节点，只使用用户自己的公网入口机作为 peer。

## 快捷命令

首次进入菜单时脚本会尝试安装：

```bash
lq
LQ
```

之后可以直接运行：

```bash
sudo lq
```

## 卸载

```bash
sudo bash wg-toolkit.sh --uninstall
```

卸载会停止并删除 EasyTier / nftables 本项目服务，可选删除 EasyTier 二进制和 `/etc/leikwan-wg-toolkit`。

旧版本组件清理放在 `高级功能 -> legacy 清理`，默认不会执行。

## 文档

- [v0.4 架构](docs/architecture-v0.4-easytier.md)
- [EasyTier 组网](docs/easytier-networking.md)
- [EasyTier 快速配对](docs/easytier-pairing.md)
- [nftables 转发](docs/nftables-forwarding.md)
- [多公网入口](docs/multi-entry.md)
- [forwards.tsv](docs/forwards.tsv.md)
- [PBR](docs/pbr.md)
- [验收测试](docs/acceptance-test.md)
- [排错](docs/troubleshooting.md)
- [legacy 清理](docs/legacy-cleanup.md)
