import { pretty } from '../utils/format.js';

export default function CodeBlock({ title, value, onCopy }) {
  const text = pretty(value);
  return (
    <div className="code-block">
      {(title || onCopy) && (
        <div className="code-title">
          {title ? <strong>{title}</strong> : <span />}
          {onCopy && <button type="button" className="secondary small" onClick={() => onCopy(text, title || '内容')}>复制</button>}
        </div>
      )}
      <pre>{text}</pre>
    </div>
  );
}
