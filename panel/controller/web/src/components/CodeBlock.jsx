import { pretty } from '../utils/format.js';

export default function CodeBlock({ title, value, onCopy }) {
  const text = pretty(value);
  return (
    <div className="code-block">
      <div className="code-title">
        <strong>{title}</strong>
        {onCopy && <button className="secondary small" onClick={() => onCopy(text, title)}>复制</button>}
      </div>
      <pre>{text}</pre>
    </div>
  );
}
