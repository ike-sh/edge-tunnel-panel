#!/usr/bin/env node
/** E2E: WebSocket first-frame auth (no query token). Requires Node 22+ WebSocket. */
const base = process.env.BASE || 'http://127.0.0.1:19081';
const token = process.env.TOKEN || 'e2e-operator-token';
const wsURL = base.replace(/^http/, 'ws') + '/api/v2/stream/machines';

function fail(msg) {
  console.error('E2E WS FAIL:', msg);
  process.exit(1);
}

async function testQueryTokenRejected() {
  let opened = false;
  await new Promise((resolve) => {
    const ws = new WebSocket(wsURL + '?token=' + encodeURIComponent(token));
    ws.addEventListener('open', () => { opened = true; ws.close(); });
    ws.addEventListener('error', () => resolve());
    ws.addEventListener('close', () => resolve());
    setTimeout(resolve, 2000);
  });
  if (opened) fail('query token must not open websocket');
  console.log('OK query token rejected');
}

async function testAuthFrame() {
  await new Promise((resolve, reject) => {
    const ws = new WebSocket(wsURL);
    let step = 0;
    const timer = setTimeout(() => reject(new Error('timeout waiting for snapshot')), 8000);
    ws.addEventListener('open', () => {
      ws.send(JSON.stringify({ type: 'auth', token }));
    });
    ws.addEventListener('message', (event) => {
      const data = JSON.parse(String(event.data));
      if (step === 0) {
        if (data.type !== 'auth_ok') return reject(new Error('expected auth_ok, got ' + data.type));
        step = 1;
        return;
      }
      if (data.type === 'snapshot') {
        clearTimeout(timer);
        ws.close();
        resolve();
      }
    });
    ws.addEventListener('error', (e) => reject(e.error || new Error('websocket error')));
  });
  console.log('OK auth frame + snapshot');
}

await testQueryTokenRejected();
await testAuthFrame();
console.log('E2E WS auth OK');
