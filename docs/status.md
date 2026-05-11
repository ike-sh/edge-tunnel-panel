# 状态输出

Leikwan Toolkit 1.3.2 对 `lq status` 做了稳定化整理，目标是让日常巡检像正式运维系统一样可读、可脚本化、不会误报角色。

## 常用命令

```bash
lq status
lq --status
lq --brief
lq --compact
lq status --brief
lq status --json
lq --status-json
LEIKWAN_BRIEF=1 lq status
```

## 角色识别

角色判断只使用真正能证明角色的信号：

- relay：`easytier-relay.service` 存在，或 `network.env` 中 `ROLE=leikwan-relay`。
- entry：`easytier-entry-*.service` 存在，或 `ROLE=cloud-entry`，或 A 侧 entry env / service 状态存在。

`entries.tsv` 不再作为 entry 判据，因为 B relay 本来就管理公网入口列表。`forwards.tsv` 只作为 relay 辅助信息，不能单独决定角色。

只有真实同时部署 relay 和 entry 时才会显示：

```text
[WARN] 检测到高级混合部署：relay + entry
```

## 简洁模式

简洁模式适合日常监控或窄终端：

```text
Leikwan Status
----------------------------------------
Role: relay
EasyTier: OK
Entries: 2 enabled
Forwards: 4 enabled
PBR: 4
DDNS: OK
nftables: OK
Health: 96/100 (excellent)
Overall: OK
```

JSON 输出不受简洁模式影响，仍输出结构化摘要。

## 健康度评分

`status` 和 JSON 都包含系统健康度：

- 90-100：excellent
- 75-89：good
- 50-74：warning
- 0-49：critical

评分会参考 EasyTier、relay / entry 服务、entries、forwards、PBR、nftables、MSS clamp、DDNS、锁和最近错误。它是巡检提示，不替代 `lq --doctor` 的详细诊断。

## disabled 项

禁用的公网入口或转发目标会保留历史配置，但不再进入 WARN / FAIL 聚合。例如端口预检会显示：

```text
[INFO] 8303 public3 已 disabled，保留历史配置。
```

只有 enabled 项发生端口冲突、nft 缺失或监听异常时才会 WARN。
