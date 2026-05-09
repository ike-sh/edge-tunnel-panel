# 验收清单

本页用于 Leikwan Toolkit 1.0.2 正式版验收。

## 版本

```bash
grep -n '^TOOL_VERSION=' leikwan-toolkit.sh
bash leikwan-toolkit.sh --version
```

期望：

```text
TOOL_VERSION="1.0.2"
leikwan-toolkit 1.0.2
```

## 打包

```bash
bash -n leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
shellcheck leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
git diff --check
bash scripts/check-redaction.sh
bash scripts/package-release.sh
```

期望生成：

```text
dist/leikwan-toolkit-1.0.2.tar.gz
dist/leikwan-toolkit-1.0.2.tar.gz.sha256
```

release 包不得包含旧入口文件：

按发布验收命令检查包内容，确认不包含旧入口文件和旧卸载脚本。

## 快速组网

1. B 生成公网入口接入码，默认推荐 `public1 / 公网1 / 10.198.1.2 / tcp+udp / 8301`。
2. 不粘贴 ENTRY，继续生成第二份，推荐 `public2 / 公网2 / 10.198.1.3 / tcp+udp / 8302`。
3. 如果已有旧入口 `aliyun -> 10.198.1.2/8301` 和 `home -> 10.198.1.3/8302`，下一台必须推荐 `public3 / 公网3 / 10.198.1.4 / 8303`。
4. A 粘贴网络码部署入口，systemd service 同时包含 TCP 和 UDP listener。
5. A 返回 ENTRY 后，B 能保存入口并清理 pending。
6. ENTRY 名称和 pending 名称不同也能保存并清理命中的 pending。

## 多公网入口

准备：

```text
public1  203.0.113.10   10.198.1.2  tcp,udp  8301  100  true
public2  203.0.113.20   10.198.1.3  tcp,udp  8302  100  true
```

验收：

- 列表显示 `公网1(public1)`、`公网2(public2)`。
- relay service peer 包含 TCP+UDP 两个协议。
- 切换主入口模式 1 后，只保留选中入口 enabled。
- 切换主入口模式 2 后，选中入口标记 PRIMARY，其它 enabled 入口标记 BACKUP。
- 批量禁用所有入口必须二次确认。

旧入口名仍兼容，可继续读取、修改、删除、启用禁用和切换主入口。

## 转发与 PBR

- A 侧端口池必须生成 TCP+UDP DNAT。
- B 侧转发目标必须生成 TCP+UDP DNAT。
- PBR 菜单显示 `0. 返回`。
- 从现有转发目标添加 PBR 后，默认询问是否立即同步转发规则和 `route_table` 元数据。
- 删除 PBR 支持编号、CIDR 和裸 IP。

## 交互

- 主菜单显示清晰 banner。
- 子菜单不重复大 banner。
- 菜单进入前会清屏；`LEIKWAN_NO_CLEAR=1 lq` 可禁用清屏。
- 菜单动作输出必须停留，按回车后才继续。
- NETWORK / ENTRY 连接码输出后，直接回车不能返回菜单；必须输入 `y`，输入 `r` 可重显，输入 `p` 可显示保存路径。
- 快速组网说明简洁。
- 生成 NETWORK / ENTRY 配对码后，单行码停留在最后一行，并提示按回车返回。
- doctor、debug report、转发入口输出等长输出后等待回车返回菜单。

## 卸载

卸载后检查：

```bash
test ! -e /var/log/leikwan-toolkit.log && echo "OK: no log"
test ! -e /etc/leikwan-toolkit && echo "OK: no state"
test ! -e /var/backups/leikwan-toolkit && echo "OK: no backups"
command -v lq || echo "OK: no lq"
```

卸载检查结果中日志文件应显示已清理，且卸载结束后不应重新创建日志。
