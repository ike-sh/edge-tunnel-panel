export default function DetailDrawer({ open, title, subtitle, children, onClose, wide = false }) {
  if (!open) return null;
  return (
    <div className="drawer-backdrop" onMouseDown={onClose}>
      <aside className={`detail-drawer ${wide ? 'wide' : ''}`} onMouseDown={(event) => event.stopPropagation()}>
        <div className="drawer-head">
          <div>
            <h2>{title}</h2>
            {subtitle && <p>{subtitle}</p>}
          </div>
          <button className="icon-button" onClick={onClose}>×</button>
        </div>
        <div className="drawer-body">{children}</div>
      </aside>
    </div>
  );
}
