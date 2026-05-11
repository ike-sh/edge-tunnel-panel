# Topology 只读拓扑

Leikwan Panel 2.0.0-beta.2 保留只读拓扑视图。Plans 虽然可以生成命令和人工执行手册，但 Topology 本身不执行任何变更。

## API

```bash
curl http://127.0.0.1:18080/api/v1/topology
```

返回：

```json
{
  "nodes": [],
  "entries": [],
  "forwards": [],
  "links": []
}
```

## 推断规则

alpha.3 不读取远端系统，也不修改任何配置。拓扑只基于 Agent 上报做轻量推断：

- `entry -> relay`
- `relay -> target`

如果无法推断，API 仍返回 nodes、entries、forwards，`links` 可以为空。

## 前端

前端 `/topology` 页面展示：

- Entry 节点
- Relay 节点
- Backend / unknown 节点
- entries 数量
- forwards 数量
- online / degraded / offline 状态

该页面没有写操作。按钮中的 `Coming in 2.1` 只是占位，不会触发配置变更。

## 安全边界

Topology 不做：

- 入口切换
- 转发新增 / 删除 / 修改
- relay restart
- 配置下发
- 任意命令执行

2.1 之后如考虑白名单任务，也必须先设计权限、审计和可回滚流程。
