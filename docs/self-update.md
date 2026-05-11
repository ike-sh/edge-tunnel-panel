# 自更新与安全回滚

Leikwan Toolkit 1.3.2 保持自更新能力。自更新只使用 GitHub Release 包，不会直接拉取 raw main 分支脚本。

## 检查版本

```bash
lq update check
lq --update-check
```

交互模式也可以从“运维命令中心 -> 自更新”进入。

输出当前版本和 GitHub latest release 版本。当前已经最新时会显示：

```text
[OK] 当前已是最新版本：1.3.2
```

## 执行更新

```bash
lq update run
lq --self-update
```

更新流程：

1. 查询 GitHub latest release。
2. 下载 `leikwan-toolkit-X.Y.Z.tar.gz`。
3. 下载 `leikwan-toolkit-X.Y.Z.tar.gz.sha256`。
4. 校验 sha256。
5. 解包并取出 `leikwan-toolkit.sh`。
6. 执行 `bash -n`。
7. 执行新脚本 `--version`。
8. 备份当前 `/root/leikwan-toolkit.sh`。
9. 替换脚本并修复 `/usr/local/bin/lq` / `/usr/local/bin/LQ`。
10. 再次检查 `/root/leikwan-toolkit.sh --version` 和 `lq --version`。

自更新只替换脚本，不删除 `/etc/leikwan-toolkit` 配置。
自更新会使用更新锁和全局锁，避免和配置导入、DDNS 应用、转发规则应用等高危写操作并发执行。
`update rollback` 也会持有更新锁和全局锁，避免回滚时和其它高危任务并发。

## 镜像

国内网络访问 GitHub Release 较慢时可设置：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

脚本会优先尝试官方 Release URL；失败后再尝试镜像。

## 状态

```bash
lq update status
```

最近更新状态写入：

```text
/etc/leikwan-toolkit/status/last-update.env
```

示例：

```text
LAST_UPDATE_TIME=2026-05-10 05:30:00
LAST_UPDATE_FROM=1.1.1
LAST_UPDATE_TO=1.3.2
LAST_UPDATE_RESULT=ok
LAST_UPDATE_BACKUP=/var/backups/leikwan-toolkit/root__leikwan-toolkit.sh.20260510-053000.bak
LAST_UPDATE_SOURCE=https://github.com/ike-sh/leikwan-toolkit/releases/download/v1.3.2/leikwan-toolkit-1.3.2.tar.gz
```

## 回滚

```bash
lq update rollback
```

回滚会读取 `last-update.env` 中的备份路径，二次确认后恢复旧脚本。恢复前会对备份执行 `bash -n` 校验；恢复后会重新显示版本，并把更新状态记为 `rollback`。

## 排查

- sha256 校验失败：不会替换当前脚本。
- 下载失败：检查网络，或设置 `LEIKWAN_GITHUB_MIRRORS`。
- 替换后版本不符合预期：脚本会自动恢复更新前备份。
- 并发更新：第二个任务会提示已有更新任务运行。

debug report 会包含 `last-update.env`、`lq --version`、`/usr/local/bin/lq` 指向和 `/root/leikwan-toolkit.sh` 文件信息；URL query 会脱敏。
