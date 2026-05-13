export default function ConfirmDialog({ open, title = '确认操作', message, confirmText = '确认', cancelText = '取消', danger = false, onConfirm, onClose }) {
  if (!open) return null;
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div className="confirm-dialog" onMouseDown={(event) => event.stopPropagation()}>
        <h3>{title}</h3>
        <p>{message}</p>
        <div className="actions right">
          <button className="secondary" onClick={onClose}>{cancelText}</button>
          <button className={danger ? 'danger' : ''} onClick={onConfirm}>{confirmText}</button>
        </div>
      </div>
    </div>
  );
}
