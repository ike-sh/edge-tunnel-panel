export function buildRulesExport(profile) {
  const rules = (profile?.rules || []).map((rule) => ({
    id: rule.id || rule.rule_id,
    nat_public_port: rule.nat_public_port || 0,
    transit_port: rule.transit_port || 0,
    local_port: rule.local_port || 0,
    landing_host: rule.landing_host || '',
    landing_port: rule.landing_port || 0,
    remark: rule.remark || '',
    enabled: rule.enabled !== false,
  }));
  return JSON.stringify({
    version: 1,
    profile_id: profile.id,
    profile_name: profile.name,
    exported_at: new Date().toISOString(),
    rules,
  }, null, 2);
}

export function parseRulesImport(raw, profileId) {
  const text = String(raw || '').trim();
  if (!text) throw new Error('导入内容为空');
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error('JSON 格式无效');
  }
  const list = Array.isArray(data) ? data : data.rules;
  if (!Array.isArray(list) || !list.length) {
    throw new Error('未找到 rules 数组');
  }
  return list.map((rule, index) => ({
    id: rule.id || rule.rule_id || `rule-import-${Date.now()}-${index}`,
    profile_id: profileId,
    nat_public_port: Number(rule.nat_public_port) || 0,
    transit_port: Number(rule.transit_port) || 0,
    local_port: Number(rule.local_port) || 0,
    landing_host: String(rule.landing_host || '').trim(),
    landing_port: Number(rule.landing_port) || 0,
    remark: String(rule.remark || '').trim(),
    enabled: rule.enabled !== false,
  })).filter((rule) => rule.landing_host);
}
