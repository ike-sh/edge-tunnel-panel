# 拓扑视图

Leikwan Panel `3.0.0-alpha.4` 保留拓扑视图，用于展示 Entry、Relay、Forward 和 target 的关系。

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

拓扑基于 Controller 中的节点、Entry 和 Forward 数据轻量推断：

- entry -> relay
- relay -> target

如果信息不足，API 仍返回 nodes / entries / forwards，links 可以为空。

## 安全边界

Topology 页面不执行：

- 入口切换
- 转发新增 / 删除 / 修改
- relay restart
- 配置下发
- 任意命令