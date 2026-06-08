import Sidebar from './Sidebar.jsx';
import Topbar from './Topbar.jsx';

export default function Layout({ tabs, activeTab, onTabChange, health, version, strictAuth, loading, alert, onRefresh, theme, onThemeToggle, children }) {
  return (
    <>
      <div className="mac-wallpaper" aria-hidden="true" />
      <div className="app-shell animate-fade-in">
        <Sidebar tabs={tabs} activeTab={activeTab} onTabChange={onTabChange} theme={theme} onThemeToggle={onThemeToggle} />
        <div className="workspace">
          <Topbar health={health} version={version} strictAuth={strictAuth} loading={loading} onRefresh={onRefresh} />
          {alert && <div className={`alert ${alert.type || ''}`}>{alert.message}</div>}
          {!strictAuth && <div className="alert info">当前为测试模式，Web API 未启用 Operator Token 鉴权。</div>}
          <main className="content-area">{children}</main>
        </div>
      </div>
    </>
  );
}
