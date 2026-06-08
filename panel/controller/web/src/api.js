import { notifyUnauthorized } from './utils/auth.js';

export const TOKEN_KEY = 'edgeTunnelOperatorToken';
export const API_BASE_KEY = 'edgeTunnelApiBase';

export function normalizeBase(value) {
  return String(value || '').trim().replace(/\/+$/, '');
}

function handleResponseStatus(response, payload) {
  if (response.status === 401) {
    notifyUnauthorized();
    throw new Error(payload?.error?.message || '未授权，请重新登录');
  }
  if (!response.ok || payload?.ok === false) {
    throw new Error(payload?.error?.message || `${response.status} ${response.statusText}`);
  }
}

export function createApiClient({ apiBase = '', token = '' } = {}) {
  return async function api(path, options = {}) {
    const method = options.method || (options.body === undefined ? 'GET' : 'POST');
    const headers = { Accept: 'application/json' };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;

    const response = await fetch(`${normalizeBase(apiBase)}/api/v1${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
    const payload = await response.json().catch(() => null);
    handleResponseStatus(response, payload);
    return payload?.data ?? payload;
  };
}
