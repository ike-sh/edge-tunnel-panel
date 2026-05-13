package controller

func payloadHasDangerousKeys(payload map[string]any) bool {
	for _, key := range []string{"command", "cmd", "shell", "script", "raw_" + "nft", "raw_" + "iptables", "raw_" + "ip_route"} {
		if _, ok := payload[key]; ok {
			return true
		}
	}
	return false
}
