export default function Card({ title, description, actions, children, className = '' }) {
  return (
    <section className={`panel-card ${className}`.trim()}>
      {(title || actions) && (
        <div className="panel-head">
          <div>
            {title && <h2>{title}</h2>}
            {description && <p>{description}</p>}
          </div>
          {actions && <div className="head-actions">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  );
}
