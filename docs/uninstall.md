# 卸载

Leikwan Toolkit 1.3.5 将卸载拆成普通卸载和深度卸载，方便真实机器维护时保留可恢复材料。

## 入口

交互菜单：

```text
卸载
----------------------------------------
1. 普通卸载：移除服务和规则，保留配置 / 快照 / 备份
2. 深度卸载：移除服务、规则、配置、日志、状态
0. 返回
```

CLI：

```bash
lq uninstall normal
lq uninstall deep --yes
lq --uninstall
```

非交互卸载必须显式 `--yes`。预览可使用：

```bash
lq --dry-run uninstall normal --yes
lq --dry-run uninstall deep --yes
```

## 普通卸载

普通卸载会：

- 停止并禁用 EasyTier relay / entry、nft forward、DDNS timer/service。
- 删除 Leikwan 管理的 systemd unit。
- 删除项目 nftables table。
- 清理 Leikwan 管理的 PBR rule / route table 项。
- 删除 `/usr/local/bin/lq` 和 `/usr/local/bin/LQ`。

普通卸载会保留：

- `/etc/leikwan-toolkit`
- `/var/backups/leikwan-toolkit`
- `/root/leikwan-config-*.tar.gz`
- 快照、DDNS、entries、forwards、PBR 配置

## 深度卸载

深度卸载会先创建：

```text
/root/final-before-uninstall-YYYYMMDD-HHMMSS.tar.gz
```

然后执行普通卸载，并额外删除：

- `/etc/leikwan-toolkit`
- `/var/log/leikwan-ddns-refresh.log`
- `/root/lq-apply-relay.log`
- `/run/leikwan-*.lock`

深度卸载会要求输入 `DELETE`。如果卸载前 final snapshot 失败，默认不继续。

## 卸载后状态

如果脚本仍在，可以继续运行：

```bash
/root/leikwan-toolkit.sh status
/root/leikwan-toolkit.sh --doctor
```

没有配置目录时会提示尚未初始化，并建议执行 `lq init`，不会触发全局 trap。

