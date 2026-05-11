# Leikwan Toolkit 1.4.0 LTS 最终版使用手册

1.4.0 LTS 是功能冻结版。Leikwan Toolkit 的定位收敛为：

```text
A 公网入口 + B 中转主机 + C 后端目标 的 TCP/UDP 转发组网工具
```

后续版本主要只做 bug fix、兼容性修复、安全修复和文档完善。

## 最短使用路径

只想把服务跑起来，按这个顺序：

1. B 安装工具，执行 `lq init`。
2. B 生成公网入口接入码。
3. A 安装工具，粘贴接入码并部署入口。
4. B 粘贴 A 返回码完成接入。
5. B 添加后端转发目标。
6. B 生成端点输出，交给使用方连接。

主菜单只保留 6 个入口：

```text
1. 快速组网
2. 利群主机 B
3. 公网入口 A
4. DDNS
5. 状态 / 诊断
6. 高级维护
0. 退出
```

## B 利群主机

B 端负责：

- 管理公网入口列表
- 管理后端转发目标
- 可选 IPv4 PBR 出口策略
- 应用 nftables 转发规则
- 查看 B 端状态

常用命令：

```bash
lq status
lq --doctor
lq forward apply-relay --auto-fix-route
```

## A 公网入口

A 端负责：

- 粘贴 B 生成的接入码
- 部署本机 entry service
- 配置入口端口池
- 可选维护本机公网入口 DDNS

常用命令：

```bash
lq entry expose-range
lq entry ddns status
lq status
```

## DDNS

DDNS 分成两端：

- A 端 DDNS：让域名指向 A 当前公网 IP。
- B 端 DDNS：发现 entries / forwards / PBR 域名变化后刷新转发、PBR 或 relay 状态。

如果 A 域名已有外部 DDNS 客户端维护，可以不启用 A 端 DDNS。

```bash
lq ddns overview
lq ddns check-consistency
lq ddns apply-entries
```

## 高级维护

低频和高危操作都收进“高级维护”：

- EasyTier 服务管理
- 配置备份 / 快照 / 回滚
- 配置导入 / 导出
- 自更新
- 端点输出
- 调试报告
- 卸载

高危操作仍会保留确认、自动快照和锁保护。
