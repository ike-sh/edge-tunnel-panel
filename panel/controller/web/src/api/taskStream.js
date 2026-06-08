export function streamTask(apiBase, token, taskId, { onUpdate, onDone, onError } = {}) {
  const base = String(apiBase || '').trim().replace(/\/+$/, '');
  const url = `${base}/api/v2/tasks/${encodeURIComponent(taskId)}/stream`;
  const controller = new AbortController();

  (async () => {
    try {
      const response = await fetch(url, {
        headers: {
          Accept: 'text/event-stream',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}`);
      }
      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('stream unavailable');
      }
      const decoder = new TextDecoder();
      let buffer = '';
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const chunks = buffer.split('\n\n');
        buffer = chunks.pop() || '';
        for (const chunk of chunks) {
          const line = chunk.split('\n').find((item) => item.startsWith('data: '));
          if (!line) continue;
          const task = JSON.parse(line.slice(6));
          onUpdate?.(task);
          if (['succeeded', 'failed', 'expired', 'cancelled'].includes(task.status)) {
            onDone?.(task);
            return;
          }
        }
      }
    } catch (error) {
      if (error.name !== 'AbortError') {
        onError?.(error);
      }
    }
  })();

  return () => controller.abort();
}

export function watchTasks(apiBase, token, taskIds, callbacks) {
  const stops = taskIds.filter(Boolean).map((taskId) => streamTask(apiBase, token, taskId, callbacks));
  return () => stops.forEach((stop) => stop());
}
