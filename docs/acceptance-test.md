# 验收测试

## 基础检查

```bash
shellcheck wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
bash -n wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
scripts/check-redaction.sh
git diff --check
scripts/package-release.sh
```

## 菜单检查

主菜单应显示：

```text
1. 快速组网（分步提示）
2. 利群主机
3. 公网入口
4. 高级功能
5. 一键诊断
6. 卸载全部
0. 退出
```

进入 `快速组网（分步提示）` 后，第一屏必须提示利群主机先执行 DNS / IPv4 优先修复。`利群主机` 菜单只包含 B 侧转发目标、PBR、IPv6 收口和状态检查。`公网入口` 菜单只包含 A 侧入口机管理、端口池和状态检查。`高级功能 -> nftables 规则管理` 在未配置规则文件或 nft table 时应显示 WARN，不应退出脚本。

## clean-room 最小流程

### B：生成网络码

```bash
sudo lq pair relay-init
```

合格标准：

- `/etc/leikwan-wg-toolkit/easytier/network.env` 存在。
- 输出 `BEGIN LEIKWAN EASYTIER NETWORK`。
- 输出 `LEIKWAN_EASYTIER_NETWORK_BASE64=`。
- 不包含系统私钥。

### A：部署入口

```bash
sudo lq pair entry-join
```

粘贴 B 网络码。

合格标准：

- `easytier-entry-aliyun.service` active。
- `ss -lntup` 可见 `8301/tcp`。
- `systemctl cat easytier-entry-aliyun` 中 `ExecStart` 包含 `tcp://0.0.0.0:8301`。
- 不应出现默认监听 `11010/tcp`。
- `/etc/leikwan-wg-toolkit/outputs/easytier-entry-code.env` 存在。
- 输出 `BEGIN LEIKWAN EASYTIER ENTRY`。

### B：接入入口

```bash
sudo lq pair relay-join
```

粘贴 A 入口码。

合格标准：

- `/etc/leikwan-wg-toolkit/entries/entries.tsv` 存在并包含入口。
- `easytier-relay.service` active。
- `systemctl cat easytier-relay` 中 peer 目标包含 `:8301`，不应连接 `:11010`。
- `easytier-cli peer` 能看到入口，或 doctor 给出明确 WARN。
- `ping 10.198.1.2` 成功，或输出可排查原因。

## doctor 端口与延迟

合格标准：

- `lq --doctor` 对 `8301` 显示白名单 OK。
- 如果手工改成 `11010`，doctor 必须 WARN。
- ping 100% loss 不能显示 OK。
- ping 平均 RTT 大于 `200ms` 时 WARN，大于 `1000ms` 时 FAIL 或强 WARN。

## nftables 转发

在 A 公网入口机配置入口端口池：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
```

合格标准：

- `nft list table inet leikwan_forward` 存在。
- A 侧有 `tcp dport 10000-19999 dnat ip to 10.198.1.1`。
- A 侧有 `tcp flags syn tcp option maxseg size set 1320`。
- A doctor 显示 `[OK] 入口端口池：10000-19999 -> 10.198.1.1`。
- A doctor 显示 `[OK] TCP MSS clamp enabled: 1320`。

在 B 使用 `利群主机 -> 转发目标管理` 添加：

```bash
sudo lq forward add
```

输入示例：

```text
name=service-a
entry_port=10001
target_host=203.0.113.30
target_port=30004
```

脚本应自动写入 B 的 `forwards.tsv`，并应用 B relay nftables。A 不需要导入转发码。

合格标准：

- `nft list table inet leikwan_forward` 存在。
- B 侧有 `tcp dport 10001 dnat ip to <resolved-target>:30004`。
- B 侧有 `tcp flags syn tcp option maxseg size set 1320`。
- B doctor 显示 `service-a relay DNAT 正常`。
- B doctor 显示 `[OK] TCP MSS clamp enabled: 1320`。
- 外部访问 `A_PUBLIC_HOST:10001` 能到达后端 TCP 服务。

新增第二个后端：

```bash
sudo lq forward add
```

使用 `entry_port=10002`。合格标准：不需要重新操作 A，外部访问 `A_PUBLIC_HOST:10002` 能到达第二个后端。

已验证场景：

```text
A expose-range: 10001-10020 -> 10.198.1.1
B forward: 10001 -> 203.0.113.30:37592
B forward: 10002 -> 198.51.100.20:30004
```

外部验收：

```bash
nc -vz -w 5 A_PUBLIC_HOST 10001
nc -vz -w 5 A_PUBLIC_HOST 10002
```

合格标准：两条连接都成功；新增第二个后端时不需要修改 A。

## MSS clamp 验收

已验证故障模型：

```text
直连 TARGET_HOST:TARGET_PORT 成功。
经 A_PUBLIC_HOST:ENTRY_PORT -> A -> EasyTier/tun -> B -> TARGET_HOST:TARGET_PORT 初始失败。
A/B 的 leikwan_forward 表加入 MSS 1320 后链路成功。
```

合格标准：

- A 和 B 都不需要手工创建 `lq_mss` 临时表。
- `/etc/leikwan-wg-toolkit/nft/leikwan-forward.nft` 包含 `tcp option maxseg size set 1320`。
- `leikwan-nft-forward.service` 重启后 MSS clamp 仍存在。
- `sudo lq --doctor` 对 A/B 都显示 `TCP MSS clamp enabled: 1320`。
- 修改 `/etc/leikwan-wg-toolkit/nft/mss.env` 为 `TCP_MSS_CLAMP=1280` 后重新应用，doctor 显示 `TCP MSS clamp enabled: 1280`。
- 如果 1320/1280 仍不稳定，可降到故障兜底值 `1200`。

删除一个后端：

```bash
sudo lq forward delete service-a
```

合格标准：不需要重新操作 A，`10001` 不再通，`10002` 仍然通。

## forwards.tsv 容错

人为写入错误内容：

```text
# nameentry_porttarget_hosttarget_portout_ifaceroute_tableenabledcomment
service-a10001203.0.113.3030004truecomment
```

合格标准：

- 应用 nftables 时必须失败，不能继续生成空转发表。
- 输出第 N 行字段数错误，并提示“期望 8 列，实际 X 列”。
- 输出当前行内容，并提醒必须使用 TAB 分隔。
- enabled forwards 为 0 时，应用空规则必须二次确认，默认不应用。
- `resolved.tsv` 没有可用转发时，不显示“nftables 转发规则已应用”。
- 如果 `table inet leikwan_forward` 存在但没有 DNAT 规则，doctor 必须 WARN。

## 多入口

添加 `aliyun`、`tencent`、`home` 三个入口。

合格标准：

- `entry_name` 唯一。
- `et_ip` 唯一。
- disabled 入口不参与输出。
- `forward-endpoints.txt` 按权重列出入口。

## doctor

```bash
sudo lq --doctor
```

合格标准：

- cloud-entry 检查 EasyTier entry、监听端口、nftables。
- relay 检查 EasyTier relay、entries、forwards、target、PBR。
- 主流程诊断不出现旧 0.2/0.3 组件字段。

## 脱敏

```bash
scripts/check-redaction.sh
```

合格标准：

- README/docs 不包含真实公网测试 IP。
- README/docs 不包含 EasyTier network secret。
- README/docs 不包含任何代理协议链接。
