export default function Modal({ open, title, description, children, footer, onClose, wide = false }) {
  if (!open) return null;
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div
        className={`modal-panel ${wide ? 'wide' : ''}`}
        onMouseDown={(event) => event.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title"
      >
        <div className="modal-head">
          <div>
            <h3 id="modal-title">{title}</h3>
            {description && <p className="muted">{description}</p>}
          </div>
          <button type="button" className="secondary small modal-close" onClick={onClose} aria-label="关闭">×</button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-footer">{footer}</div>}
      </div>
    </div>
  );
}
