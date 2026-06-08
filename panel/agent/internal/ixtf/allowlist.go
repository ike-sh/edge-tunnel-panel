package ixtf

// readonlySubcommands are safe read-only ix install.sh subcommands.
var readonlySubcommands = map[string]bool{
	"list-profiles":       true,
	"show-config":         true,
	"show-port-map":       true,
	"show-port-map-compact": true,
	"health":              true,
	"diagnose":            true,
	"list-rules":          true,
	"show-nat-code":       true,
	"show-code":           true,
	"ddns-status":         true,
	"traffic-report":      true,
	"latency-report":      true,
	"export-diagnostic":   true,
	"status-all":          true,
	"show-profile":        true,
}

// writeSubcommands mutate local ixtf state.
var writeSubcommands = map[string]bool{
	"add-nat-listener-profile":      true,
	"import-code":                   true,
	"add-rule":                      true,
	"edit-rule":                     true,
	"delete-rule":                   true,
	"enable-rule":                   true,
	"disable-rule":                  true,
	"apply-rules":                   true,
	"refresh-code":                  true,
	"refresh-nat-code":              true,
	"enable-profile":                true,
	"disable-profile":               true,
	"delete-profile":                true,
	"ddns-refresh":                  true,
	"install-ix-cli":                true,
	"add-nat-ingress-from-listener-code": true,
}

func AllowedSubcommand(name string) bool {
	return readonlySubcommands[name] || writeSubcommands[name]
}

func IsWriteSubcommand(name string) bool {
	return writeSubcommands[name]
}

func IsReadSubcommand(name string) bool {
	return readonlySubcommands[name]
}

// ActionToSubcommand maps agent task actions to ix subcommands.
var ActionToSubcommand = map[string]string{
	"ix_read_list_profiles":    "list-profiles",
	"ix_read_show_config":      "show-config",
	"ix_read_port_map":         "show-port-map",
	"ix_read_health":           "health",
	"ix_read_diagnose":         "diagnose",
	"ix_read_list_rules":       "list-rules",
	"ix_read_show_code":        "show-nat-code",
	"ix_read_ddns_status":      "ddns-status",
	"ix_read_traffic":          "traffic-report",
	"ix_read_latency":          "latency-report",
	"ix_read_export_diagnostic": "export-diagnostic",
	"ix_write_create_nat":      "add-nat-listener-profile",
	"ix_write_import_code":     "import-code",
	"ix_write_add_rule":        "add-rule",
	"ix_write_edit_rule":       "edit-rule",
	"ix_write_delete_rule":     "delete-rule",
	"ix_write_enable_rule":     "enable-rule",
	"ix_write_disable_rule":    "disable-rule",
	"ix_write_apply_rules":     "apply-rules",
	"ix_write_refresh_code":    "refresh-code",
	"ix_write_enable_profile":  "enable-profile",
	"ix_write_disable_profile": "disable-profile",
	"ix_write_delete_profile":  "delete-profile",
	"ix_write_ddns_refresh":    "ddns-refresh",
	"ix_write_install_cli":     "install-ix-cli",
}

func SubcommandForAction(action string) (string, bool) {
	sub, ok := ActionToSubcommand[action]
	return sub, ok
}

func IsReadAction(action string) bool {
	sub, ok := ActionToSubcommand[action]
	return ok && IsReadSubcommand(sub)
}

func IsWriteAction(action string) bool {
	sub, ok := ActionToSubcommand[action]
	return ok && IsWriteSubcommand(sub)
}
