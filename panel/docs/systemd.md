# systemd

## 主控服务

```bash
sudo systemctl status edge-tunnel-controller.service
sudo journalctl -u edge-tunnel-controller.service -f
sudo systemctl restart edge-tunnel-controller.service
```

## Agent 服务

```bash
sudo systemctl status edge-tunnel-agent.service
sudo journalctl -u edge-tunnel-agent.service -f
sudo systemctl restart edge-tunnel-agent.service
```

## EasyTier 服务

```bash
sudo systemctl status edge-tunnel-easytier.service
sudo journalctl -u edge-tunnel-easytier.service -f
sudo systemctl restart edge-tunnel-easytier.service
```

EasyTier 配置默认在 `/etc/edge-tunnel/agent/easytier.toml`。

Agent 应用组网配置时会写入：

- `/etc/edge-tunnel/agent/easytier.toml`
- `/etc/edge-tunnel/agent/systemd/edge-tunnel-easytier.service`
- `/etc/systemd/system/edge-tunnel-easytier.service`

随后使用固定参数执行：

```bash
systemctl daemon-reload
systemctl enable edge-tunnel-easytier.service
systemctl restart edge-tunnel-easytier.service
systemctl is-active edge-tunnel-easytier.service
```

## EasyTier ????

`edge-tunnel-easytier.service` ? `ExecStart` ?? `easytier-core` CLI ?????`--network-name`?`--network-secret`??? `-l` listeners????? `-p` peers?`/etc/edge-tunnel/agent/easytier.toml` ?????????????????
