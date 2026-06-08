export default function GlassPanel({ children, className = '', strong = false, subtle = false }) {
  const cls = strong ? 'glass-strong' : subtle ? 'glass-subtle' : 'glass';
  return <div className={`${cls} ${className}`.trim()}>{children}</div>;
}

export function StatCard({ label, value, detail, className = '' }) {
  return (
    <div className={`metric-card glass stat-card animate-slide-up ${className}`.trim()}>
      <span className="stat-label">{label}</span>
      <strong>{value}</strong>
      {detail && <small>{detail}</small>}
    </div>
  );
}

export function PageHeader({ title, description, action }) {
  return (
    <div className="page-header animate-slide-up">
      <div>
        {title && <h2 className="page-header-title">{title}</h2>}
        {description && <p className="page-header-desc">{description}</p>}
      </div>
      {action && <div className="page-header-action">{action}</div>}
    </div>
  );
}
