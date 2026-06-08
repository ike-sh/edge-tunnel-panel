# ix-transit-fabric → Edge Tunnel Panel 迁移设计文档

> **版本**: v0.2-revised  
> **日期**: 2026-06-09  
> **作者**: 资深全栈架构师  
> **状态**: 评审修订中（API + UI 已更新，待确认后启动 Phase 1）

### v0.2 修订摘要（基于评审 A+B+C）

**API 修订**:
- 新增 `POST /api/v2/profiles/:id/sync` — 从 Agent 拉取本地状态
- 新增 `GET /api/v2/tasks/:id/stream` — SSE 任务进度推送
- 规则路由扁平化：`GET /api/v2/rules?profile_id=` 作为列表备选
- 接入码导入改为 `POST /api/v2/machines/:id/import-code`（绑定目标机器）
- 统一 Action 命名：`ixtf_*` → 分组前缀 `ix_read_*` / `ix_write_*`

**UI 修订**:
- 导航从 8 页精简为 **6 页**（合并线路+规则+接入码）
- 接入码改为 Profile 详情 Drawer，非独立页面
- 新增「线路详情」Tab 布局：概览 | 规则 | 接入码 | 端口地图
- Dashboard 增加链路拓扑可视化（ASCII/SVG 路径图）

---

## 1. 背景与目标

### 1.1 背景

| 项目 | 现状 |
|------|------|
| **edge-tunnel-panel** | Web 控制台 + Go Controller/Agent，管理节点组网、转发、PBR |
| **ix-transit-fabric** | 单文件 Bash CLI（~16,000 行），管理 NAT-IX 中转线路，**已移除** Web Panel 集成 |

两个项目由同一作者（ike）维护，业务场景高度重叠但实现形态完全不同。用户希望：

1. **移除** edge-tunnel-panel 原有功能（节点/组网/PBR 模型）
2. **迁移** ix-transit-fabric 全部能力到 Web Panel
3. **保留** 已完成的 macOS 26.5 毛玻璃 UI 外壳

### 1.2 目标

- 通过 Web UI 完成 ix-transit-fabric 的全部核心流程
- 支持 NAT IX 机器 + 公网入口机 双角色部署
- 支持多线路、多转发规则、接入码、DDNS、诊断、流量统计
- 保持 Agent allowlist 安全模型（禁止任意 shell）

### 1.3 非目标（Phase 1–2 不做）

- 主备切线自动化（`switch-line`）— Phase 3
- 通知/Webhook 集成 — Phase 3
- 将 16,000 行 Bash 全部重写为 Go — Phase 3 渐进

---

## 2. 架构对比

### 2.1 现有 edge-tunnel-panel 架构

```text
用户 → Web UI (React/Vite)
         ↓ REST
       Controller (Go) → SQLite/JSON 存储
         ↓ 任务队列
       Agent (Go) → nftables / EasyTier / ip rule
```

**数据模型**: Node → NetworkLink → ForwardRule → PBRPolicy → Task

### 2.2 ix-transit-fabric 架构

```text
运维人员 → ix CLI (Bash) / 交互菜单
             ↓
           install.sh → profiles/*.env + rules/* + nftables
             ↓
           EasyTier + nftables（项目级，不接管全局）
```

**数据模型**: Profile（线路）→ Rules（转发规则）→ AccessCode（接入码 v4）

### 2.3 目标架构（推荐：Agent 桥接 + 渐进原生化）

```text
用户 → Web UI (React/Vite, macOS 26.5 Glass)
         ↓ REST /api/v2/*
       Controller (Go)
         ├── ProfileStore（线路元数据）
         ├── RuleStore（转发规则）
         └── TaskOrchestrator
               ↓ allowlist tasks
       Agent (Go)
         ├── ixtf CLI 桥接层（Phase 1）
         └── 原生 Go 模块（Phase 3 渐进替换）
               ↓
         ix-transit-fabric install.sh + profiles/
```

---

## 3. 概念映射

### 3.1 角色映射

| edge-tunnel-panel（旧） | ix-transit-fabric | 新 Panel |
|------------------------|-------------------|----------|
| A 公网入口节点 | 公网入口机 (`ROLE=nat-ingress`) | **Ingress 机器** |
| B 落地节点 | NAT IX 机器 (`ROLE=nat-transit`) | **NAT IX 机器** |
| 组网链路 | Profile + EasyTier 组网 | **线路 Profile** |
| 转发规则 | ForwardRule（A→B→落地） | **Rule**（多规则数组） |
| PBR 出口策略 | ❌ ix 不支持 | **移除** |
| Agent Token | — | 保留 |
| 接入码 | — | **新增核心** |

### 3.2 数据流（NAT IX 正式流程）

```text
① NAT IX 机器：Web → 创建线路 Profile → Agent 执行 add-nat-listener-profile
② 生成接入码（code_schema=4，含密钥，脱敏展示）
③ 公网入口机：Web → 导入接入码 → Agent 执行 import-code
④ 指定客户端入口端口（LOCAL_PORT）
⑤ 客户端连接：公网入口 IP:LOCAL_PORT
⑥ 验证：health / show-port-map / latency-report
```

### 3.3 Profile 环境变量（核心字段）

来源：`examples/nat-ix-listener.env` / `examples/public-ingress.env`

| 字段 | NAT IX | 公网入口 | 说明 |
|------|--------|----------|------|
| `PROFILE_ID` | ✓ | ✓ | 线路唯一 ID |
| `ROLE` | `nat-transit` | `nat-ingress` | 机器角色 |
| `NAT_DIRECTION` | `nat-listener` | `nat-listener` | 正式流程 |
| `ET_NETWORK_NAME/SECRET` | ✓ | ✓ | EasyTier 组网 |
| `NAT_PUBLIC_HOST/PORT` | ✓ | ✓ | 商家 NAT 入口 |
| `TRANSIT_PORT` | ✓ | ✓ | 虚拟网中转端口 |
| `LANDING_HOST/PORT` | ✓ | ✓ | 落地业务 |
| `LOCAL_PORT` | — | ✓ | 客户端入口端口 |
| `rules/` 目录 | ✓ | ✓ | 多规则（code_schema=4） |

---

## 4. API 设计（v2）

### 4.1 移除的旧 API（/api/v1）

| 路由 | 原因 |
|------|------|
| `/network-links/*` | 替换为 profiles |
| `/network-profiles/*` | 合并到 profiles |
| `/forwards/*` | 替换为 rules |
| `/pbr-policies/*` | ix 不支持 |
| `/entries/*` | 合并到 profiles |

### 4.2 新增 API（/api/v2）

#### 机器管理

```
GET    /api/v2/machines              # 列出已注册机器
POST   /api/v2/machines              # 注册机器（生成 Agent Token）
GET    /api/v2/machines/:id          # 机器详情 + 健康状态
DELETE /api/v2/machines/:id          # 删除机器
POST   /api/v2/bootstrap/install     # 生成安装命令（含 ixtf + agent）
```

#### 线路 Profile

```
GET    /api/v2/profiles              # 列出所有线路（?role= / ?machine_id= / ?status=）
POST   /api/v2/profiles              # 创建线路（NAT IX / Ingress）
GET    /api/v2/profiles/:id          # 线路详情 + 规则 + 状态 + 端口地图摘要
PUT    /api/v2/profiles/:id          # 更新线路配置
DELETE /api/v2/profiles/:id          # 删除线路
POST   /api/v2/profiles/:id/enable   # 启用
POST   /api/v2/profiles/:id/disable  # 禁用
POST   /api/v2/profiles/:id/apply    # 应用配置到 Agent
POST   /api/v2/profiles/:id/sync     # 从 Agent 拉取本地 ixtf 状态（对账）
```

#### 转发规则

```
GET    /api/v2/profiles/:id/rules              # 列出规则（嵌套，主路径）
GET    /api/v2/rules?profile_id=               # 列出规则（扁平备选，跨线路查询）
POST   /api/v2/profiles/:id/rules              # 新增规则
PUT    /api/v2/profiles/:id/rules/:ruleId      # 编辑规则
DELETE /api/v2/profiles/:id/rules/:ruleId      # 删除规则
POST   /api/v2/profiles/:id/rules/:ruleId/enable
POST   /api/v2/profiles/:id/rules/:ruleId/disable
POST   /api/v2/profiles/:id/rules/apply        # 应用全部规则
POST   /api/v2/profiles/:id/rules/batch        # 批量启用/禁用/删除
```

#### 接入码

```
GET    /api/v2/profiles/:id/code               # 获取接入码（NAT IX，脱敏）
POST   /api/v2/profiles/:id/code/refresh       # 刷新接入码
POST   /api/v2/machines/:id/import-code        # 公网入口机导入接入码（绑定机器）
GET    /api/v2/profiles/:id/code/history       # 接入码刷新历史（审计）
```

#### 诊断与监控

```
POST   /api/v2/diagnostics/run              # 一键诊断
GET    /api/v2/diagnostics/:id              # 诊断报告
GET    /api/v2/profiles/:id/health          # 线路健康
GET    /api/v2/profiles/:id/port-map        # 端口地图
GET    /api/v2/profiles/:id/latency         # 延迟报告
GET    /api/v2/traffic                      # 流量统计
GET    /api/v2/ddns/status                  # DDNS 状态
POST   /api/v2/ddns/refresh                 # 手动刷新 DDNS
```

#### 任务（保留 + SSE）

```
GET    /api/v2/tasks
GET    /api/v2/tasks/:id
GET    /api/v2/tasks/:id/stream     # SSE 实时进度（替代轮询）
```

#### 保留的 v1 兼容

```
GET    /api/v1/health
POST   /api/v1/login
GET    /api/v1/agent/*                      # Agent 协议不变
```

---

## 5. Agent 任务设计

### 5.1 新增 readonlyActions

| Action | ix 命令 | 说明 |
|--------|---------|------|
| `ixtf_list_profiles` | `list-profiles` | 列出本地线路 |
| `ixtf_show_config` | `show-config` | 读取线路配置 |
| `ixtf_show_port_map` | `show-port-map --compact` | 端口地图 |
| `ixtf_health` | `health` | 健康检查 |
| `ixtf_diagnose` | `diagnose` | 诊断 |
| `ixtf_list_rules` | `list-rules` | 列出规则 |
| `ixtf_show_code` | `show-nat-code` | 读取接入码（脱敏） |
| `ixtf_ddns_status` | `ddns-status` | DDNS 状态 |
| `ixtf_traffic_report` | `traffic-report` | 流量统计 |
| `ixtf_latency_report` | `latency-report` | 延迟报告 |
| `ixtf_export_diagnostic` | `export-diagnostic` | 导出诊断 |

### 5.2 新增 writeActions

| Action | ix 命令 | 说明 |
|--------|---------|------|
| `ixtf_create_nat_profile` | `add-nat-listener-profile` | 创建 NAT IX 线路 |
| `ixtf_import_code` | `import-code` | 导入接入码 |
| `ixtf_add_rule` | `add-rule` | 新增转发规则 |
| `ixtf_edit_rule` | `edit-rule` | 编辑规则 |
| `ixtf_delete_rule` | `delete-rule` | 删除规则 |
| `ixtf_enable_rule` | `enable-rule` | 启用规则 |
| `ixtf_disable_rule` | `disable-rule` | 禁用规则 |
| `ixtf_apply_rules` | `apply-rules` | 应用规则 |
| `ixtf_refresh_code` | `refresh-code` | 刷新接入码 |
| `ixtf_enable_profile` | `enable-profile` | 启用线路 |
| `ixtf_disable_profile` | `disable-profile` | 禁用线路 |
| `ixtf_delete_profile` | `delete-profile` | 删除线路 |
| `ixtf_ddns_refresh` | `ddns-refresh` | 刷新 DDNS |
| `ixtf_install_ixtf` | `install-ix-cli` | 安装 ix CLI |

### 5.3 桥接层实现要点

```go
// panel/agent/internal/ixtf/bridge.go
type Bridge struct {
    InstallPath string // 默认 /opt/ix-transit-fabric/install.sh
}

func (b *Bridge) Run(ctx context.Context, subcommand string, args ...string) (string, error) {
    // 固定 argv: bash install.sh <subcommand> [args]
    // 禁止 shell 注入：args 白名单校验
    // stdout/stderr 截断 + 密钥脱敏
}
```

**安全约束**（继承现有模型）：
- 禁止 `command`/`shell`/`script` payload 键
- subcommand 必须在 allowlist 映射表内
- 接入码/密钥在 task result 中脱敏
- writeActions 需 `enable_write_actions=true`

---

## 6. UI 页面设计

### 6.1 新导航结构（v0.2 精简为 6 页）

| 页面 | 路由 Key | 功能 |
|------|----------|------|
| 概览 | `dashboard` | 线路数、健康状态、链路拓扑图、快捷入口 |
| 机器 | `machines` | NAT IX / 公网入口 机器管理 + 安装命令 + 导入接入码 |
| 线路 | `profiles` | 线路 CRUD + 详情 Tab（规则/接入码/端口地图） |
| 诊断 | `diagnostics` | 一键诊断 + 延迟/流量/DDNS |
| 任务 | `tasks` | 任务历史 + SSE 实时进度 |
| 设置 | `settings` | Token / API / 主题 |

**合并说明**:
- ~~转发规则~~ → 线路详情 Tab「规则」
- ~~接入码~~ → 线路详情 Drawer「接入码」
- ~~PBR / 旧组网 / 旧节点~~ → 删除

### 6.2 线路详情页 Tab 布局

```
┌─ 线路: 前海IX-A ──────────────────── [启用] [诊断] [刷新] ─┐
│  [概览]  [规则]  [接入码]  [端口地图]                          │
├──────────────────────────────────────────────────────────────┤
│  Tab: 概览                                                    │
│  ┌─ 链路拓扑 ─────────────────────────────────────────────┐  │
│  │ 客户端 → 公网入口:30000 → ET → NAT IX:40000 → 落地:50000 │  │
│  └────────────────────────────────────────────────────────┘  │
│  状态: healthy | 延迟: 42ms | 规则: 3 条启用                  │
├──────────────────────────────────────────────────────────────┤
│  Tab: 规则 → GlassTable CRUD + 批量操作                       │
│  Tab: 接入码 → 脱敏展示 + [复制完整码] + [刷新]                  │
│  Tab: 端口地图 → show-port-map 可视化                          │
└──────────────────────────────────────────────────────────────┘
```

### 6.3 Dashboard 布局

```
┌─────────────────────────────────────────────┐
│  [StatCard] 线路  [StatCard] 健康  [StatCard] 规则  [StatCard] 机器 │
├─────────────────────────────────────────────┤
│  快捷入口: 创建 NAT IX | 导入接入码 | 诊断 | 刷新    │
├──────────────────────┬──────────────────────┤
│  线路健康 (GlassTable) │  最近任务 (GlassTable)   │
└──────────────────────┴──────────────────────┘
```

### 6.4 创建 NAT IX 线路向导（Steps）

1. 选择目标机器（NAT IX 角色）
2. 填写商家 NAT 地址/端口
3. 填写落地机地址/端口
4. EasyTier 组网参数（网络名/密钥/CIDR/协议）
5. 预览 → 创建并应用
6. 展示接入码（一次性完整展示 + 脱敏历史）

### 6.5 导入接入码向导（公网入口 — 从机器页或线路页触发）

1. 选择目标机器（Ingress 角色）
2. 粘贴接入码 / 上传文件
3. 为每条规则指定客户端入口端口
4. 预览端口地图 → 导入并应用
5. 验证 health

---

## 7. 存储模型

### 7.1 Controller 存储

```json
{
  "machines": [{
    "id": "m-uuid",
    "name": "nat-ix-1",
    "role": "nat-transit",
    "token_hash": "...",
    "status": "online",
    "last_seen": "2026-06-09T..."
  }],
  "profiles": [{
    "id": "nat-ix-listener-1",
    "name": "前海IX线路A",
    "role": "nat-transit",
    "machine_id": "m-uuid",
    "enabled": true,
    "config": { "NAT_PUBLIC_HOST": "...", "LANDING_HOST": "..." },
    "rules": [{
      "id": "rule-main",
      "nat_public_port": 20000,
      "transit_port": 40000,
      "landing_host": "...",
      "landing_port": 50000,
      "local_port": 30000,
      "enabled": true,
      "remark": "游戏线路"
    }],
    "code_schema": 4,
    "status": "healthy"
  }],
  "tasks": []
}
```

### 7.2 Agent 本地存储

- 继续使用 ix-transit-fabric 的 `profiles/*.env` + `rules/` 目录
- Controller 为权威源，Agent 同步执行

---

## 8. 分阶段实施计划

### Phase 1 — Agent 桥接层（预估 5–7 天）

| # | 任务 | 产出 |
|---|------|------|
| 1.1 | 创建 `panel/agent/internal/ixtf/` 桥接包 | bridge.go + 测试 |
| 1.2 | 扩展 tasks.go allowlist（§5.1/5.2） | 新 action 注册 |
| 1.3 | Agent 安装脚本集成 ixtf | install-agent.sh 更新 |
| 1.4 | Controller v2 API 骨架 | profiles/machines CRUD |
| 1.5 | 集成测试：创建 NAT IX 线路 E2E | smoke test |

**验收标准**: Web/API 可创建 NAT IX 线路 → Agent 执行 → 返回 health=healthy

### Phase 2 — UI 重构（预估 5–7 天）

| # | 任务 | 产出 |
|---|------|------|
| 2.1 | 移除旧页面（PBR/旧组网/旧节点） | 代码清理 |
| 2.2 | 新页面：机器/线路/规则/接入码 | 8 页完成 |
| 2.3 | api.js 切换到 v2 | 前端 API 层 |
| 2.4 | 向导组件（CreateProfile/ImportCode） | 交互流程 |
| 2.5 | Dashboard 适配新数据模型 | 概览页 |

**验收标准**: 完整 NAT IX 流程可通过 Web UI 操作

### Phase 3 — 后端原生化（预估 10–20 天，渐进）

| # | 任务 | 说明 |
|---|------|------|
| 3.1 | Profile 配置渲染器（Go 替代 .env 写入） | 减少 bash 依赖 |
| 3.2 | nftables 模板引擎（Go） | 替代 install.sh nft 部分 |
| 3.3 | EasyTier 生命周期管理（Go） | 替代 install.sh ET 部分 |
| 3.4 | DDNS / 监控 / 流量统计 API 化 | 原生存储 |
| 3.5 | 主备切线（可选） | switch-line 集成 |

---

## 9. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| ix CLI 输出不稳定 | Agent 解析失败 | 结构化 JSON 输出模式（ixtf 新增 `--json` flag） |
| 16K 行 Bash 难以桥接 | 边界 case 遗漏 | Phase 1 严格 allowlist + 集成测试 |
| 接入码泄露 | 安全风险 | 一次性展示 + 脱敏 + 审计日志 |
| 旧 API  Breaking Change | 现有部署 | v1 保留 6 个月 deprecate 警告 |
| 双项目版本同步 | 功能漂移 | ixtf 版本 pin + Agent 兼容性检查 |

---

## 10. 待决策项

| # | 问题 | 选项 | 建议 |
|---|------|------|------|
| D1 | API 版本策略 | v2 新路由 vs 覆写 v1 | **v2 新路由** |
| D2 | ixtf 安装方式 | Agent 内置 vs 独立安装 | **Agent 安装脚本集成** |
| D3 | 结构化输出 | 要求 ixtf 加 `--json` | **Phase 1 先解析文本，Phase 1.5 加 JSON** |
| D4 | PBR 页面 | 删除 vs 隐藏 | **删除** |
| D5 | 项目名称 | 保持 Edge Tunnel Panel vs 改名 IX Transit Panel | **保持，副标题改** |

---

## 11. 文件变更清单（Phase 1+2）

### 新增

```
panel/agent/internal/ixtf/bridge.go
panel/agent/internal/ixtf/bridge_test.go
panel/controller/internal/ixtf/handlers.go
panel/controller/internal/ixtf/store.go
panel/controller/internal/ixtf/models.go
panel/controller/web/src/pages/Machines.jsx
panel/controller/web/src/pages/Profiles.jsx
panel/controller/web/src/pages/Rules.jsx
panel/controller/web/src/pages/Codes.jsx
panel/controller/web/src/api/v2.js
docs/migration-ix-transit-fabric-design.md  (本文件)
```

### 修改

```
panel/agent/internal/agent/tasks.go          # 新 actions
panel/controller/internal/controller/server.go  # v2 路由
panel/controller/web/src/main.jsx            # 新 tab + v2 API
panel/controller/web/src/components/Sidebar.jsx  # 新导航
panel/scripts/install-agent.sh               # 集成 ixtf
```

### 删除（Phase 2）

```
panel/controller/web/src/pages/PBR.jsx
panel/controller/web/src/pages/NetworkLinks.jsx  → 合并到 Profiles
panel/controller/web/src/pages/Nodes.jsx           → 重命名为 Machines
panel/controller/web/src/pages/Forwards.jsx        → 合并到 Rules
panel/agent/internal/agent/forward*.go             # 旧转发逻辑
panel/controller/internal/controller/pbr*.go       # PBR 后端
```

---

## 12. 测试策略

| 层级 | 范围 |
|------|------|
| 单元测试 | ixtf bridge 解析、allowlist 校验、API handler |
| 集成测试 | Controller ↔ Agent 任务流 |
| E2E smoke | 创建 NAT IX → 生成码 → 导入 → health |
| UI 测试 | 向导流程手动验证清单 |

---

## 13. 评审检查清单

- [ ] API v2 路由设计是否覆盖全部 ix 核心命令？
- [ ] Agent allowlist 是否足够安全？
- [ ] UI 页面结构是否符合 NAT IX 正式流程？
- [ ] Phase 划分是否合理？是否需调整优先级？
- [ ] 旧功能移除时机：Phase 1 还是 Phase 2？
- [ ] 是否需要 ixtf 侧配合添加 `--json` 输出？

---

*文档结束 — 请评审后确认 Phase 1 启动。*
