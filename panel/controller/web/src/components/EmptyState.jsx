export default function EmptyState({ title = '暂无数据', description, action }) {
  return (
    <div className="empty-state">
      <div className="empty-icon">∅</div>
      <h3>{title}</h3>
      {description && <p>{description}</p>}
      {action && <div className="actions center">{action}</div>}
    </div>
  );
}
