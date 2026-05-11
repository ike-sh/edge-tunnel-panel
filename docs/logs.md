# 日志查看 / 清理

Leikwan Toolkit 1.4.0 新增 `lq logs` 命令中心，用于查看运行日志和最近状态文件。

## CLI

```bash
lq logs
lq logs ddns
lq logs entry-ddns
lq logs apply
lq logs update
lq logs doctor
lq logs clean
```

`lq logs` 默认显示日志索引。无日志时会友好提示，不触发全局 trap。

## 日志来源

```text
/var/log/leikwan-ddns-refresh.log
/var/log/leikwan-entry-ddns.log
/root/lq-apply-relay.log
/etc/leikwan-toolkit/status/*.env
```

`logs ddns`、`logs entry-ddns` 和 `logs apply` 只显示尾部 100 行。`logs update` 复用 `lq update status`，`logs doctor` 显示最近 doctor 状态缓存。

## 清理

```bash
lq logs clean
```

清理前会确认：

```text
[WARN] 将清理运行日志，但不会删除配置、快照、备份。
确认继续？[y/N]
```

它只删除运行日志，不删除 `/etc/leikwan-toolkit`、快照、配置包或 `/var/backups/leikwan-toolkit`。
