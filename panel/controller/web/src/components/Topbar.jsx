import StatusBadge from './StatusBadge.jsx';

export default function Topbar({ health, version, strictAuth, loading, onRefresh }) {
  return (
    <header className="topbar">
      <div>
        <h1>Edge Tunnel Panel</h1>
        <p>组网、转发、出口策略与任务排障控制台</p>
      </div>
      <div className="topbar-actions">
        <StatusBadge status={health ? 'succeeded' : 'waiting'}>{health ? 'Controller 正常' : '等待连接'}</StatusBadge>
        <span className="version-pill">{health?.version || version}</span>
        <span className={strictAuth ? 'auth-pill strict' : 'auth-pill'}>{strictAuth ? '严格鉴权' : '测试模式'}</span>
        <button className="secondary" onClick={onRefresh} disabled={loading}>{loading ? '处理中' : '刷新'}</button>
      </div>
    </header>
  );
}
