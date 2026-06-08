export function buildProfileAddressLines(profile, machine, node) {
  const cfg = profile?.config || {};
  const host = node?.public_ip || node?.observed_ip || node?.hostname || machine?.name || '—';
  const lines = [];
  const seen = new Set();

  function add(label, port) {
    const p = Number(port);
    if (!p) return;
    const line = `${label}: ${host}:${p}`;
    if (seen.has(line)) return;
    seen.add(line);
    lines.push(line);
  }

  add('客户端入口', cfg.LOCAL_PORT);
  add('NAT 中转', cfg.TRANSIT_PORT || cfg.NAT_PUBLIC_PORT);

  (profile?.rules || []).forEach((rule) => {
    add('客户端入口', rule.local_port);
    add('商家 NAT', rule.nat_public_port);
    add('中转端口', rule.transit_port);
  });

  return lines;
}

export function buildProfileAddressBlock(profile, machine, node) {
  const lines = buildProfileAddressLines(profile, machine, node);
  if (!lines.length) return '';
  return lines.join('\n');
}
