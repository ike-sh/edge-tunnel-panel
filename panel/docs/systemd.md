# systemd 与清理

服务：

- `edge-tunnel-controller.service`
- `edge-tunnel-agent.service`
- `edge-tunnel-easytier.service`

常用命令：

```bash
systemctl status edge-tunnel-agent --no-pager
journalctl -u edge-tunnel-agent -n 100 --no-pager
systemctl status edge-tunnel-easytier --no-pager
journalctl -u edge-tunnel-easytier -n 100 --no-pager
```

节点删除支持：仅删除记录、远程清理部署内容、清理并卸载 Agent。离线节点无法远程清理。
