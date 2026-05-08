# Leikwan Toolkit

`leikwan-wg-toolkit` v0.4.0-alpha 是面向“公网入口 + 利群主机”的快速组网与四层 TCP 转发工具。项目仍沿用仓库名，但交互标题统一为 **Leikwan Toolkit / 利群快速组网工具**，不再以 WireGuard 作为主线。

## 一键安装

推荐安装快捷命令：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/scripts/bootstrap.sh | bash
```

官方 GitHub 直接运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/wg-toolkit.sh)
```

下载到本地再执行：

```bash
curl -fsSL -o /root/wg-toolkit.sh https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/wg-toolkit.sh && chmod +x /root/wg-toolkit.sh && ln -sf /root/wg-toolkit.sh /usr/local/bin/lq && lq
```

Release 包安装：

```bash
curl -fsSL -o /tmp/leikwan-wg-toolkit.tar.gz https://github.com/ike-sh/leikwan-wg-toolkit/releases/latest/download/leikwan-wg-toolkit-0.4.0-alpha.tar.gz && tar -xzf /tmp/leikwan-wg-toolkit.tar.gz -C /root && cp /root/leikwan-wg-toolkit-0.4.0-alpha/wg-toolkit.sh /root/wg-toolkit.sh && chmod +x /root/wg-toolkit.sh && ln -sf /root/wg-toolkit.sh /usr/local/bin/lq && lq
```

如果 GitHub 下载慢，可以设置镜像轮询环境变量，脚本仍会优先尝试官方 GitHub，不把第三方镜像作为唯一入口：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://mirror1.example/https://github.com,https://mirror2.example/https://github.com"
```

## 推荐小白流程

1. 利群主机先执行 DNS / IPv4 优先修复。
2. 利群主机生成 EasyTier 网络码。
3. 公网入口粘贴网络码加入。
4. 利群主机粘贴入口码完成组网。
5. 公网入口配置端口池。
6. 利群主机添加后端转发。
7. 两边执行 doctor。

菜单路径：

```text
主菜单 -> 快速组网（分步提示）
```

利群主机如果无法下载 GitHub / EasyTier / release 包，优先执行：

```text
高级功能 -> DNS / IPv4 优先修复
```

或：

```text
快速组网（分步提示） -> 1
```

## 定位

它只做三件事：

- 使用 EasyTier 让公网入口机和利群主机进入同一个虚拟 IPv4 网络。
- 使用 nftables 把公网入口端口转发到任意后端 TCP 目标。
- 提供 PBR、IPv6 入站安全收口、BBR / DNS 辅助修复、诊断和备份清理工具。

脚本不部署后端代理协议，不管理后端服务，也不生成任何客户端协议链接。后端可以是用户自备的任意 TCP 服务。

## 主菜单

```text
1. 快速组网（分步提示）
2. 利群主机
3. 公网入口
4. 高级功能
5. 一键诊断
6. 卸载全部
0. 退出
```

利群主机菜单只放 B 侧能力：

```text
1. EasyTier 组网管理
2. 转发目标管理
3. IPv4 多出口策略路由
4. IPv6 入站安全收口
5. 查看利群主机状态
0. 返回
```

公网入口菜单只放 A 侧能力：

```text
1. EasyTier 组网管理
2. 公网入口机管理
3. 转发端口池
4. 查看公网入口状态
0. 返回
```

高级功能保留通用维护项：

```text
1. nftables 规则管理
2. 链路测试
3. DNS / IPv4 优先修复
4. BBR / 系统优化
5. 查看全部状态
6. 备份 / 恢复
7. 生成脱敏故障报告
8. legacy 清理
0. 返回
```

## 快速流程

进入 `快速组网（分步提示）` 后，脚本会先提醒利群主机优先执行 DNS / IPv4 修复，避免 IPv6 / DNS 默认环境导致 GitHub、raw.githubusercontent.com、GitHub release 下载失败。

在利群主机 B：

```bash
sudo lq pair relay-init
```

复制输出的 `LEIKWAN EASYTIER NETWORK` 配对码。

在公网入口机 A：

```bash
sudo lq pair entry-join
```

粘贴 B 生成的网络码，输入本机公网 IP 或域名，确认后脚本会安装并启动 EasyTier entry 服务，然后输出 `LEIKWAN EASYTIER ENTRY` 入口码。

回到利群主机 B：

```bash
sudo lq pair relay-join
```

粘贴 A 生成的入口码，脚本会登记入口并启动 `easytier-relay.service`。

之后先在 A 公网入口机配置一次入口端口池：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
```

它会生成端口池 DNAT：

```text
A:10000-19999 -> 10.198.1.1:10000-19999
```

然后在 B 利群主机添加后端目标：

```bash
sudo lq forward add
```

以后新增、修改、删除后端只在 B 上执行：

```bash
sudo lq forward add
sudo lq forward edit service-a
sudo lq forward delete service-a
sudo lq forward list
sudo lq forward apply-relay
```

菜单路径：

```text
利群主机 -> 转发目标管理
公网入口 -> 转发端口池
```

## 默认参数

| 项目 | 默认值 |
| --- | --- |
| EasyTier 网段 | `10.198.1.0/24` |
| 利群主机 | `10.198.1.1` |
| 第一台公网入口机 | `10.198.1.2` |
| EasyTier 监听 | `tcp/8301` |
| 公网入口端口池 | `10000-19999/tcp` |

利群环境建议走 `8000-9000` 白名单端口段。本项目默认使用 `8301/tcp`，避免 EasyTier 官方示例端口 `11010` 在部分线路上出现高延迟。

## nftables

- nftables 只管理 `table inet leikwan_forward`，不 flush 全局 ruleset。
- 高级功能中的 `nftables 规则管理` 可以查看当前规则、重新应用 A 侧入口规则、重新应用 B 侧转发规则、清理脚本生成的规则。
- 如果规则文件、nft table 或 service 不存在，菜单会用中文 WARN 提示，不会直接退出脚本。

EasyTier/tun 转发默认启用 TCP MSS clamp：

```text
tcp flags syn tcp option maxseg size set 1320
```

这条规则会写入项目 nftables 表，随 `leikwan-nft-forward.service` 持久化，用于避免双 NAT + tun 场景下部分 TCP 后端出现“有延迟但无法建立应用层连接”。

## 诊断

```bash
sudo lq --doctor
sudo lq --doctor --verbose
```

doctor 检查：

- EasyTier binary 和 systemd 服务
- EasyTier 虚拟 IP
- entry peer 可达性
- nftables 项目表
- forwards / entries 配置
- target TCP 可达性
- PBR / BBR / 基础网络状态

## 卸载与清理

主菜单 `卸载全部` 会二次确认，默认 No。它会删除通过本脚本安装/生成的服务、配置、nftables 规则、EasyTier 文件、快捷命令，不会删除系统本身和用户手动部署的业务。

旧版本组件清理放在：

```text
高级功能 -> legacy 清理
```

legacy 清理项使用通用中文描述，默认不执行，每一项都需要二次确认。

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
