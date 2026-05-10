# 故障排查

Leikwan Toolkit 1.2.1 主线是 EasyTier 传输 + nftables 四层 TCP/UDP 转发。脚本不部署后端业务，只负责：

```text
外部客户端 -> A 公网入口端口（TCP/UDP） -> EasyTier -> B 利群主机 -> 后端目标
```

## 一键诊断

日常查看先用轻量状态总览：

```bash
lq status
lq --status
```

状态总览只读取配置、systemd 和 nftables，不做 ping、nc、apt update，也不会修改系统。它会显示最近一次 apply / doctor / status 缓存，缓存文件位于：

```text
/etc/leikwan-toolkit/status/last-apply.env
/etc/leikwan-toolkit/status/last-doctor.env
/etc/leikwan-toolkit/status/last-status.env
```

需要详细排障时再执行：

```bash
lq --doctor
```

doctor 会检查：

- EasyTier binary 和 service 状态
- EasyTier IP 是否存在
- peer 目标和 EasyTier IP ping
- A 侧端口池 TCP/UDP DNAT
- B 侧转发 TCP/UDP DNAT
- PBR 路由规则
- TCP MSS clamp
- GitHub / apt DNS 与依赖命令

UDP 是无连接协议，`nc -uvz` 探测失败不一定代表业务不可用。最终应结合 EasyTier peer / ping 和业务实测判断。

## peer 列表暂未显示

relay 重启后 easytier-cli 的 peer 列表可能短时间未刷新。脚本会重试读取 peer 列表；如果 peer 暂未显示但 EasyTier IP ping 成功，会视为已连通并输出 INFO。只有 peer 未确认且 ping 失败时才 WARN。

## apt / jq

如果 apt 源返回 `403 Forbidden` 或 `mirror sync in progress`，请换源、稍后重试或手动安装对应 deb 包。

`jq` 只用于读取 GitHub release metadata。如果 EasyTier 已安装，缺少 `jq` 不影响当前组网运行。

## EasyTier 下载

脚本会优先使用 GitHub API metadata 找到的资产；如果无法获取 metadata，会尝试已知 zip 和 tar.gz/tgz 候选。缺少 `unzip` 时会跳过 zip 并继续尝试 tar.gz/tgz，或引导用户提供本地包 / 本地二进制。

## 端口混淆

- EasyTier 组网端口：默认 `8301`、`8302`、`8303`，建议 `8000-9000`，用于 A/B 建链。
- 业务入口端口：常用 `10001-19999`，用于外部客户端访问业务。

不要把 EasyTier 白名单端口误填为业务入口端口。

遇到端口占用或 DNAT 不一致时，先运行：

```bash
lq port check
lq --port-check
```

端口预检会检查 EasyTier 端口、业务入口端口、本机监听和 nftables dport。它只读，不修改系统。新增入口或转发目标时，脚本也会拦截重复端口并允许重新输入。

如果业务入口端口池没有可推荐端口，会提示清理旧转发目标或调整端口池。

## 终端显示

窄终端会自动切换为紧凑列表，避免中英文混排导致表格错位。可用 `LEIKWAN_COMPACT=1 lq` 强制紧凑显示；调试输出时可用 `LEIKWAN_NO_CLEAR=1 lq` 禁用清屏。

## MSS clamp

MSS clamp 用于提高 EasyTier/tun 场景下 TCP 转发稳定性。doctor 和状态页面只检测，不自动修改；应用 A 侧端口池或 B 侧转发规则时会重新渲染 nftables，并明确输出是否自动启用 MSS clamp。

## 快照与回滚

菜单路径：

```text
高级功能 -> 配置快照 / 回滚
```

快照可能包含 EasyTier network secret，排障转交前必须确认保存范围。高危操作前会自动创建轻量快照，自动快照保存在：

```text
/etc/leikwan-toolkit/snapshots/auto/
```

自动快照只保留最近 10 个。恢复快照前会二次确认，恢复后会询问是否立即 reload systemd 并重启相关服务。

## 配置包

导出完整配置包：

```bash
lq config export --full
```

完整包包含 EasyTier network secret，只适合自己保存和迁移。排错给别人看时使用：

```bash
lq config export --redacted
```

脱敏包会替换 secret、配对码 base64、token/password 类字段。它不能完整恢复运行。

查看配置包：

```bash
lq config inspect /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz
```

导入配置包前会自动创建 `auto-before-config-import-*` 快照。如果导入后状态异常，先执行：

```bash
lq status
lq --doctor
```

需要重渲染转发规则时再执行：

```bash
lq forward apply-relay --auto-fix-route
```

## pending reservation

未完成接入码保存在：

```text
/etc/leikwan-toolkit/entries/pending-entries.tsv
```

如果误生成了接入码，可以在：

```text
利群主机 -> 公网入口列表管理 -> 查看 / 清理未完成接入码
```

中清理。清理 pending 不会影响正式 `entries.tsv`，也不会重启 relay。

## PBR 后加

如果先添加了转发目标，后添加 PBR，请执行：

```bash
lq forward apply-relay --auto-fix-route
```

如果当前 SSH 连接经过公网入口 / EasyTier / 转发链路，前台重应用 nftables 可能短暂中断连接。建议使用后台方式避免 SIGHUP 中止命令：

```bash
nohup lq forward apply-relay --auto-fix-route >/root/lq-apply-relay.log 2>&1 &
tail -f /root/lq-apply-relay.log
lq --doctor
```

升级脚本后，如果 doctor 发现 nftables 表存在但没有任何 DNAT、只有部分 TCP/UDP DNAT 缺失，或启用了 MSS clamp 但规则未渲染，会提示这可能是旧版本模板。交互菜单会询问是否立即执行 `lq forward apply-relay --auto-fix-route` 并复查；非交互 `lq --doctor` 只提示命令，不会自动修改 nftables。

从现有转发目标添加 PBR 时，脚本会默认询问是否立即执行上述同步。

## DDNS 后端 / 公网入口 / PBR 刷新

域名后端目标、公网入口 `public_host` 和域名 PBR 可使用 DDNS 自动刷新：

```bash
lq ddns status
lq ddns run
lq ddns run --scope forwards
lq ddns run --scope entries
lq ddns run --scope pbr
lq ddns enable
lq ddns logs
```

如果 `lq ddns run --scope forwards` 显示 IP 未变化，不会重应用 nftables。如果显示解析变化，会更新 `resolved.tsv` 并安全重应用转发规则。解析失败时会保留旧 IP。

公网入口 DDNS 变化时，默认不会自动重启 relay。状态中会显示 `relay restart needed`，因为 EasyTier 运行中不一定重新解析 peer 域名。建议在维护窗口重启 relay；只有设置 `DDNS_ENTRY_AUTO_RESTART_RELAY=true` 后，timer 才会自动重启。

forward 来源 PBR 可执行：

```bash
lq pbr sync-from-forwards
```

域名 PBR 可执行：

```bash
lq pbr domain sync
```

PBR 自动管理边界：

- `forward:<name>` 可自动同步。
- `pbr-domain:<name>` 可自动同步。
- `static` 规则不会被自动删除。

日志路径：

```text
/var/log/leikwan-ddns-refresh.log
/etc/leikwan-toolkit/status/last-ddns.env
```

如果 doctor 提示域名 PBR 已变化但规则未同步，执行：

```bash
lq pbr domain sync
lq --pbr-apply
```

## 端点输出

生成端点分享：

```bash
lq output generate
lq output show
lq output json
lq output html
```

端点输出只包含公网入口和业务端口，不包含 EasyTier secret 或配对码。它不是代理链接。若安装了 `qrencode`，`lq output qr` 会生成 endpoint 字符串二维码；未安装时会跳过。

## 自更新

检查版本：

```bash
lq update check
```

执行更新：

```bash
lq update run
```

如果下载失败，请检查网络或设置 GitHub 镜像：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

sha256 校验失败时不会替换脚本。替换后版本异常时会自动恢复更新前备份。需要手动恢复时执行：

```bash
lq update rollback
```

最近更新状态：

```text
/etc/leikwan-toolkit/status/last-update.env
```

## 脱敏报告

生成脱敏报告：

```bash
lq --doctor --verbose
```

或使用交互菜单中的“生成脱敏故障报告”。报告会尽量脱敏，但仍建议人工检查后再发送。
