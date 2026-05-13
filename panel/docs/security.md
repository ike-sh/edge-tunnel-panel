# 瀹夊叏璇存槑

## Token

- Web/API 浣跨敤 Operator Token锛涙祴璇曟ā寮忓彲鍏抽棴涓ユ牸閴存潈銆?- Agent 浣跨敤 Controller Token 娉ㄥ唽銆佷笂鎶ュ拰杞浠诲姟銆?- 鏃ュ織銆佷换鍔¤緭鍑哄拰閿欒淇℃伅浼氬仛 redaction銆?
## Agent action allowlist

Agent 鍙墽琛屽浐瀹?action锛屼緥濡傦細

- `collect_agent_status`
- `run_node_preflight`
- `verify_easytier_status`
- `verify_network_connectivity`
- `apply_network_profile`
- `install_or_update_easytier`
- `apply_forward_config`
- `verify_forward_rules`

## 绂佹 payload

Controller 鍜?Agent 浼氭嫆缁濆嵄闄╁瓧娈碉細

- `command`
- `cmd`
- `shell`
- `script`
- `raw_nft`
- `raw_iptables`
- `raw_ip_route`

## Root 鏉冮檺

Agent 闇€瑕?root 鏉冮檺鏉ュ啓 systemd銆乶ftables 鍜?EasyTier 閰嶇疆銆傚啓鍏ュ姩浣滃簲鍙湪鍙俊鑺傜偣寮€鍚€?
