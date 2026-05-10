# 工作流

本文说明 Leikwan Toolkit 1.1.1 的推荐操作顺序。

## 角色

- A：公网入口，可部署多台，用于接入公网流量。
- B：利群主机 / 中转主机，负责 EasyTier relay、PBR 和后端转发。
- C：后端目标，支持 TCP/UDP 转发。

链路：

```text
外部客户端 -> A 公网入口端口（TCP/UDP） -> EasyTier -> B 利群主机 -> 后端目标
```

## 快速组网

推荐顺序：

1. B：修复 DNS / IPv4。
2. B：生成公网入口网络码。
3. A：粘贴网络码部署入口。
4. B：粘贴 A 返回码完成接入。
5. A：配置公网入口端口池。
6. B：添加后端转发目标。

如果后端需要指定出口，先配置 PBR，再添加或重应用转发目标。

## 多公网入口

新入口默认命名：

```text
public1 -> 公网1
public2 -> 公网2
public3 -> 公网3
```

连续生成多个入口码时，脚本会写入 pending reservation，后续推荐会同时排除已保存入口和 pending 入口，因此会依次推荐 `public1 10.198.1.2 tcp+udp/8301`、`public2 10.198.1.3 tcp+udp/8302`、`public3 10.198.1.4 tcp+udp/8303`。

连接码输出后需要输入 `y` 确认返回菜单；输入 `r` 可重新显示单行码，输入 `p` 可显示保存路径，直接回车不会返回菜单。

A 的 ENTRY 返回码接回 B 后，会按 `ENTRY_ET_IP + EASYTIER_PORT` 清理对应 pending。ENTRY 名称和 pending 名称不同也允许保存。

## 终端显示

窄 SSH 终端会自动切换为紧凑列表，避免中英文混排表格错位。可用 `LEIKWAN_COMPACT=1 lq` 强制紧凑列表，用 `LEIKWAN_NO_CLEAR=1 lq` 禁用清屏；调试宽表时可尝试 `LEIKWAN_TABLE=1 lq`。

## 公网入口管理

菜单路径：

```text
利群主机 -> 公网入口列表管理
```

可执行：

- 生成新公网入口接入码
- 粘贴公网入口返回码并接入
- 手动添加公网入口
- 修改公网入口详情
- 删除公网入口
- 启用 / 禁用公网入口
- 修改权重
- 切换主公网入口
- 批量启用 / 禁用公网入口
- 查看 / 清理未完成接入码

入口变更后默认不会静默重启 relay。脚本会提示是否现在重启，选择 `N` 时运行中的 relay peer 不会改变。

## 端口

- EasyTier 组网端口：默认 `8301`、`8302`、`8303`，TCP+UDP，同端口，建议位于 `8000-9000`。
- 业务入口端口：常用 `10001-19999`，默认 TCP+UDP 转发。
- 后端目标端口：由用户填写。

新增公网入口前会检查 EasyTier 端口是否已被 `entries.tsv`、`pending-entries.tsv`、本机监听进程或 nftables dport 占用。新增转发目标前会检查业务入口端口是否已被 `forwards.tsv`、本机监听进程或 nftables DNAT 占用。推荐端口会自动跳过这些冲突。

可随时执行轻量端口预检：

```bash
lq port check
lq --port-check
```

端口预检只读，不修改系统。

## 状态总览

日常查看建议使用：

```bash
lq status
lq --status
```

`status` 输出角色、版本、入口数量、转发数量、nftables、MSS clamp、最近应用和最近诊断，适合快速确认状态。它只做轻量检查，不执行 ping、nc 或 apt update，也不会自动修改系统。

`doctor` 适合排障，会做更完整的链路、DNAT、MSS、依赖和 DNS 检查；交互菜单中可按提示执行修复。

## 脚本更新

检查 GitHub Release 最新版本：

```bash
lq update check
```

更新到最新正式 release：

```bash
lq update run
```

更新只替换 `/root/leikwan-toolkit.sh`，不会删除 `/etc/leikwan-toolkit` 配置。更新失败会保留旧脚本，替换后版本校验失败会自动恢复备份。

## 配置快照 / 回滚

菜单路径：

```text
高级功能 -> 配置快照 / 回滚
```

可创建完整快照、查看列表、按编号恢复、删除旧快照，以及导出最新快照到 `/root/leikwan-snapshot-YYYYMMDD-HHMMSS.tar.gz`。

快照可能包含 EasyTier network secret，请按敏感文件保存。恢复快照前会二次确认，恢复后会询问是否立即 reload systemd 并重启相关服务。

高危操作前会自动创建轻量快照，包括重启 relay、重新应用 nftables 转发规则、删除公网入口、批量禁用公网入口、删除转发目标、删除 PBR 规则、卸载全部和恢复快照前。自动快照保存在 `/etc/leikwan-toolkit/snapshots/auto/`，只保留最近 10 个。

## PBR

如果需要 CN2、9929 或其它指定出口：

1. 先配置 PBR。
2. 再添加转发目标。

如果先添加了转发目标，后添加 PBR，请执行：

```bash
lq forward apply-relay --auto-fix-route
```

从现有转发目标添加 PBR 后，脚本会默认询问是否立即执行上述同步。

## DDNS 后端自动刷新

如果后端目标是 DDNS 域名，建议在转发目标稳定后启用自动刷新：

```bash
lq ddns enable
lq ddns status
```

脚本会定期检查 enabled 转发目标中的域名后端。解析 IP 变化时，会更新 `resolved.tsv`、创建自动快照并安全重应用 nftables 转发规则；解析失败时保留旧 IP。

PBR 默认不会自动同步。域名 IP 变化后，可执行：

```bash
lq pbr sync-from-forwards
```

## 诊断

A 和 B 都可以执行：

```bash
lq --doctor
```

doctor 会检查 EasyTier、nftables、PBR、TCP/UDP DNAT、MSS clamp、入口 TCP/UDP 探测和后端目标探测。UDP 探测只作为参考，最终应结合 EasyTier peer / ping 和业务实测判断。
