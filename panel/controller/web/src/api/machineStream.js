function wsBase(apiBase) {
  const trimmed = String(apiBase || '').trim().replace(/\/+$/, '');
  if (trimmed) {
    const url = new URL(trimmed, window.location.origin);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    return url.origin;
  }
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${proto}//${window.location.host}`;
}

export function watchMachineStream(apiBase, token, { onSnapshot, onOpen, onClose, onError } = {}) {
  let ws = null;
  let stopped = false;
  let reconnectTimer = null;
  let attempts = 0;
  let lastMessageAt = 0;

  function connect() {
    if (stopped) return;
    if (typeof document !== 'undefined' && document.visibilityState === 'hidden') {
      reconnectTimer = window.setTimeout(connect, 3000);
      return;
    }
    const base = wsBase(apiBase);
    const url = `${base}/api/v2/stream/machines`;

    try {
      ws = new WebSocket(url);
    } catch (error) {
      onError?.(error);
      scheduleReconnect();
      return;
    }

    let authed = !token;

    ws.onopen = () => {
      attempts = 0;
      lastMessageAt = Date.now();
      if (token) {
        ws.send(JSON.stringify({ type: 'auth', token }));
      } else {
        authed = true;
        onOpen?.();
      }
    };

    ws.onmessage = (event) => {
      lastMessageAt = Date.now();
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'auth_ok') {
          authed = true;
          onOpen?.();
          return;
        }
        if (data.type === 'auth_error') {
          onError?.(new Error(data.message || 'websocket auth failed'));
          ws.close();
          return;
        }
        if (data.type === 'snapshot' && authed) {
          onSnapshot?.(data);
        }
      } catch {
        /* ignore malformed frames */
      }
    };

    ws.onerror = () => {
      if (!stopped) onError?.(new Error('websocket error'));
    };

    ws.onclose = () => {
      ws = null;
      onClose?.();
      scheduleReconnect();
    };
  }

  function scheduleReconnect() {
    if (stopped) return;
    attempts += 1;
    const delay = Math.min(30000, 1000 * 2 ** Math.min(attempts, 5));
    reconnectTimer = window.setTimeout(connect, delay);
  }

  const staleChecker = window.setInterval(() => {
    if (stopped || !lastMessageAt) return;
    if (Date.now() - lastMessageAt > 15000 && ws?.readyState === WebSocket.OPEN) {
      ws.close();
    }
  }, 5000);

  connect();

  return () => {
    stopped = true;
    window.clearInterval(staleChecker);
    if (reconnectTimer) window.clearTimeout(reconnectTimer);
    if (ws) {
      ws.onopen = null;
      ws.onmessage = null;
      ws.onerror = null;
      ws.onclose = null;
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close();
      }
      ws = null;
    }
  };
}
