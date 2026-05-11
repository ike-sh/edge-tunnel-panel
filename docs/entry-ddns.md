# A 端公网入口 DDNS

Leikwan Toolkit 1.3.4 开始支持 A 公网入口机器主动维护自己的 DDNS 域名。

双端职责要分清：

- A 端更新器：把本机当前公网 IP 更新到 DNS 服务商。
- B 端监控器：解析公网入口、后端转发目标和 PBR 域名，发现变化后同步 nftables / PBR / relay。

B 端不能替 A 端把 `home.example.com` 改到新公网 IP。如果 A 域名已经由路由器、DNS 服务商客户端或其它 DDNS 程序维护，可以不启用 `entry ddns`。

## 常用命令

```bash
lq entry ddns status
lq entry ddns setup
lq entry ddns run
lq entry ddns enable
lq entry ddns disable
lq entry ddns logs
```

也可以使用别名：

```bash
lq ddns entry status
lq ddns entry run
```

## 配置文件

```text
/etc/leikwan-toolkit/entry/ddns.env
```

默认不启用：

```text
ENTRY_DDNS_ENABLED=false
ENTRY_DDNS_PROVIDER=custom-url
ENTRY_DDNS_INTERVAL=5min
ENTRY_DDNS_IP_SOURCE=auto
```

`setup` 会提示敏感信息会保存在本机配置文件中。请保护好这个文件。

## custom-url

适合 DNS 服务商或自建网关提供 HTTP 更新接口的场景：

```text
ENTRY_DDNS_PROVIDER=custom-url
ENTRY_DDNS_UPDATE_URL=https://ddns.example.test/update?token=<redacted>&domain={host}&ip={ip}
```

脚本会替换 `{host}` 和 `{ip}`，然后用 `curl` 请求。普通 status、debug report 和 redacted export 不会明文输出 query 中的 token。

## custom-cmd

适合用户自己封装 DNSPod、Cloudflare、阿里云、腾讯云等 API：

```text
ENTRY_DDNS_PROVIDER=custom-cmd
ENTRY_DDNS_UPDATE_CMD=/usr/local/bin/update-ddns {host} {ip}
```

命令失败会 WARN / FAIL。日志会对 token、secret、password、key 和整条 `ENTRY_DDNS_UPDATE_CMD` 做脱敏。

## systemd timer

启用：

```bash
lq entry ddns enable
```

会安装：

```text
/etc/systemd/system/leikwan-entry-ddns.service
/etc/systemd/system/leikwan-entry-ddns.timer
```

日志：

```text
/var/log/leikwan-entry-ddns.log
```

状态：

```text
/etc/leikwan-toolkit/status/last-entry-ddns.env
```

## 与 B 端配合

B 端建议启用监控：

```bash
lq ddns enable
lq ddns run --scope all
lq ddns apply-entries
```

公网入口 DDNS 变化后，EasyTier relay 运行中不一定重新解析 peer 域名。B 端默认只记录 `relay restart needed`，不会自动中断链路。确认维护窗口可接受时，再设置：

```text
DDNS_ENTRY_AUTO_RESTART_RELAY=true
```
