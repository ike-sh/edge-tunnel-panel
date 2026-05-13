export function normalizeHostIP(value) {
  const text = String(value || '').trim();
  const slash = text.indexOf('/');
  return slash > 0 ? text.slice(0, slash) : text;
}

export function isValidPort(value) {
  const port = Number(value);
  return Number.isInteger(port) && port >= 1 && port <= 65535;
}

export function browserControllerURL() {
  return typeof window === 'undefined' ? 'http://CONTROLLER_HOST:18080' : `${window.location.protocol}//${window.location.host}`;
}
