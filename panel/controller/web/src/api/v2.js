export function createApiV2Client({ apiBase = '', token = '' } = {}) {
  return async function apiV2(path, options = {}) {
    const method = options.method || (options.body === undefined ? 'GET' : 'POST');
    const headers = { Accept: 'application/json' };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;

    const response = await fetch(`${String(apiBase || '').trim().replace(/\/+$/, '')}/api/v2${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok || payload?.ok === false) {
      throw new Error(payload?.error?.message || `${response.status} ${response.statusText}`);
    }
    return payload?.data ?? payload;
  };
}
