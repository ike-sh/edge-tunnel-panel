# Leikwan Toolkit

`leikwan-wg-toolkit` v0.4.0-alpha 是面向“公网入口 A + 利群主机 B”的快速组网与四层 TCP 转发工具。仓库名沿用历史名称，但 v0.4 主线已经改为 **EasyTier + nftables**。

脚本只管理 A/B：

- A：公网入口机，暴露入口端口池。
- B：利群主机，管理后端 TCP 转发目标和多出口策略。
- C：任意后端 TCP 服务，由用户自备，脚本不部署、不识别、不生成任何代理协议配置。

不部署 Xray / VLESS / Reality / FRP / WireGuard / Phantun / realm 主流程，也不生成代理客户端链接。

## 安装

推荐安全安装：

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
```

管道安装只安装，不会自动进入菜单：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/scripts/bootstrap.sh | bash
lq
```

GitHub 下载慢时可设置镜像轮询：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

EasyTier 包较大，安装器会下载到 `.part` 临时文件，校验文件大小和压缩包完整性后才安装。失败时会列出已尝试 URL，并允许输入本地 EasyTier zip/tar.gz。

## 启动横幅

启动菜单会显示：

```text
╔════════════════════════════════════════════════════════════════════╗
║ Leikwan Toolkit                                                   ║
║ 利群快速组网工具                                                  ║
║ Author : ike-sh                                                   ║
║ Version: 0.4.0-alpha                                              ║
║ GitHub : https://github.com/ike-sh/leikwan-wg-toolkit             ║
╚════════════════════════════════════════════════════════════════════╝
```

## 推荐流程

快速组网菜单编号：

```text
1. 我现在在利群主机：先执行 DNS / IPv4 优先修复
2. 我现在在利群主机：生成给公网入口的 EasyTier 网络码
3. 我现在在公网入口：粘贴利群网络码，部署公网入口
4. 我现在在利群主机：粘贴公网入口码，完成组网
5. 我现在在公网入口：配置入口端口池
6. 我现在在利群主机：添加后端转发目标
7. IPv4 多出口策略路由 / PBR
8. 查看完整分步说明
0. 返回
```

在 B 利群主机：

```bash
sudo lq pair relay-init
```

复制 EasyTier 网络码到 A。

在 A 公网入口机：

```bash
sudo lq pair entry-join
```

粘贴网络码，部署 EasyTier entry，复制入口码回 B。

在 B 利群主机：

```bash
sudo lq pair relay-join
```

粘贴入口码，完成 EasyTier 组网。

在 A 只配置一次入口端口池：

```bash
sudo lq entry expose-range --range 10001-10020 --relay-ip 10.198.1.1
```

常用小白流程建议先开放 `10001-10020`。如果需要更大端口池，再使用默认推荐范围 `10000-19999`。

如果后端目标需要固定走 CN2 / 9929 等出口，先在 B 配置 PBR，再添加后端转发目标：

```bash
sudo lq
# 快速组网 -> 7. IPv4 多出口策略路由 / PBR
```

以后新增、修改、删除后端只在 B 操作：

```bash
sudo lq forward add
sudo lq forward edit service-a
sudo lq forward delete service-a
sudo lq forward list
sudo lq forward apply-relay
```

外部访问链路：

```text
client -> A_PUBLIC_HOST:ENTRY_PORT -> A nftables -> EasyTier -> B nftables -> TARGET_HOST:TARGET_PORT
```

## 默认参数

| 项目 | 默认值 |
| --- | --- |
| EasyTier 网段 | `10.198.1.0/24` |
| B relay IP | `10.198.1.1` |
| 第一台 A entry IP | `10.198.1.2` |
| EasyTier 监听 | `tcp/8301` |
| 入口端口池 | `10000-19999/tcp` |
| TCP MSS clamp | `1320` |

EasyTier 默认端口 `8301/tcp` 位于利群推荐 `8000-9000` 白名单范围。`11010` 只是 EasyTier 官方常见示例端口，不作为本项目默认值。

## nftables

脚本只管理：

```text
table inet leikwan_forward
```

A 侧端口池规则示例：

```text
tcp dport 10000-19999 dnat ip to 10.198.1.1
```

B 侧后端规则示例：

```text
iifname "tun0" tcp dport 10001 dnat ip to 203.0.113.30:37592
```

EasyTier/tun 转发默认启用 MSS clamp：

```text
tcp flags syn tcp option maxseg size set 1320
```

如果仍然出现“有延迟但无法连接”，可在 `/etc/leikwan-wg-toolkit/nft/mss.env` 中把 `TCP_MSS_CLAMP` 降到 `1280` 或 `1200` 后重新应用 A/B nftables。

## 转发出口自动识别

在 B 执行 `lq forward add` / `lq forward edit` 时，脚本会自动执行：

```bash
ip route get TARGET_IP
```

并推荐实际出口接口和 PBR 路由表，例如：

```text
dev eth1 table T_CN2 src 10.8.1.42
```

对应写入：

```text
out_iface=eth1
route_table=T_CN2
```

`lq forward apply-relay` 会在应用 nftables 前重新校验 `forwards.tsv` 与实际路由是否一致。发现配置 `eth0/-` 但实际是 `eth1/T_CN2` 时，会提示自动修正，避免 A 已经到 B、但 B 转后端超时。

非交互自动修正：

```bash
sudo lq forward apply-relay --auto-fix-route
```

如果系统缺少 `nc`，链路测试会提示安装 `netcat-openbsd`，不会直接 `command not found`。

## PBR

PBR 目标必须是合法 IPv4 或 CIDR。单个 IP 自动转为 `/32`，非法值会被拒绝，不写入配置。

快速组网菜单中 PBR 是第 7 项。需要指定 CN2 / 9929 时，推荐先配置 PBR，再执行第 6 项添加后端转发目标。如果先添加了转发目标，后添加 PBR，请重新执行：

```bash
sudo lq forward apply-relay --auto-fix-route
```

线路组使用菜单选择：

```text
1. CN2 -> T_CN2
2. 9929 -> T_9929
3. 自定义路由表
0. 返回
```

配置文件：

```text
/etc/leikwan-wg-toolkit/pbr/static-routes.conf
```

应用：

```bash
sudo lq --pbr-apply
```

历史坏数据会被跳过并 WARN，不会导致脚本崩溃。

## 诊断

```bash
sudo lq --doctor
sudo lq --doctor --verbose
```

doctor 检查 EasyTier、nftables、入口端口池、后端转发、PBR、MSS clamp、BBR 和基础网络。检查命令失败只会输出 `[WARN]` / `[FAIL]`，不会因为 `grep`、`nft`、`ping`、`nc`、`ip route get` 等失败直接退出。

## 卸载

主菜单选择“卸载全部”，或执行：

```bash
sudo lq --uninstall
```

卸载会二次确认，并只清理本项目服务、配置、nftables 表、EasyTier 二进制、快捷命令和日志。服务或文件不存在时会跳过，不会中途崩溃。

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
