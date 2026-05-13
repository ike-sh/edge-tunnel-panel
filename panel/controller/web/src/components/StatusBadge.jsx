export default function StatusBadge({ status, children }) {
  return <span className={`badge ${status || 'unknown'}`}>{children || status || '-'}</span>;
}
