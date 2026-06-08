import Modal from './Modal.jsx';
import CodeBlock from './CodeBlock.jsx';

export default function CopyModal({ open, title, description, content, onClose, onCopy }) {
  return (
    <Modal
      open={open}
      title={title}
      description={description}
      onClose={onClose}
      wide
      footer={(
        <div className="actions right">
          <button type="button" className="secondary" onClick={onClose}>关闭</button>
          <button type="button" onClick={() => onCopy?.(content)}>复制到剪贴板</button>
        </div>
      )}
    >
      <CodeBlock title="" value={content} />
    </Modal>
  );
}
