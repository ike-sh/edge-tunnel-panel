# systemd

## Controller

```bash
systemctl status edge-tunnel-controller --no-pager
journalctl -u edge-tunnel-controller -n 100 --no-pager
```

默认路径：

- 二进制：`/usr/local/bin/edge-tunnel-controller`
- 环境文件：`/etc/edge-tunnel/controller/controller.env`
- 数据目录：`/var/lib/edge-tunnel/controller`
- Web 目录：`/var/lib/edge-tunnel/controller/web`

## Agent

```bash
systemctl status edge-tunnel-agent --no-pager
journalctl -u edge-tunnel-agent -n 100 --no-pager
```

默认路径：

- 二进制：`/usr/local/bin/edge-tunnel-agent`
- 环境文件：`/etc/edge-tunnel/agent/agent.env`
- 配置目录：`/etc/edge-tunnel/agent`
- 状态目录：`/var/lib/edge-tunnel/agent`

## EasyTier

Agent 管理的 EasyTier service：

```bash
systemctl status edge-tunnel-easytier --no-pager
journalctl -u edge-tunnel-easytier -n 100 --no-pager
easytier-cli peer
easytier-cli route
```

配置文件：

- `/etc/edge-tunnel/agent/easytier.toml`
- `/etc/systemd/system/edge-tunnel-easytier.service`

Agent purge 会清理 EasyTier service/config；如需删除 `easytier-core` 和 `easytier-cli`，额外使用 `--remove-easytier-binaries`。
