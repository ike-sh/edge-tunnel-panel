# 故障排查

Leikwan Toolkit 1.0.4 主线是 EasyTier 传输 + nftables 四层 TCP/UDP 转发。脚本不部署后端业务，只负责：

```text
外部客户端 -> A 公网入口端口（TCP/UDP） -> EasyTier -> B 利群主机 -> 后端目标
```

## 一键诊断

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

## MSS clamp

MSS clamp 用于提高 EasyTier/tun 场景下 TCP 转发稳定性。doctor 和状态页面只检测，不自动修改；应用 A 侧端口池或 B 侧转发规则时会重新渲染 nftables，并明确输出是否自动启用 MSS clamp。

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

## 脱敏报告

生成脱敏报告：

```bash
lq --doctor --verbose
```

或使用交互菜单中的“生成脱敏故障报告”。报告会尽量脱敏，但仍建议人工检查后再发送。
