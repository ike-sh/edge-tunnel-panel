#!/usr/bin/env node
/**
 * Mock Agent — polls controller tasks and submits synthetic ix results for E2E.
 * Usage:
 *   CONTROLLER_URL=http://127.0.0.1:18080 AGENT_TOKEN=edge-agent-token MACHINE_ID=<id> node mock-agent.mjs
 */
const BASE = (process.env.CONTROLLER_URL || 'http://127.0.0.1:18080').replace(/\/+$/, '');
const TOKEN = process.env.AGENT_TOKEN || 'edge-agent-token';
const MACHINE_ID = process.env.MACHINE_ID || '';
const NODE_ID = process.env.NODE_ID || `mock-${Date.now().toString(36)}`;
const NODE_NAME = process.env.NODE_NAME || 'mock-agent-1';
const POLL_MS = Number(process.env.POLL_MS || 2000);

const headers = {
  Authorization: `Bearer ${TOKEN}`,
  'Content-Type': 'application/json',
  Accept: 'application/json',
};

async function api(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || json.ok === false) {
    throw new Error(json.error?.message || `${res.status} ${path}`);
  }
  return json.data ?? json;
}

function mockResult(action, payload) {
  const profileID = payload?.profile_id || 'profile-1';
  switch (action) {
    case 'ix_read_health':
      return { status: 'succeeded', result: JSON.stringify({ stdout: 'HEALTH_STATUS=healthy\n' }) };
    case 'ix_read_diagnose':
      return { status: 'succeeded', result: JSON.stringify({ stdout: 'DIAG_OK=1\nlatency_ms=42\n' }) };
    case 'ix_read_show_config':
      return { status: 'succeeded', stdout: JSON.stringify({ config: { LANDING_HOST: '1.2.3.4', TRANSIT_PORT: 40000 } }) };
    case 'ix_read_port_map':
      return { status: 'succeeded', stdout: '40000 -> 50000/tcp\n' };
    case 'ix_read_list_rules':
      return { status: 'succeeded', stdout: JSON.stringify([{ id: 'rule-main', transit_port: 40000, landing_host: '1.2.3.4', landing_port: 50000, enabled: true }]) };
    case 'ix_read_show_code':
    case 'ix_write_refresh_code':
      return { status: 'succeeded', stdout: 'IXTF1:[REDACTED]\nprofile=' + profileID + '\n' };
    case 'ix_write_create_nat':
    case 'ix_write_apply_rules':
    case 'ix_write_import_code':
    case 'ix_write_enable_profile':
    case 'ix_write_disable_profile':
      return { status: 'succeeded', result: JSON.stringify({ native: true, mock: true }) };
    default:
      return { status: 'succeeded', result: '{}' };
  }
}

async function register() {
  await api('POST', '/api/v1/agent/register', {
    id: NODE_ID,
    name: NODE_NAME,
    role: 'backend',
    hostname: NODE_NAME,
    machine_id: MACHINE_ID,
  });
  await api('POST', '/api/v1/agent/report', {
    id: NODE_ID,
    name: NODE_NAME,
    role: 'backend',
    agent_version: 'mock-1',
    hostname: NODE_NAME,
    os: 'linux',
    arch: 'amd64',
    machine_id: MACHINE_ID,
    capabilities: { supports_task_polling: true },
    easytier_status: 'unknown',
  });
  console.log(`[mock-agent] registered node=${NODE_ID} machine=${MACHINE_ID || '(none)'}`);
}

async function pollOnce() {
  const tasks = await api('GET', `/api/v1/agent/tasks?node_id=${encodeURIComponent(NODE_ID)}`);
  if (!Array.isArray(tasks) || tasks.length === 0) return 0;
  let done = 0;
  for (const task of tasks) {
    if (!['pending', 'running'].includes(task.status)) continue;
    const body = mockResult(task.action, task.payload);
    await api('POST', `/api/v1/agent/tasks/${encodeURIComponent(task.id)}/result`, body);
    console.log(`[mock-agent] completed ${task.action} (${task.id})`);
    done += 1;
  }
  return done;
}

async function main() {
  await register();
  for (;;) {
    try {
      const n = await pollOnce();
      if (n > 0) console.log(`[mock-agent] processed ${n} task(s)`);
    } catch (e) {
      console.error('[mock-agent] error:', e.message);
    }
    await new Promise((r) => setTimeout(r, POLL_MS));
  }
}

main();
