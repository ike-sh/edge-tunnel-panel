# systemd

## Controller

服务：

```text
edge-tunnel-controller.service
```

默认路径：

```text
/etc/edge-tunnel/controller/controller.env
/var/lib/edge-tunnel/controller
/var/lib/edge-tunnel/controller/web
/usr/local/bin/edge-tunnel-controller
```

常用命令：

```bash
systemctl status edge-tunnel-controller --no-pager
journalctl -u edge-tunnel-controller -n 100 --no-pager
```

## Agent

服务：

```text
edge-tunnel-agent.service
```

默认路径：

```text
/etc/edge-tunnel/agent/agent.env
/etc/edge-tunnel/agent
/var/lib/edge-tunnel/agent
/usr/local/bin/edge-tunnel-agent
```

## EasyTier

Agent 管理的 EasyTier 服务：

```text
edge-tunnel-easytier.service
```

配置路径：

```text
/etc/edge-tunnel/agent/easytier.toml
/etc/systemd/system/edge-tunnel-easytier.service
```

常用命令：

```bash
systemctl status edge-tunnel-easytier --no-pager
journalctl -u edge-tunnel-easytier -n 100 --no-pager
easytier-cli peer
easytier-cli route
```

Agent purge 会清理 EasyTier service/config。如果需要删除 `easytier-core` 和 `easytier-cli`，额外使用：

```bash
panel/scripts/install-agent.sh --purge --remove-easytier-binaries
```
