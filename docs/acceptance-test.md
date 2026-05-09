# 验收测试

本页用于 v0.4.1-alpha 收尾验收。

## 静态检查

```bash
bash -n leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
shellcheck leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
git diff --check
scripts/check-redaction.sh
scripts/package-release.sh
```

Release 包应生成：

```text
dist/leikwan-toolkit-0.4.1-alpha.tar.gz
```

包内包含：

```text
leikwan-toolkit.sh
scripts/bootstrap.sh
docs/
README.md
```

包内不包含独立卸载脚本或旧入口脚本。

## 命名

Banner 显示：

```text
Leikwan Toolkit
利群快速组网工具
Author : ike-sh
Version: 0.4.1-alpha
GitHub : https://github.com/ike-sh/leikwan-toolkit
```

安装命令使用：

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
```

唯一主脚本安装为 `/root/leikwan-toolkit.sh`，`lq` 和 `LQ` 都指向它。

卸载入口：

```text
lq -> 主菜单 -> 卸载全部
bash /root/leikwan-toolkit.sh --uninstall
```

## 快速组网菜单

必须显示第 7 项 PBR、第 8 项完整说明：

```text
2. 我现在在利群主机：生成 / 新增公网入口网络码
3. 我现在在公网入口：粘贴利群网络码，部署本机入口
4. 我现在在利群主机：粘贴公网入口返回码，完成接入
7. IPv4 多出口策略路由 / PBR
8. 查看完整分步说明
```

已有 `aliyun 10.198.1.2 tcp+udp/8301` 时，B 再生成网络码，应推荐 `home` 或 `entry2`、`10.198.1.3`、`tcp+udp/8302`。

B 生成网络码默认必须包含：

```text
SUGGESTED_EASYTIER_PROTOCOLS=tcp,udp
SUGGESTED_EASYTIER_TCP_PORT=8301
SUGGESTED_EASYTIER_UDP_PORT=8301
SUGGESTED_EASYTIER_PROTOCOL=tcp
SUGGESTED_EASYTIER_PORT=8301
```

如果已有 `/etc/leikwan-toolkit/easytier/network.env` 且角色是 `leikwan-relay`，再次生成网络码必须复用现有 network name / secret，不覆盖 `network.env`，不重启 `easytier-relay`，已有入口不掉线。

新 A 粘贴网络码部署时，默认使用 B 推荐的 `SUGGESTED_ENTRY_NAME`、`SUGGESTED_ENTRY_ET_IP`、`SUGGESTED_EASYTIER_PROTOCOLS`、`SUGGESTED_EASYTIER_PORT`。默认提示应显示 `EasyTier 传输模式 [tcp+udp]` 和 `EasyTier 监听端口（TCP+UDP，同端口，白名单 8000-9000） [8301]`。

A 部署后 systemd service 必须同时包含 `tcp://0.0.0.0:8301` 和 `udp://0.0.0.0:8301`。A 返回 ENTRY 码必须同时包含 `EASYTIER_PROTOCOLS=tcp,udp`、`EASYTIER_TCP_PORT=8301`、`EASYTIER_UDP_PORT=8301` 和旧字段 `EASYTIER_PROTOCOL=tcp`、`EASYTIER_PORT=8301`。

旧网络码如果只有 `SUGGESTED_EASYTIER_PROTOCOL=tcp` 和 `SUGGESTED_EASYTIER_PORT=8301`，A 仍应部署 TCP-only；旧 ENTRY 码如果只有 `EASYTIER_PROTOCOL=tcp`，B 仍应只生成 TCP peer。

连续生成入口码验收：

1. B 上 `entries.tsv` 为空。
2. 第一次生成推荐 `aliyun / 10.198.1.2 / tcp+udp / 8301`。
3. 不粘贴 ENTRY，立刻第二次生成；确认继续后必须推荐 `home / 10.198.1.3 / tcp+udp / 8302`。
4. 不粘贴第二份 ENTRY，立刻第三次生成；确认继续后必须推荐 `tencent / 10.198.1.4 / tcp+udp / 8303`。
5. `entries/pending-entries.tsv` 中不应重复预占同一个 EasyTier IP 或端口。
6. 如果 pending 为 `home 10.198.1.3 tcp,udp 8302`，但 A 返回 `ENTRY_NAME=shanghai`、`ENTRY_ET_IP=10.198.1.3`、`EASYTIER_PORT=8302`，B 必须保存 `shanghai` 并清理 `home` pending。

新 A 若在“本机 EasyTier IP [10.198.1.3]”输入 `home.example.com`，应提示这是域名而不是 EasyTier 虚拟 IP，并提示 DDNS 应填在“本机公网 IP / 域名”；下一轮默认值仍是 `10.198.1.3`。

## 公网入口管理

B 侧路径：

```text
利群主机 -> 公网入口列表管理
```

删除、启用/禁用、修改权重、测试公网入口必须先展示列表，支持编号或名称，空输入返回。

菜单必须显示：

```text
1. 生成新公网入口接入码
2. 粘贴公网入口返回码并接入
3. 手动添加公网入口（高级）
4. 修改公网入口详情
5. 删除公网入口
6. 启用 / 禁用公网入口
7. 修改公网入口权重
8. 查看所有公网入口
9. 测试公网入口
10. 切换主公网入口
11. 批量启用 / 禁用公网入口
12. 查看 / 清理未完成接入码
0. 返回
```

B 粘贴新 A 返回的 ENTRY 入口码后，默认只保存 `entries.tsv`，不渲染 relay service，不重启 relay。手动添加、修改详情、删除、启用/禁用、修改权重后也必须统一提示应用 relay。用户选择稍后应用时，已有入口保持在线。用户选择立即应用时，必须再次提示重启 relay 会短暂中断所有入口；确认后才 restart，并测试所有 enabled entries。

立即应用后：

```text
entries.tsv 同时存在 aliyun 和 home
relay service peer 列表同时包含 aliyun 和 home
```

`tcp,udp` 入口在 `entries.tsv` 中保存为 `tcp,udp  8301`，列表显示为 `tcp+udp`，relay service peer 列表必须同时包含 `tcp://PUBLIC_HOST:8301` 和 `udp://PUBLIC_HOST:8301`。

修改入口协议验收：

1. 把 `aliyun` 从 `tcp+udp` 改成 `tcp`。
2. 立即应用后，relay service 只包含 `tcp://203.0.113.10:8301`，不再包含 `udp://203.0.113.10:8301`。
3. 再改回 `tcp+udp` 后，TCP/UDP peer 都恢复。

角色保护验收：

- B 利群主机执行“启动 / 重启 entry 服务”时，应 WARN 当前机器看起来是 B，默认不继续。
- A 公网入口执行“启动 / 重启 relay 服务”时，应 WARN 当前机器看起来是 A，默认不继续。

入口策略验收：

- 切换主公网入口选择 `home`，模式 1 后，`home enabled=true`，其它入口 `enabled=false`；立即应用后 relay service 只包含 `home` peer。
- 批量启用所有入口后，所有 entry `enabled=true`；立即应用后 relay service 包含所有 enabled entry 的 TCP/UDP peer。
- 切换主公网入口选择 `home`，模式 2 后，`home` 权重最高且仍保留其它 enabled entry；`generate_forward_outputs` 中 `home` 标记 PRIMARY，其它标记 BACKUP。
- 批量只保留 `aliyun` enabled 后，`aliyun enabled=true`，其它入口 `enabled=false`。
- 禁用所有入口必须二次确认；立即应用后 relay peer 为空，doctor WARN 当前没有 enabled 公网入口。
- 输出清单和 doctor 必须说明：权重只影响排序和推荐，不代表自动负载均衡。

A 侧配置入口端口池 `10000-19999` 后，nftables 必须同时存在：

```text
tcp dport 10000-19999 dnat ip to 10.198.1.1
udp dport 10000-19999 dnat ip to 10.198.1.1
```

A 侧路径：

```text
主菜单 -> 公网入口
```

只保留本机功能：部署本机入口、配置本机入口端口池、查看本机公网入口状态。在 B 上误进状态页时，应 WARN 并引导到 B 侧入口列表管理。

## 转发目标

添加转发目标时：

- 公网入口端口提示显示端口池范围和推荐下一个未使用端口。
- 后端目标端口不显示默认值，空输入会 WARN。
- 添加摘要显示 `protocols=tcp,udp`，但 `forwards.tsv` 仍保持 8 列兼容。

修改、删除、启用/禁用、测试单个转发目标必须先展示列表，支持编号或名称。修改、删除、启用/禁用后必须重新生成 `resolved.tsv` 并应用 relay nftables。

域名目标示例：

```text
name=Hinet
entry_port=10002
target_host=tw.example.com
target_port=52936
```

列表应显示：

```text
Hinet 10002 -> tw.example.com(203.0.113.20):52936 eth1 - enabled
```

`apply-relay` 每次重新解析域名；IP 变化时输出解析变化并刷新 nftables。

对每个 enabled 转发目标，B 侧 nftables 必须同时生成：

```text
tcp dport 10002 dnat ip to 203.0.113.20:52936
udp dport 10002 dnat ip to 203.0.113.20:52936
```

`doctor` 应同时检查入口 TCP / UDP、后端 target TCP / UDP、relay TCP / UDP DNAT。UDP 探测失败只 WARN，最终以 EasyTier peer / ping 和业务实测为准。

## PBR

菜单：

```text
1. 添加静态 PBR
2. 从现有转发目标添加 PBR
3. 删除 PBR 规则
4. 应用 PBR
5. 查看 PBR
0. 返回
```

静态 PBR 输入域名时，应提示改用“从现有转发目标添加 PBR”。从转发目标选择域名后端时，应解析当前 IP 并写入 `resolved_ip/32`，同时记录来源转发名和 `target_host`。

删除 PBR 规则时，应先展示规则列表；输入编号、CIDR 或裸 IP 都可选择规则，裸 IP 按 `/32` 匹配。确认删除后应从 `static-routes.conf` 删除对应行并重新应用 PBR。同一 CIDR 有多条不同路由表规则时，必须提示使用编号精确删除。

## 依赖和下载排错

A 缺少 `unzip` 且 apt 安装失败时，应明确提示 `unzip` 缺失，不应误报 EasyTier zip 坏包。脚本会优先尝试已知 zip 资产；如果缺少 `unzip`，会跳过 zip 并继续尝试 `tar.gz` / `tgz`，或引导用户提供本地 EasyTier 包 / `easytier-core` / `easytier-cli`。

`doctor` 应检查：

```text
raw.githubusercontent.com / api.github.com / cn.archive.ubuntu.com 是否解析到 198.18.x.x fake-ip
curl / jq / tar / unzip 是否存在
apt 源更新是否失败或返回 403
```

## 旧名称检查

旧入口脚本文件名、独立卸载脚本文件名、旧仓库 URL、旧英文标题都不应命中主线内容。`leikwan-wg-toolkit` 只允许出现在旧路径迁移/清理说明里。
