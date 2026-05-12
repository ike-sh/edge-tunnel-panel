# DDNS

DDNS 不是一级主流程，而是节点或公网入口的内置能力。

## 当前能力

测试版主要完成配置落地和安全 redaction，provider 同步逻辑后续增强。

## 配置路径

Agent 写入：

- `/etc/edge-tunnel/agent/ddns.json`

Token 建议使用引用方式保存，任务输出会隐藏敏感值。
