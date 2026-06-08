export const DEFAULT_VERSION = 'v0.3.1-test';

export const tabs = [
  ['dashboard', '总览'],
  ['machines', '机器'],
  ['profiles', '线路'],
  ['diagnostics', '诊断'],
  ['tasks', '任务'],
  ['settings', '设置'],
];

export const ixActions = [
  'ix_read_list_profiles', 'ix_read_show_config', 'ix_read_port_map', 'ix_read_health',
  'ix_read_diagnose', 'ix_read_list_rules', 'ix_read_show_code', 'ix_write_create_nat',
  'ix_write_apply_rules', 'ix_write_import_code', 'ix_write_refresh_code',
];

/** @deprecated v1 tabs — kept for reference during migration */
export const legacyTabs = [
  ['nodes', '节点'],
  ['networks', '组网链路'],
  ['forwards', '转发规则'],
  ['pbr', '出口策略 / PBR'],
];

export const readActions = [
  'run_node_preflight',
  'collect_agent_status',
  'verify_agent_config',
  'verify_easytier_status',
  'verify_network_connectivity',
  'verify_forward_rules',
  'verify_pbr_rules',
  'detect_network_interfaces',
  'detect_pbr_route_groups',
  'detect_mtu_status',
  'verify_ddns_status',
];

export const writeActions = ['install_or_update_easytier', 'restart_easytier', 'restart_agent'];
export const easyTierActions = ['install_or_update_easytier', 'apply_network_profile', 'verify_easytier_status', 'verify_network_connectivity', 'restart_easytier', 'detect_mtu_status'];
export const forwardingActions = ['apply_forward_config', 'apply_entry_forward_config', 'apply_landing_forward_config', 'verify_forward_rules', 'verify_entry_forward_rules', 'verify_landing_forward_rules'];
export const pbrActions = ['detect_network_interfaces', 'detect_pbr_route_groups', 'apply_pbr_policy', 'verify_pbr_policy', 'disable_pbr_policy', 'verify_pbr_rules'];

export const actionLabels = {
  run_node_preflight: '节点预检',
  collect_agent_status: '状态检查',
  verify_agent_config: '验证 Agent 配置',
  verify_easytier_status: '验证 EasyTier 状态',
  verify_network_connectivity: '验证组网',
  verify_direct_link: '验证直连链路',
  verify_forward_rules: '验证转发规则',
  verify_pbr_rules: '验证出口策略',
  detect_network_interfaces: '识别网卡',
  detect_pbr_route_groups: '识别出口线路',
  detect_mtu_status: '检测 MTU/MSS',
  verify_ddns_status: '验证 DDNS',
  install_or_update_easytier: '安装/更新 EasyTier',
  apply_network_profile: '应用组网配置',
  apply_entry_config: '应用公网入口',
  apply_forward_config: '应用转发规则',
  apply_entry_forward_config: '应用入口转发',
  apply_landing_forward_config: '应用落地转发',
  disable_entry_forward_config: '停用入口转发',
  disable_landing_forward_config: '停用落地转发',
  disable_network_link: '停用组网链路',
  cleanup_node_deployment: '清理节点部署',
  purge_agent_deployment: '清理并卸载 Agent',
  apply_pbr_config: '应用出口策略',
  apply_pbr_policy: '应用出口策略',
  verify_pbr_policy: '验证出口策略',
  disable_pbr_policy: '禁用出口策略',
  apply_ddns_config: '应用 DDNS',
  reload_firewall_rules: '重载防火墙规则',
  restart_easytier: '重启 EasyTier',
  restart_agent: '重启 Agent',
  reboot_node: '重启服务器',
};

export const statusLabels = {
  online: '在线',
  stale: '可能离线',
  offline: '离线',
  pending: '等待中',
  running: '执行中',
  succeeded: '成功',
  failed: '失败',
  expired: '已过期',
  cancelled: '已取消',
  active: '运行中',
  inactive: '未运行',
  missing_binary: '未安装',
  missing_config: '缺少配置',
  service_missing: '服务缺失',
  connected: '组网成功',
  partial: '部分异常',
  waiting: '等待验证',
  applying: '应用中',
  verifying: '验证中',
  disabled: '已禁用',
  draft: '草稿',
  applied: '已应用',
  verified: '已验证',
};

export function safeList(value) {
  return Array.isArray(value) ? value : [];
}

export function shortID(value, size = 12) {
  const text = String(value || '');
  return text ? text.slice(0, size) : '-';
}

export function labelStatus(value) {
  return statusLabels[value] || value || '-';
}

export function statusClass(value) {
  return `badge ${value || 'unknown'}`;
}

export function actionLabel(action) {
  return actionLabels[action] || action || '-';
}

export function lines(value) {
  return String(value || '').split(/\r?\n/).map((item) => item.trim()).filter(Boolean);
}

export function formatTime(value) {
  if (!value) return '-';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '-' : date.toLocaleString();
}

export function timeAgo(value) {
  if (!value) return '-';
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000));
  if (!Number.isFinite(seconds)) return '-';
  if (seconds < 60) return `${seconds} 秒前`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} 小时前`;
  return `${Math.floor(hours / 24)} 天前`;
}

export function pretty(value) {
  if (value === undefined || value === null || value === '') return '-';
  if (typeof value !== 'string') return JSON.stringify(value, null, 2);
  try {
    return JSON.stringify(JSON.parse(value), null, 2);
  } catch {
    return value;
  }
}

export function parseJSON(value) {
  try {
    return typeof value === 'string' ? JSON.parse(value) : (value || {});
  } catch {
    return {};
  }
}

export function nodeLabel(node) {
  return node ? `${node.name || node.id || '-'} / ${shortID(node.id)}` : '-';
}

export function nodeOptionLabel(node) {
  return node ? `${node.name || node.id} / ${node.public_ip || node.observed_ip || '-'} / ${labelStatus(node.easytier_status)}` : '-';
}

export function networkStatusText(node) {
  if (node?.easytier_network_ok) return '组网成功';
  if (Number(node?.easytier_peer_count || 0) > 0) return 'Peer 已连接';
  if (node?.easytier_status === 'active') return '未发现 Peer';
  return labelStatus(node?.easytier_status);
}

export function linkStatusText(link) {
  if (link?.link_type === 'direct' && link?.status === 'active') return '直连可用';
  if (link?.status === 'active' || link?.status === 'connected') return '组网成功';
  if (link?.status === 'applying') return '应用中';
  if (link?.status === 'verifying') return '验证中';
  if (link?.status === 'failed') return '组网失败';
  if (link?.status === 'disabled') return '已禁用';
  if (link?.status === 'partial') return '部分异常';
  return '等待验证';
}

export function cleanLoss(value) {
  const text = String(value || '').trim();
  return /^\d+(?:\.\d+)?%$/.test(text) ? text : '-';
}

export function cleanTunnels(value) {
  const list = safeList(value)
    .flatMap((item) => String(item || '').split(','))
    .map((item) => item.trim())
    .filter((item) => /^(tcp|udp|tcp6|udp6|wg|ws|wss)$/i.test(item) || item.includes('://'));
  return [...new Set(list)];
}

export function displayTunnels(value) {
  const list = cleanTunnels(value);
  return list.length ? list.join(',') : '-';
}

export function displayLatency(value) {
  const n = Number(value || 0);
  return n > 0 ? `${n} ms` : '-';
}

export function displayRoute(value, networkOK = false) {
  const text = String(value || '').trim();
  if (!text || text === 'unknown') return networkOK ? '待识别' : '-';
  return text;
}

export function linkNodeNames(link, nodeMap) {
  const entry = nodeMap[link?.entry_node_id];
  const backend = nodeMap[link?.backend_node_id];
  return `${entry?.name || link?.entry_node_id || '-'} → ${backend?.name || link?.backend_node_id || '-'}`;
}

export function linkOptionLabel(link, nodeMap) {
  return `${link.name || link.network_name || 'edge-net'}：${linkNodeNames(link, nodeMap)}，${linkStatusText(link)}，延迟 ${displayLatency(link.best_latency_ms)}`;
}

export function transportModeLabel(value) {
  if (value === 'direct') return '直连链路';
  return value === 'public' ? 'B 公网直连' : 'EasyTier 隧道';
}

export function publicIP(node) {
  return node?.public_ip || node?.observed_ip || '-';
}

export function landingHost(rule) {
  return rule?.landing_host_raw || rule?.landing_host || rule?.landing_host_resolved || '-';
}

export function ruleListenPort(rule) {
  return rule?.public_listen_port || rule?.listen_port || '-';
}

export function ruleLandingPort(rule) {
  return rule?.landing_port || rule?.target_port || '-';
}

export function randomSecret() {
  const bytes = new Uint8Array(18);
  if (window.crypto?.getRandomValues) {
    window.crypto.getRandomValues(bytes);
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  }
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}
