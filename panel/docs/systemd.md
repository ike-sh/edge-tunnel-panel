# Leikwan Panel systemd ç¤ºä¾‹

±¾Ò³Ìá¹© Leikwan Panel 2.1.0-alpha.1 µÄ systemd ²İ°¸¡£2.1-alpha.1 ²»»á×Ô¶¯Ö´ĞĞÅäÖÃ±ä¸ü£¬²»»áĞŞ¸Ä Leikwan Core µÄ nftables¡¢systemd¡¢EasyTier¡¢DDNS »ò TSV ÅäÖÃ¡£
## Controller é…ç½®è·¯å¾„

å»ºè®®è·¯å¾„ï¼?
```text
/usr/local/bin/leikwan-controller
/var/lib/leikwan-panel/controller.db
/etc/leikwan-panel/controller.yml
```

`controller.yml` ç¤ºä¾‹ï¼?
```yaml
token: change-me
```

ä¹Ÿå¯ä»¥ä½¿ç”¨ç¯å¢ƒå˜é‡ï¼š

```text
LEIKWAN_CONTROLLER_TOKEN=change-me
```

## leikwan-controller.service

ç¤ºä¾‹æ–‡ä»¶è§ï¼š

```text
panel/examples/leikwan-controller.service
```

å†…å®¹ï¼?
```ini
[Unit]
Description=Leikwan Panel Controller
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/leikwan-panel/controller.env
ExecStart=/usr/local/bin/leikwan-controller --listen 0.0.0.0:18080 --db /var/lib/leikwan-panel/controller.db
Restart=on-failure
RestartSec=5s
User=root

[Install]
WantedBy=multi-user.target
```

## Agent é…ç½®è·¯å¾„

å»ºè®®è·¯å¾„ï¼?
```text
/usr/local/bin/leikwan-agent
/etc/leikwan-agent/config.yml
```

`config.yml` ç¤ºä¾‹è§ï¼š

```text
panel/examples/agent.yml
```

## leikwan-agent.service

ç¤ºä¾‹æ–‡ä»¶è§ï¼š

```text
panel/examples/leikwan-agent.service
```

å†…å®¹ï¼?
```ini
[Unit]
Description=Leikwan Panel Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/leikwan-agent --config /etc/leikwan-agent/config.yml
Restart=on-failure
RestartSec=5s
User=root

[Install]
WantedBy=multi-user.target
```

## å¯ç”¨æœåŠ¡

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now leikwan-controller.service
sudo systemctl enable --now leikwan-agent.service
```

## æŸ¥çœ‹æ—¥å¿—

```bash
journalctl -u leikwan-controller.service -n 100 --no-pager
journalctl -u leikwan-agent.service -n 100 --no-pager
```

æ—¥å¿—ä¸­ä¸åº”å‡ºç?tokenã€secretã€passwordã€privateKeyã€custom_urlã€custom_cmd æˆ?Authorization æ˜æ–‡ã€?
