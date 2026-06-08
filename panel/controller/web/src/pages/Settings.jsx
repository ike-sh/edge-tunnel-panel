import Card from '../components/Card.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import { useApp } from '../context/AppContext.jsx';
import { DEFAULT_VERSION } from '../utils/format.js';

export default function Settings() {
  const {
    apiBase,
    setApiBase,
    token,
    setToken,
    strictAuth,
    health,
    saveSettings,
    clearToken,
    refreshHealth,
    handleCopyValue,
  } = useApp();

  const controllerInstall = `curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | bash -s -- \\\n  --version ${DEFAULT_VERSION}`;
  const agentPurge = `curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- --purge --remove-easytier-binaries`;

  return (
    <div className="page-stack">
      <Card title="设置" description="API、Token、运行模式和常用安装命令。">
        <div className="form-grid drawer-form">
          <label>API Base（默认同源）<input value={apiBase} onChange={(event) => setApiBase(event.target.value)} placeholder="留空表示同源" /></label>
          <label>Operator Token<input type="password" value={token} onChange={(event) => setToken(event.target.value)} placeholder={strictAuth ? '严格鉴权时需要' : '测试模式可留空'} /></label>
        </div>
        <div className="actions">
          <button type="button" onClick={saveSettings}>保存设置</button>
          <button type="button" className="secondary" onClick={clearToken}>清除 Token</button>
          <button type="button" className="secondary" onClick={() => refreshHealth()}>测试连接</button>
        </div>
        <dl className="kv-grid">
          <dt>Controller</dt><dd>{health?.name || 'Edge Tunnel Controller'}</dd>
          <dt>版本</dt><dd>{health?.version || DEFAULT_VERSION}</dd>
          <dt>鉴权状态</dt><dd>{strictAuth ? '严格鉴权' : '测试模式免登录'}</dd>
          <dt>Agent 配置目录</dt><dd><code>/etc/edge-tunnel/agent</code></dd>
          <dt>Controller 数据目录</dt><dd><code>/var/lib/edge-tunnel/controller</code></dd>
          <dt>服务</dt><dd><code>edge-tunnel-controller.service</code> / <code>edge-tunnel-agent.service</code> / <code>edge-tunnel-easytier.service</code></dd>
        </dl>
      </Card>
      <Card title="常用命令" description="复制到服务器执行。">
        <CodeBlock title="安装 Controller" value={controllerInstall} onCopy={handleCopyValue} />
        <CodeBlock title="彻底删除 Agent 与 EasyTier 二进制" value={agentPurge} onCopy={handleCopyValue} />
      </Card>
      <Card title="Credits / License" description="Web UI 布局参考 flux-panel 等成熟面板项目的交互模式。">
        <p>UI 信息架构借鉴 <a href="https://github.com/bqlpfy/flux-panel" target="_blank" rel="noreferrer">flux-panel</a>，保留 macOS Glass 视觉风格。</p>
        <p>详见 <code>panel/docs/credits.md</code>。</p>
      </Card>
    </div>
  );
}
