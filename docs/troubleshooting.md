# 排错

v0.4 的排错边界：EasyTier 负责 A/B 虚拟网络，nftables 负责 TCP 四层转发。后端目标协议由用户自行排查。

## doctor

```bash
sudo lq --doctor
sudo lq --doctor --verbose
```

普通模式只输出 `[OK] [WARN] [INFO] [FAIL]`。详细模式会显示配置文件路径等调试信息。

## EasyTier 下载失败

EasyTier release 包较大，GitHub 直连慢时可能出现下载到一半超时。v0.4 安装器会把大文件先写入 `.part` 临时文件，只有在文件大于 10MB 且压缩包校验通过后才安装，不会把半截文件当成成功。

可先设置镜像轮询：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

排查顺序：

1. 执行 `DNS / IPv4 优先修复`。
2. 重新安装 EasyTier。
3. 如果仍失败，手动下载 EasyTier zip 后，在脚本提示时输入本地路径。

下载日志如果出现每个候选 URL 都失败，脚本会列出已尝试地址，便于判断是 DNS、GitHub、镜像还是本机出口问题。

## entry 端口不通

检查：

```bash
systemctl status easytier-entry-aliyun --no-pager
ss -lntup | grep 8301
```

常见原因：

- 云安全组没有放行 TCP `8301`。
- EasyTier binary 安装失败。
- 配对码中的公网地址填错。

## relay 看不到入口

检查：

```bash
systemctl status easytier-relay --no-pager
easytier-cli peer
cat /etc/leikwan-wg-toolkit/entries/entries.tsv
```

如果 `entries.tsv` 已登记但 peer 不可见，先确认 relay 能访问 `ENTRY_PUBLIC_HOST:8301`。

## EasyTier IP 不存在

```bash
ip -br addr
```

doctor 会通过本机 EasyTier IP 查找虚拟接口。如果服务 active 但 IP 不存在，通常是 EasyTier 参数不兼容或 network secret 不一致。

## nftables 未生效

检查项目表：

```bash
nft list table inet leikwan_forward
```

脚本只管理这个表。应用规则前会执行 `nft -c -f`，失败会尝试回滚。

如果 `enabled forwards` 大于 0，但表里没有 `dnat` 规则，说明入口或 relay 侧规则没有正确生成。重新执行：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1  # 在 A entry 上，仅需一次
sudo lq forward add                                                    # 在 B relay 上
```

cloud-entry 侧不直接转发到后端目标，只生成端口池 DNAT：

```text
tcp dport 10000-19999 dnat ip to 10.198.1.1
```

relay 侧才会生成：

```text
tcp dport ENTRY_PORT dnat ip to TARGET_IP:TARGET_PORT
```

## 有延迟但应用层连不上

如果后端直连成功，但经 A -> EasyTier -> B 转发后连接失败，优先检查 TCP MSS clamp。

典型场景：

```text
直连后端 TCP 服务成功
A_PUBLIC_HOST:ENTRY_PORT -> A -> EasyTier/tun -> B -> TARGET_HOST:TARGET_PORT 失败
```

A 和 B 的项目 nftables 表都应该包含：

```text
tcp flags syn tcp option maxseg size set 1320
```

修复：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1  # A
sudo lq forward apply-relay                                           # B
sudo lq --doctor
```

doctor 显示 `TCP MSS clamp enabled: 1320` 即为启用。

默认值 `1320` 是当前验证的最高稳定值。如果仍然出现“有延迟但无法连接”，建议依次降到 `1280`、`1200`：

```bash
sudo install -d -m 700 /etc/leikwan-wg-toolkit/nft
printf 'TCP_MSS_CLAMP=1280\nENABLE_MSS_CLAMP=true\n' | sudo tee /etc/leikwan-wg-toolkit/nft/mss.env >/dev/null
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
sudo lq forward apply-relay
```

`forwards.tsv` 必须是 8 列 TAB 分隔。默认请使用 `lq forward add/edit/delete`，不要手写空格对齐。

v0.4 默认不再推荐 `lq forward import`。A 只需要配置入口端口池，B 负责所有 `forward add/edit/delete`。

## target 不通

在 relay 上测试：

```bash
nc -vz -w 3 <TARGET_HOST> <TARGET_PORT>
ip route get <TARGET_IP>
```

如果使用 PBR，确认 `route_table` 与 `ip rule` 已生效。

## 生成脱敏报告

```text
高级功能 -> 生成脱敏故障报告
```

输出：

```text
/root/leikwan-debug-report.txt
```

报告会脱敏 EasyTier network secret、历史私钥字段和常见代理链接格式。
