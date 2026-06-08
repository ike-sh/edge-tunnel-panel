let unauthorizedHandler = () => {};

export function setUnauthorizedHandler(handler) {
  unauthorizedHandler = typeof handler === 'function' ? handler : () => {};
}

export function notifyUnauthorized() {
  unauthorizedHandler();
}

export function taskOutput(task) {
  if (!task) return '';
  if (task.stdout?.trim()) return task.stdout.trim();
  if (task.result?.trim()) return task.result.trim();
  return task.error?.trim() || '';
}

export function taskBelongsToProfile(task, profileId) {
  if (!task?.payload || !profileId) return false;
  return task.payload.profile_id === profileId;
}
