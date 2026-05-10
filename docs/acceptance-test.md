# 验收清单

本页用于 Leikwan Toolkit 1.1.2 正式版验收。

## 版本

```bash
grep -n '^TOOL_VERSION=' leikwan-toolkit.sh
bash leikwan-toolkit.sh --version
```

期望：

```text
TOOL_VERSION="1.1.2"
leikwan-toolkit 1.1.2
```

## 打包

```bash
bash -n leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
shellcheck leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
git diff --check
bash scripts/check-redaction.sh
bash scripts/package-release.sh
```

期望生成：

```text
dist/leikwan-toolkit-1.1.2.tar.gz
dist/leikwan-toolkit-1.1.2.tar.gz.sha256
```

release 包不得包含旧入口文件：

按发布验收命令检查包内容，确认不包含旧入口文件和旧卸载脚本。

## 快速组网

1. B 生成公网入口接入码，默认推荐 `public1 / 公网1 / 10.198.1.2 / tcp+udp / 8301`。
2. 不粘贴 ENTRY，继续生成第二份，推荐 `public2 / 公网2 / 10.198.1.3 / tcp+udp / 8302`。
3. 如果已有旧入口 `aliyun -> 10.198.1.2/8301` 和 `home -> 10.198.1.3/8302`，下一台必须推荐 `public3 / 公网3 / 10.198.1.4 / 8303`。
4. A 粘贴网络码部署入口，systemd service 同时包含 TCP 和 UDP listener。
5. A 返回 ENTRY 后，B 能保存入口并清理 pending。
6. ENTRY 名称和 pending 名称不同也能保存并清理命中的 pending。

## 多公网入口

准备：

```text
public1  203.0.113.10   10.198.1.2  tcp,udp  8301  100  true
public2  203.0.113.20   10.198.1.3  tcp,udp  8302  100  true
```

验收：

- 列表显示 `公网1(public1)`、`公网2(public2)`。
- relay service peer 包含 TCP+UDP 两个协议。
- 切换主入口模式 1 后，只保留选中入口 enabled。
- 切换主入口模式 2 后，选中入口标记 PRIMARY，其它 enabled 入口标记 BACKUP。
- 批量禁用所有入口必须二次确认。

旧入口名仍兼容，可继续读取、修改、删除、启用禁用和切换主入口。

## 转发与 PBR

- A 侧端口池必须生成 TCP+UDP DNAT。
- B 侧转发目标必须生成 TCP+UDP DNAT。
- PBR 菜单显示 `0. 返回`。
- PBR 菜单包含 `域名 PBR 管理`。
- 从现有转发目标添加 PBR 后，默认询问是否立即同步转发规则和 `route_table` 元数据。
- `lq pbr sync-from-forwards` 能根据当前 resolved IP 同步 forward 来源 PBR，且不删除 static PBR。
- `lq pbr domain add/list/delete/sync` 可用，域名 PBR 同步生成 `pbr-domain:<name>` 来源规则，且不删除 static PBR。
- 删除 PBR 支持编号、CIDR 和裸 IP。

## DDNS 自动刷新

```bash
lq ddns status
lq ddns run
lq ddns run --scope forwards
lq ddns run --scope entries
lq ddns run --scope pbr
lq ddns run --scope all
lq --ddns-run
```

期望：

- 不清屏，不等待回车。
- 能识别 enabled 转发目标中的域名后端、公网入口域名和域名 PBR。
- forward IP 未变化时不重应用 nftables。
- forward IP 变化时更新 `resolved.tsv`，创建 `auto-before-ddns-apply-*.tar.gz` 快照并安全重应用 nftables。
- entry IP 变化时更新 `resolved-entries.tsv`，默认只记录 `relay restart needed`，timer 不自动重启 relay。
- pbr domain IP 变化时更新 `resolved-pbr-domains.tsv`，生成新的 `pbr-domain:<name>` `/32` 规则。
- 解析失败时保留旧 resolved IP。

启用 timer：

```bash
lq ddns enable
systemctl status leikwan-ddns-refresh.timer
lq ddns status
```

检查：

```bash
tail -n 100 /var/log/leikwan-ddns-refresh.log
cat /etc/leikwan-toolkit/status/last-ddns.env
```

期望日志包含开始 / 结束、changed / failed 统计，不包含 EasyTier secret。

检查 last-ddns：

```bash
cat /etc/leikwan-toolkit/status/last-ddns.env
```

期望包含：

```text
LAST_DDNS_SCOPE=
LAST_DDNS_FORWARD_CHANGED=
LAST_DDNS_ENTRY_CHANGED=
LAST_DDNS_PBR_CHANGED=
LAST_DDNS_RELAY_RESTART_NEEDED=
LAST_DDNS_NFT_APPLIED=
LAST_DDNS_PBR_APPLIED=
```

## 自更新

```bash
lq update check
lq --update-check
```

期望显示当前版本和最新 GitHub Release 版本；当前已最新时显示 `[OK] 当前已是最新版本`。

在测试环境中使用旧版本脚本执行：

```bash
lq update run
```

期望：

- 下载 release tar.gz 和 sha256。
- sha256 校验通过。
- 解包得到 `leikwan-toolkit.sh`。
- `bash -n` 通过。
- 新脚本 `--version` 符合预期。
- 备份旧脚本到 `/var/backups/leikwan-toolkit/root__leikwan-toolkit.sh.*.bak`。
- 替换 `/root/leikwan-toolkit.sh`。
- `lq --version` 显示新版本。

回滚：

```bash
lq update rollback
```

期望根据 `last-update.env` 找到备份，恢复旧脚本，并把 `LAST_UPDATE_RESULT` 记为 `rollback`。

## 状态总览与缓存

```bash
lq status
lq --status
```

期望：

- 输出简洁状态总览，不清屏，不等待回车。
- 显示版本、角色、入口数量、转发数量、nftables、MSS clamp、整体状态。
- 不自动修改系统。

执行：

```bash
lq status
lq --doctor
nohup lq forward apply-relay --auto-fix-route >/root/lq-apply-relay.log 2>&1 &
```

检查：

```bash
ls -lh /etc/leikwan-toolkit/status/
cat /etc/leikwan-toolkit/status/last-status.env
cat /etc/leikwan-toolkit/status/last-doctor.env
cat /etc/leikwan-toolkit/status/last-apply.env
```

期望缓存文件存在，包含时间、结果、版本，不包含 EasyTier secret。

## 快照 / 回滚

菜单路径：

```text
高级功能 -> 配置快照 / 回滚
```

验收：

- 创建当前完整快照会生成 `snapshot-YYYYMMDD-HHMMSS.tar.gz`。
- 查看快照列表能按编号显示。
- 导出最新快照到 `/root/leikwan-snapshot-YYYYMMDD-HHMMSS.tar.gz`。
- 创建快照时提醒可能包含 EasyTier network secret。
- 恢复快照前二次确认，恢复后询问是否 reload systemd 并重启相关服务。

高危操作前，例如删除转发目标、删除公网入口、重新应用利群转发规则，应生成 `/etc/leikwan-toolkit/snapshots/auto/auto-before-*.tar.gz`，且只保留最近 10 个自动快照。

## 端口预检

```bash
lq port check
lq --port-check
```

期望：

- 输出 EasyTier 端口、业务入口端口、本机监听、nftables 状态。
- 不修改系统。
- 发现端口重复、pending 占用、本机监听或 nftables dport 冲突时输出 WARN。

新增转发目标时尝试使用已存在的 `entry_port`，应提示端口已被对应转发目标使用，不直接写入重复端口，并允许重新输入。

新增公网入口时尝试使用已存在的 EasyTier 端口，应提示端口已被对应入口使用或 pending 占用，不直接写入重复端口，并允许重新输入。

## 交互

- 主菜单显示清晰 banner。
- 子菜单不重复大 banner。
- 菜单进入前会清屏；`LEIKWAN_NO_CLEAR=1 lq` 可禁用清屏。
- 菜单动作输出必须停留，按回车后才继续。
- NETWORK / ENTRY 连接码输出后，直接回车不能返回菜单；必须输入 `y`，输入 `r` 可重显，输入 `p` 可显示保存路径。
- 快速组网说明简洁。
- 生成 NETWORK / ENTRY 配对码后，单行码停留在最后一行，并提示按回车返回。
- doctor、debug report、转发入口输出等长输出后等待回车返回菜单。

## 卸载

卸载后检查：

```bash
test ! -e /var/log/leikwan-toolkit.log && echo "OK: no log"
test ! -e /etc/leikwan-toolkit && echo "OK: no state"
test ! -e /var/backups/leikwan-toolkit && echo "OK: no backups"
command -v lq || echo "OK: no lq"
```

卸载检查结果中日志文件应显示已清理，且卸载结束后不应重新创建日志。
