# 验收测试

本页用于 v0.4.0-alpha 收尾验收。

## 静态检查

```bash
bash -n leikwan-toolkit.sh wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
shellcheck leikwan-toolkit.sh wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
git diff --check
scripts/check-redaction.sh
scripts/package-release.sh
```

Release 包应生成：

```text
dist/leikwan-toolkit-0.4.0-alpha.tar.gz
```

包内包含：

```text
leikwan-toolkit.sh
wg-toolkit.sh
uninstall.sh
scripts/bootstrap.sh
docs/
README.md
```

## 命名

Banner 显示：

```text
Leikwan Toolkit
利群快速组网工具
Author : ike-sh
Version: 0.4.0-alpha
GitHub : https://github.com/ike-sh/leikwan-toolkit
```

安装命令使用：

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
```

主脚本安装为 `/root/leikwan-toolkit.sh`，`wg-toolkit.sh` 是旧名称兼容 wrapper。

## 快速组网菜单

必须显示第 7 项 PBR、第 8 项完整说明：

```text
2. 我现在在利群主机：生成 / 新增公网入口网络码
3. 我现在在公网入口：粘贴利群网络码，部署本机入口
4. 我现在在利群主机：粘贴公网入口返回码，完成接入
7. IPv4 多出口策略路由 / PBR
8. 查看完整分步说明
```

已有 `aliyun 10.198.1.2 tcp/8301` 时，B 再生成网络码，应推荐 `home` 或 `entry2`、`10.198.1.3`、`8302`。

新 A 粘贴网络码部署时，默认使用 B 推荐的 `SUGGESTED_ENTRY_NAME`、`SUGGESTED_ENTRY_ET_IP`、`SUGGESTED_EASYTIER_PORT`。

## 公网入口管理

B 侧路径：

```text
利群主机 -> 公网入口列表管理
```

删除、启用/禁用、修改权重、测试公网入口必须先展示列表，支持编号或名称，空输入返回。

A 侧路径：

```text
主菜单 -> 公网入口
```

只保留本机功能：部署本机入口、配置本机入口端口池、查看本机公网入口状态。在 B 上误进状态页时，应 WARN 并引导到 B 侧入口列表管理。

## 转发目标

添加转发目标时：

- 公网入口端口提示显示端口池范围和推荐下一个未使用端口。
- 后端目标端口不显示默认值，空输入会 WARN。

修改、删除、启用/禁用、测试单个转发目标必须先展示列表，支持编号或名称。修改、删除、启用/禁用后必须重新生成 `resolved.tsv` 并应用 relay nftables。

域名目标示例：

```text
name=Hinet
entry_port=10002
target_host=tw.example.com
target_port=52936
```

列表应显示：

```text
Hinet 10002 -> tw.example.com(203.0.113.20):52936 eth1 - enabled
```

`apply-relay` 每次重新解析域名；IP 变化时输出解析变化并刷新 nftables。

## PBR

菜单：

```text
1. 添加静态 PBR
2. 从现有转发目标添加 PBR
3. 应用 PBR
4. 查看 PBR
```

静态 PBR 输入域名时，应提示改用“从现有转发目标添加 PBR”。从转发目标选择域名后端时，应解析当前 IP 并写入 `resolved_ip/32`，同时记录来源转发名和 `target_host`。

## 旧名称检查

旧仓库 URL、旧英文标题和旧后端端口提示不应命中主线内容；旧名称只允许出现在兼容 wrapper、迁移说明和卸载兼容清理中。
