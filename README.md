# Leikwan Toolkit

Leikwan Toolkit 是一个面向多公网入口场景的快速组网与四层转发管理工具。它使用 EasyTier 构建公网入口和中转主机之间的虚拟网络，并使用 nftables 在中转主机上管理 TCP/UDP 转发。

当前版本：`1.2.0`

## 功能特性

- 多公网入口接入与管理
- TCP+UDP EasyTier 组网
- A 侧公网端口池 DNAT
- B 侧 TCP/UDP 转发目标管理
- 多入口 PRIMARY / BACKUP 推荐
- 手动切换主公网入口
- IPv4 PBR 策略路由
- 状态总览与最近 apply / doctor / status 缓存
- 配置快照 / 回滚，高危操作前自动快照
- 配置导入 / 导出 / 迁移包
- 端口冲突预检与端口推荐避让
- 转发端点分享输出：TXT / TSV / JSON / HTML / 可选 QR
- DDNS 后端 / 公网入口 / 域名 PBR 自动刷新
- GitHub Release 自更新、sha256 校验与安全回滚
- 一键诊断与脱敏报告
- 完整卸载

## 架构说明

- A：公网入口，可部署多台，用于接入公网流量
- B：利群主机 / 中转主机，负责 EasyTier relay、PBR 和后端转发
- C：后端目标，支持 TCP/UDP 转发

链路：

```text
外部客户端 -> A 公网入口端口（TCP/UDP） -> EasyTier -> B 利群主机 -> 后端目标
```

多公网入口不是 B 侧自动负载均衡。外部客户端连接哪台 A，就从哪台 A 进入。`weight` 用于输出排序和 PRIMARY / BACKUP 推荐；真正自动负载均衡需要客户端、DNS 或外部 LB 配合。

## 快速安装

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
```

安装后主入口为：

```text
/root/leikwan-toolkit.sh
/usr/local/bin/lq
/usr/local/bin/LQ
```

## 快速开始

推荐按 B -> A -> B -> A -> B 的顺序执行：

1. B：修复 DNS / IPv4。
2. B：生成公网入口网络码。
3. A：粘贴网络码部署入口。
4. B：粘贴 A 返回码完成接入。
5. A：配置公网入口端口池。
6. B：添加后端转发目标。

进入交互菜单：

```bash
lq
```

查看版本：

```bash
lq --version
```

一键诊断：

```bash
lq --doctor
```

快速状态总览：

```bash
lq status
lq --status
```

端口冲突预检：

```bash
lq port check
lq --port-check
```

配置导入 / 导出：

```bash
lq config export --full
lq config export --redacted
lq config inspect /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz
lq config import /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz
```

转发端点输出：

```bash
lq output generate
lq output json
lq output html
lq output qr
```

`status` 适合日常查看，轻量读取配置文件、systemd 状态和 nftables 表，不做 ping、nc、apt update，也不自动修改系统。`doctor` 用于详细诊断，会检查更多链路细节；交互模式下可按提示修复部分问题。

如果升级脚本后看到 TCP/UDP DNAT 缺失，交互菜单中的“一键诊断 / 查看状态”会提示是否立即执行 `lq forward apply-relay --auto-fix-route` 重新渲染当前模板；非交互 `lq --doctor` 只提示命令，不会自动改规则。

## 端口说明

- EasyTier 组网端口：默认 `8301`、`8302`、`8303`，TCP+UDP 同端口，建议位于 `8000-9000`。
- 业务入口端口：常用 `10001-19999`，A 侧端口池会 TCP+UDP DNAT 到 B。
- 后端目标端口：由用户填写，同一个转发目标默认生成 TCP+UDP 转发规则。

EasyTier 组网端口和业务入口端口不是一回事：`8301` 用于 A/B 建链，`10001` 这类端口用于外部客户端访问业务。

新增入口或转发目标时，脚本会预检端口是否已被 TSV、pending reservation、本机监听进程或 nftables dport 占用。推荐端口会自动跳过已占用端口；业务入口端口池无可用推荐时会明确报错。

## 快照与回滚

菜单路径：

```text
高级功能 -> 配置快照 / 回滚
```

快照保存在 `/etc/leikwan-toolkit/snapshots/`，自动快照保存在 `/etc/leikwan-toolkit/snapshots/auto/`。快照会包含 `/etc/leikwan-toolkit/`、相关 systemd unit、sysctl、rt_tables，以及 nft/ip rule/ip route 的只读导出。

快照可能包含 EasyTier network secret，请按敏感文件妥善保存，不要公开上传。

以下高危操作前会自动创建轻量快照，自动快照只保留最近 10 个：重启 relay、重新应用 nftables 转发规则、删除公网入口、批量禁用公网入口、删除转发目标、删除 PBR 规则、卸载全部、恢复快照前。

## 配置导入 / 导出

菜单路径：

```text
高级功能 -> 配置导入 / 导出
```

完整配置包用于迁移或恢复，默认输出到：

```text
/root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz
/root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz.sha256
```

完整配置包包含 `/etc/leikwan-toolkit` 和 EasyTier network secret。泄露后可能导致别人加入你的 EasyTier 网络，务必妥善保存。

脱敏配置包用于排错或提交 issue：

```bash
lq config export --redacted
```

脱敏包会把 EasyTier secret、配对码 base64、token/password/secret 类字段替换为 `REDACTED`，不适合直接恢复运行。

导入前会先 inspect 包内容、校验 sha256、校验 manifest，并自动创建 `auto-before-config-import-YYYYMMDD-HHMMSS.tar.gz` 快照。交互导入可选择：

```text
1. 仅导入 /etc/leikwan-toolkit 配置
2. 导入配置并重新渲染 systemd / nftables / PBR
3. 完整迁移恢复，包括 systemd service、nftables、PBR、sysctl
```

非交互示例：

```bash
lq config import /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz --mode config-only
lq config import /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz --mode apply
lq config import /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz --mode full --yes
```

## 多公网入口

新入口默认使用内部名：

```text
public1 -> 公网1
public2 -> 公网2
public3 -> 公网3
```

脚本会在中文 UI 中显示 `公网1(public1)` 这类名称，systemd 和 TSV 内部仍使用 ASCII 名称，避免兼容问题。旧入口名仍兼容，例如用户已有的 `aliyun`、`home` 可以继续读取、修改、删除、启用禁用和切换主入口。

连续生成多个公网入口接入码时，脚本会写入 `entries/pending-entries.tsv` 预占推荐值，避免重复使用 EasyTier IP 或端口。推荐名称会按已占用的 EasyTier IP / 端口序号递增；例如旧入口 `aliyun=10.198.1.2/8301`、`home=10.198.1.3/8302` 已存在时，下一台会推荐 `public3 / 公网3 / 10.198.1.4 / 8303`。A 的 ENTRY 返回码接回 B 后，会按 `ENTRY_ET_IP + EASYTIER_PORT` 清理对应 pending。即使 A 侧改了入口名称，也会按返回码名称保存。

## PBR

IPv4 PBR 用于让特定目标网段走指定路由表，例如 CN2 或 9929。

建议顺序：

1. 先添加 PBR。
2. 再添加转发目标。

如果已经先添加了转发目标，后添加 PBR，脚本会询问是否立即重新应用转发规则并同步 `route_table` 元数据。也可以手动执行：

```bash
lq forward apply-relay --auto-fix-route
```

域名型 PBR 可通过 CLI 或菜单管理：

```bash
lq pbr domain add
lq pbr domain list
lq pbr domain sync
lq pbr domain delete
```

域名 PBR 写入 `/etc/leikwan-toolkit/pbr/domain-routes.tsv`，同步后在 `static-routes.conf` 生成 `pbr-domain:<name> <host>` 来源的 `/32` 规则。脚本只自动管理 `forward:<name>` 和 `pbr-domain:<name>` 来源，用户手写 `static` 规则不会被自动删除。

如果当前 SSH 连接可能经过公网入口、EasyTier 或正在修改的转发链路，建议后台安全执行：

```bash
nohup lq forward apply-relay --auto-fix-route >/root/lq-apply-relay.log 2>&1 &
tail -f /root/lq-apply-relay.log
lq --doctor
```

## DDNS 后端 / 公网入口 / PBR 自动刷新

如果转发目标的 `target_host`、公网入口的 `public_host` 或域名 PBR 使用 DDNS 域名，可以启用自动刷新。脚本会定期解析 enabled 对象；后端变化时更新 `resolved.tsv` 并安全重应用 nftables，公网入口变化时记录 `relay restart needed`，域名 PBR 变化时同步 `/32` PBR 规则。

```bash
lq ddns status
lq ddns run
lq ddns run --scope forwards
lq ddns run --scope entries
lq ddns run --scope pbr
lq ddns run --scope all
lq ddns enable
lq ddns disable
lq ddns logs
lq --ddns-run
```

默认 timer 间隔为 5 分钟，配置文件为 `/etc/leikwan-toolkit/ddns.env`，日志为 `/var/log/leikwan-ddns-refresh.log`，最近状态写入 `/etc/leikwan-toolkit/status/last-ddns.env`。

默认配置会刷新三类对象并自动同步 forward / domain PBR：

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

公网入口 `public_host` 变化默认不会自动重启 relay，因为 relay 重启会短暂中断所有入口。EasyTier 运行中不一定重新解析 peer 域名，所以状态和 doctor 会提示维护窗口重启。只有显式设置 `DDNS_ENTRY_AUTO_RESTART_RELAY=true` 时，timer 模式才会自动创建快照并重启 relay。

域名后端 IP 变化后，可手动同步 forward 来源 PBR：

```bash
lq pbr sync-from-forwards
```

域名 PBR 可手动同步：

```bash
lq pbr domain sync
```

## 转发端点分享输出

生成端点分享文件：

```bash
lq output generate
```

输出文件：

```text
/etc/leikwan-toolkit/outputs/forward-endpoints.txt
/etc/leikwan-toolkit/outputs/forward-endpoints.tsv
/etc/leikwan-toolkit/outputs/forward-endpoints.json
/etc/leikwan-toolkit/outputs/forward-endpoints.html
```

HTML 是静态文件，不需要 Web 服务；JSON 适合脚本读取；TXT 适合直接复制给使用方。端点输出只包含公网入口、业务端口、PRIMARY / BACKUP、TCP / UDP endpoint 和后端摘要，不包含 EasyTier network secret，不包含配对码，也不是代理链接。

如果系统安装了 `qrencode`，可以生成端点二维码：

```bash
lq output qr
```

二维码内容只是 `tcp://host:port` 或 `udp://host:port` 这种端点字符串。

## 常用命令

```bash
lq
lq status
lq --status
lq --doctor
lq port check
lq --port-check
lq config export --redacted
lq config list
lq output generate
lq output html
lq pair status
lq pbr show
lq pbr sync-from-forwards
lq pbr domain sync
lq ddns status
lq ddns run
lq update check
lq update run
lq forward list
lq forward apply-relay --auto-fix-route
lq --uninstall
```

交互菜单默认会在进入菜单前清屏，保持 SSH 页面干净。调试时可临时禁用清屏：

```bash
LEIKWAN_NO_CLEAR=1 lq
```

窄终端会自动切换为紧凑列表显示。也可以手动指定：

```bash
LEIKWAN_COMPACT=1 lq
LEIKWAN_TABLE=1 lq
```

菜单动作的输出会停留在当前屏幕，按回车继续。公网入口接入码和入口返回码会额外要求确认：输入 `y` 返回菜单，输入 `r` 重新显示单行码，输入 `p` 显示保存路径，直接回车不会返回菜单。

## 升级

推荐使用内置自更新。它只从 GitHub Release 包更新，下载 `.tar.gz` 和 `.sha256`，校验通过后才替换 `/root/leikwan-toolkit.sh`：

```bash
lq update check
lq update run
lq update status
lq update rollback
```

也可以使用短参数：

```bash
lq --update-check
lq --self-update
```

如果国内网络访问 GitHub 较慢，可设置镜像：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

自更新只替换脚本，不删除 `/etc/leikwan-toolkit` 配置。更新失败会保留旧脚本；替换后版本校验失败会自动恢复更新前备份。

也可以重新运行 bootstrap 安装最新版脚本：

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh
```

也可以直接覆盖 `/root/leikwan-toolkit.sh`，然后执行：

```bash
chmod +x /root/leikwan-toolkit.sh
ln -sf /root/leikwan-toolkit.sh /usr/local/bin/lq
ln -sf /root/leikwan-toolkit.sh /usr/local/bin/LQ
```

## 卸载

交互菜单中选择：

```text
主菜单 -> 卸载全部
```

或执行：

```bash
lq --uninstall
```

卸载会清理脚本生成的服务、配置、nftables 表、sysctl 配置、快捷命令、日志和备份目录。

## 安全说明

- 配对码包含 EasyTier network secret，应视为敏感信息。
- 配置快照可能包含 EasyTier network secret，应视为敏感文件。
- 完整配置包包含 EasyTier network secret，应视为敏感文件。
- 脱敏配置包和端点输出不包含 secret，但仍建议发布前快速检查。
- 不要把配对码公开到工单、聊天记录或仓库。
- debug report 会脱敏后输出，但仍建议人工检查后再发送。
- 本工具只管理组网和四层转发，不保存代理协议链接，不管理后端业务认证。

## Release

当前正式版本：`1.2.0`

Release 包名：

```text
leikwan-toolkit-1.2.0.tar.gz
leikwan-toolkit-1.2.0.tar.gz.sha256
```
