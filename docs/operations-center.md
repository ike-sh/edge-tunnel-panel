# 运维命令中心

Leikwan Toolkit 1.3.0 新增“运维命令中心”，用于把日常维护入口集中到一个菜单，减少在多个子菜单之间来回查找。

## 入口

交互菜单中选择：

```text
运维命令中心
```

菜单包含：

```text
1. 查看状态总览
2. 一键诊断
3. 自动修复常见问题
4. 重新应用转发规则
5. 检查端口冲突
6. 生成端点输出
7. 配置导出 / 导入
8. DDNS 自动刷新
9. 自更新
0. 返回
```

## 行为

运维中心不新增重复实现，只复用已有能力：

- `lq status`
- `lq --doctor`
- `lq port check`
- `lq output generate`
- `lq config export/import/inspect/list`
- `lq ddns status/run/enable/disable/logs`
- `lq update check/run/status/rollback`
- `lq forward apply-relay --auto-fix-route`

只读动作不会修改系统。高危动作继续沿用原有确认、自动快照、锁和后台执行策略。

## 适用场景

- 日常巡检：先看状态总览，再按需运行 doctor。
- 变更后确认：重新应用转发规则后执行端口预检和状态总览。
- 迁移前后：从运维中心进入配置导出 / 导入，再执行状态总览。
- DDNS 排查：查看 timer 状态、刷新日志和最近运行结果。

