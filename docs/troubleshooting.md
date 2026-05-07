# 排错

v0.4 的排错边界：EasyTier 负责 A/B 虚拟网络，nftables 负责 TCP 四层转发。后端目标协议由用户自行排查。

## doctor

```bash
sudo lq --doctor
sudo lq --doctor --verbose
```

普通模式只输出 `[OK] [WARN] [INFO] [FAIL]`。详细模式会显示配置文件路径等调试信息。

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
