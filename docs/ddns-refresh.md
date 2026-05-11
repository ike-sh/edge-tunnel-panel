# DDNS 后端 / PBR / 公网入口自动刷新

Leikwan Toolkit 1.3.4 把 DDNS 明确拆成双端职责：

- A 公网入口机器：负责把自己的当前公网 IP 更新到 DNS 服务商。
- B 利群主机：负责解析 `entries.tsv public_host`、`forwards.tsv target_host`、PBR 域名规则，并在 IP 变化后同步 nftables / PBR / relay。

B 端不能替 A 端修改 DNS 服务商记录。如果 A 端没有 DDNS 更新器或外部 DDNS 客户端，B 端解析到的仍然会是旧 IP。

B 端 DDNS 监控覆盖三类对象：

- 转发目标：`forwards.tsv` 的 `target_host`
- 公网入口：`entries.tsv` 的 `public_host`
- 域名 PBR：`pbr/domain-routes.tsv`

它只处理域名，不会把用户填写的域名替换成 IP。纯 IPv4 保持原样。

## 常用命令

```bash
lq ddns run
lq ddns run --scope forwards
lq ddns run --scope entries
lq ddns run --scope pbr
lq ddns run --scope all
lq ddns overview
lq ddns apply-entries
lq ddns status
lq ddns enable
lq ddns disable
lq ddns logs
lq entry ddns status
lq entry ddns setup
lq entry ddns run
lq entry ddns enable
lq entry ddns logs
lq --ddns-run
```

交互菜单路径：

```text
主菜单 -> DDNS 自动刷新
运维命令中心 -> DDNS 自动刷新
```

旧的“转发目标管理”中仍保留兼容入口，但会提示 DDNS 已提升为主菜单一等功能。

## 配置文件

配置文件为：

```text
/etc/leikwan-toolkit/ddns.env
```

默认配置：

```text
DDNS_REFRESH_FORWARDS=true
DDNS_REFRESH_ENTRIES=true
DDNS_REFRESH_PBR=true
DDNS_AUTO_APPLY=true
DDNS_AUTO_SYNC_FORWARD_PBR=true
DDNS_AUTO_SYNC_DOMAIN_PBR=true
DDNS_ENTRY_AUTO_RESTART_RELAY=false
DDNS_KEEP_OLD_ON_FAIL=true
DDNS_REFRESH_INTERVAL=5min
```

`DDNS_ENTRY_AUTO_RESTART_RELAY=false` 是安全默认值。公网入口域名 IP 变化后，EasyTier relay 运行中不一定重新解析 peer 域名，但自动重启 relay 会短暂中断所有入口，所以 timer 默认只记录 `relay restart needed` 并写日志。

确认可接受维护窗口自动重启时，再显式设置：

```text
DDNS_ENTRY_AUTO_RESTART_RELAY=true
```

## Scope

`lq ddns run` 默认等价于：

```bash
lq ddns run --scope all
```

scope 行为：

- `forwards`：只刷新后端转发目标域名。
- `entries`：只刷新公网入口 `public_host` 域名。
- `pbr`：只刷新域名 PBR。
- `all`：按 forwards -> entries -> pbr 顺序刷新，并合并 apply。

## 转发目标 DDNS

示例 forward：

```text
tw    10004    tw.example.com    52936    eth1    T_CN2    true    tw-target
```

刷新成功后写入：

```text
/etc/leikwan-toolkit/forwards/resolved.tsv
```

IP 变化时：

- 更新 `resolved.tsv`
- 创建 `auto-before-ddns-apply-*.tar.gz` 自动快照
- 只重应用一次 nftables
- 如果该 forward 有 `route_table` 且 `DDNS_AUTO_SYNC_FORWARD_PBR=true`，同步 `forward:<name>` 来源 PBR

解析失败时保留旧 resolved IP，不覆盖成空值。

## 公网入口 DDNS

示例 entry：

```text
public3    entry.example.com    10.198.1.4    tcp,udp    8303    100    true
```

刷新缓存写入：

```text
/etc/leikwan-toolkit/entries/resolved-entries.tsv
```

格式：

```text
# name public_host resolved_ip last_checked last_changed
public3 entry.example.com 203.0.113.44 2026-05-10T05:00:00 2026-05-10T05:00:00
```

公网入口域名变化时，脚本不会修改 `entries.tsv`，也不会把域名替换成 IP。状态文件会记录：

```text
LAST_DDNS_ENTRY_CHANGED=public3
LAST_DDNS_RELAY_RESTART_NEEDED=true
```

交互执行时会询问是否立即重启 relay；timer 非交互模式默认不重启。选择不重启时，可在维护窗口执行：

```text
利群主机 -> EasyTier 组网管理 -> 启动 / 重启 relay 服务
```

## 域名 PBR DDNS

域名 PBR 定义文件：

```text
/etc/leikwan-toolkit/pbr/domain-routes.tsv
```

格式：

```text
# name host route_table enabled comment
tw tw.example.com T_CN2 true tw-ddns-pbr
```

解析缓存：

```text
/etc/leikwan-toolkit/pbr/resolved-pbr-domains.tsv
```

同步后在 `static-routes.conf` 生成来源明确的规则：

```text
203.0.113.45/32 CN2 pbr-domain:tw tw.example.com
```

域名 IP 变化时，脚本删除旧的 `pbr-domain:<name>` 规则并添加新的 `/32` 规则。它不会删除用户手写 `static` 规则，也不会删除 `forward:<name>` 来源规则。

## PBR 来源边界

自动管理范围：

- `forward:<name>`：由 `lq pbr sync-from-forwards` 管理。
- `pbr-domain:<name>`：由 `lq pbr domain sync` 管理。

不会自动删除：

- `static` 或无来源标记的用户手写规则。

## 状态与日志

最近状态：

```text
/etc/leikwan-toolkit/status/last-ddns.env
```

关键字段：

```text
LAST_DDNS_SCOPE=
LAST_DDNS_FORWARD_CHANGED=
LAST_DDNS_ENTRY_CHANGED=
LAST_DDNS_PBR_CHANGED=
LAST_DDNS_RELAY_RESTART_NEEDED=
LAST_DDNS_NFT_APPLIED=
LAST_DDNS_PBR_APPLIED=
LAST_DDNS_RELAY_RESTARTED=
```

日志：

```text
/var/log/leikwan-ddns-refresh.log
```

日志会记录 scope、三类对象 checked / changed / failed、是否应用 nftables、是否应用 PBR、是否需要或已经重启 relay。日志不会写入 EasyTier network secret。

1.3.4 起，`lq ddns run`、菜单刷新和日志中的末尾摘要改为面向运维人员阅读的分区格式：

```text
DDNS 检测摘要
----------------------------------------
后端转发：
- 检查 4
- 域名 1
- 变化 0
- 失败 0

公网入口：
- 域名入口 0
- 无需刷新

域名 PBR：
- 未配置

系统动作：
- nftables：无需重应用
- relay：无需重启

结果：
- DDNS 状态：OK
```

`lq ddns status` 也会显示同样的摘要口径，避免只看到机器化 changed / failed 字段。

配置导出包会包含 DDNS 配置、缓存和日志尾部。给别人排错时请使用 `lq config export --redacted`，不要发送完整配置包。

## 并发保护

DDNS 全流程使用：

```text
/run/leikwan-ddns-refresh.lock
/run/leikwan-toolkit.lock
```

如果已有 Leikwan 任务运行，timer 会跳过本次刷新，不视为失败。

1.3.4 起，锁会记录 PID。若检测到 PID 已不存在的 stale lock，下次获取锁时会自动清理并输出 WARN。
