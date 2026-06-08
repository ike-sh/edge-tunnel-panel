export const routes = [
  { path: '/dashboard', key: 'dashboard', label: '总览' },
  { path: '/machines', key: 'machines', label: '机器' },
  { path: '/profiles', key: 'profiles', label: '线路' },
  { path: '/diagnostics', key: 'diagnostics', label: '诊断' },
  { path: '/tasks', key: 'tasks', label: '任务' },
  { path: '/settings', key: 'settings', label: '设置' },
];

export function routeLabel(pathname) {
  if (pathname.startsWith('/profiles/')) return '线路详情';
  const hit = routes.find((r) => r.path === pathname);
  return hit?.label || 'Edge Tunnel Panel';
}
