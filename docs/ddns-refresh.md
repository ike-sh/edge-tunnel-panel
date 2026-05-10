# DDNS 后端自动刷新

Leikwan Toolkit 1.1.0 增加 DDNS 后端自动刷新。它用于处理转发目标中的域名后端，例如：

```text
tw    10004    tw.example.com    52936    eth1    T_CN2    true    tw-target
```

当 `target_host` 的 IPv4 解析结果变化时，脚本会更新 `resolved.tsv`，创建自动快照，并安全重应用 B 侧 nftables 转发规则。

## 使用场景

- 后端目标是家宽、动态公网 IP 或 DDNS 域名。
- 后端域名 IP 变化后，希望 B 侧转发规则自动跟随。
- 需要保留旧 IP，在解析失败时避免把可用规则覆盖成空值。

## 常用命令

```bash
lq ddns status
lq ddns run
lq ddns enable
lq ddns disable
lq ddns logs
lq --ddns-run
```

交互菜单路径：

```text
利群主机 -> 转发目标管理 -> DDNS 后端自动刷新
```

## 自动刷新 timer

默认不自动启用。执行：

```bash
lq ddns enable
```

会写入：

```text
/etc/systemd/system/leikwan-ddns-refresh.service
/etc/systemd/system/leikwan-ddns-refresh.timer
```

默认间隔：

```text
OnBootSec=2min
OnUnitActiveSec=5min
```

可在菜单中选择 `5min / 10min / 30min / 1h`。

配置文件：

```text
/etc/leikwan-toolkit/ddns.env
```

默认配置：

```text
DDNS_REFRESH_INTERVAL=5min
DDNS_AUTO_APPLY=true
DDNS_AUTO_FIX_ROUTE=false
DDNS_AUTO_SYNC_PBR=false
DDNS_KEEP_OLD_ON_FAIL=true
```

## 刷新行为

- 只检查 enabled 转发目标。
- 只处理 `target_host` 为域名的目标，纯 IPv4 不作为 DDNS 目标。
- IP 未变化时不会重应用 nftables。
- IP 变化时更新 `resolved.tsv`，创建 `auto-before-ddns-apply-YYYYMMDD-HHMMSS.tar.gz` 快照，并安全重应用转发规则。
- 解析失败时保留旧 resolved IP，不覆盖为失败结果。

日志：

```text
/var/log/leikwan-ddns-refresh.log
```

最近状态：

```text
/etc/leikwan-toolkit/status/last-ddns.env
```

## PBR 同步

域名后端 IP 变化后，PBR `/32` 规则可能需要同步。默认不会自动迁移 PBR，脚本会提示：

```bash
lq pbr sync-from-forwards
```

该命令会遍历 enabled forwards，根据当前 resolved IP 同步 `forward:<name>` 来源的 PBR，并删除旧的 forward 来源规则。它不会删除用户手动添加的 `static` PBR。

如需 DDNS 刷新后自动同步，可设置：

```text
DDNS_AUTO_SYNC_PBR=true
```

## 并发保护

DDNS 刷新和转发规则应用使用 lock，避免多个任务同时写 nftables：

```text
/run/leikwan-toolkit.lock
/run/leikwan-ddns-refresh.lock
```

如果已有任务运行，DDNS timer 会跳过本次刷新，不视为系统失败。

## 排查

```bash
lq ddns status
journalctl -u leikwan-ddns-refresh.service --no-pager -n 100
tail -f /var/log/leikwan-ddns-refresh.log
lq --doctor
```

debug report 会包含 `ddns.env`、`last-ddns.env`、timer/service 状态和最近 100 行 DDNS 日志。DDNS 日志不会写入 EasyTier network secret。
