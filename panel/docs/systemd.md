# systemd

## Controller

```bash
systemctl status edge-tunnel-controller --no-pager
journalctl -u edge-tunnel-controller -n 100 --no-pager
```

榛樿璺緞锛?
- 浜岃繘鍒讹細`/usr/local/bin/edge-tunnel-controller`
- 鐜鏂囦欢锛歚/etc/edge-tunnel/controller/controller.env`
- 鏁版嵁鐩綍锛歚/var/lib/edge-tunnel/controller`
- Web 鐩綍锛歚/var/lib/edge-tunnel/controller/web`

## Agent

```bash
systemctl status edge-tunnel-agent --no-pager
journalctl -u edge-tunnel-agent -n 100 --no-pager
```

榛樿璺緞锛?
- 浜岃繘鍒讹細`/usr/local/bin/edge-tunnel-agent`
- 鐜鏂囦欢锛歚/etc/edge-tunnel/agent/agent.env`
- 閰嶇疆鐩綍锛歚/etc/edge-tunnel/agent`
- 鐘舵€佺洰褰曪細`/var/lib/edge-tunnel/agent`

## EasyTier

Agent 绠＄悊鐨?EasyTier service锛?
```bash
systemctl status edge-tunnel-easytier --no-pager
journalctl -u edge-tunnel-easytier -n 100 --no-pager
easytier-cli peer
easytier-cli route
```

閰嶇疆鏂囦欢锛?
- `/etc/edge-tunnel/agent/easytier.toml`
- `/etc/systemd/system/edge-tunnel-easytier.service`

Agent purge 浼氭竻鐞?EasyTier service/config锛涘闇€鍒犻櫎 `easytier-core` 鍜?`easytier-cli`锛岄澶栦娇鐢?`--remove-easytier-binaries`銆?
