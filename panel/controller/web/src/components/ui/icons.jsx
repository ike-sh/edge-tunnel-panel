const iconProps = { width: 18, height: 18, fill: 'none', stroke: 'currentColor', strokeWidth: 1.75, strokeLinecap: 'round', strokeLinejoin: 'round' };

export const NavIcons = {
  dashboard: () => (
    <svg {...iconProps} viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1.5" /><rect x="14" y="3" width="7" height="7" rx="1.5" /><rect x="3" y="14" width="7" height="7" rx="1.5" /><rect x="14" y="14" width="7" height="7" rx="1.5" /></svg>
  ),
  machines: () => (
    <svg {...iconProps} viewBox="0 0 24 24"><rect x="2" y="6" width="20" height="12" rx="2" /><circle cx="7" cy="12" r="1.5" fill="currentColor" stroke="none" /><circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none" /><circle cx="17" cy="12" r="1.5" fill="currentColor" stroke="none" /></svg>
  ),
  profiles: () => (
    <svg {...iconProps} viewBox="0 0 24 24"><path d="M4 6h16M4 12h10M4 18h14" /><circle cx="19" cy="12" r="2" /></svg>
  ),
  tasks: () => (
    <svg {...iconProps} viewBox="0 0 24 24"><path d="M9 11l3 3L22 4" /><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" /></svg>
  ),
  diagnostics: () => (
    <svg {...iconProps} viewBox="0 0 24 24"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" /><circle cx="12" cy="12" r="3" /></svg>
  ),
  settings: () => (
    <svg {...iconProps} viewBox="0 0 24 24"><circle cx="12" cy="12" r="3" /><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" /></svg>
  ),
};

export function NavIcon({ name }) {
  const Icon = NavIcons[name];
  return Icon ? <span className="nav-icon">{Icon()}</span> : <span className="nav-dot" />;
}
