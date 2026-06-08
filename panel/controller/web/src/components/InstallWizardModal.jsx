import { useEffect, useState } from 'react';
import Card from './Card.jsx';
import CodeBlock from './CodeBlock.jsx';
import StatusBadge from './StatusBadge.jsx';

const steps = ['前置条件', '安装命令', '验证注册', '完成'];

const roleHint = {
  'nat-transit': 'NAT IX 中转机：负责 nft 转发、生成接入码，需安装 ixtf CLI。',
  'nat-ingress': '公网入口机：导入接入码加入 EasyTier 虚拟网，面向客户端暴露入口端口。',
};

export default function InstallWizardModal({
  open,
  machine,
  installData,
  liveMachine,
  loading,
  onClose,
  onCopy,
  onRefresh,
}) {
  const [step, setStep] = useState(0);

  useEffect(() => {
    if (open) setStep(0);
  }, [open, machine?.id]);

  if (!open || !machine) return null;

  const status = liveMachine?.status || machine.status || 'pending';
  const registered = status === 'online' || status === 'stale';
  const rootCommand = installData?.root_command || '';
  const envBlock = [
    installData?.env_hint,
    `# machine_id=${installData?.machine_id || machine.id}`,
    installData?.note,
  ].filter(Boolean).join('\n');

  function nextStep() {
    setStep((s) => Math.min(steps.length - 1, s + 1));
  }

  function prevStep() {
    setStep((s) => Math.max(0, s - 1));
  }

  return (
    <div className="wizard-overlay" onClick={onClose}>
      <div className="wizard-panel install-wizard" onClick={(e) => e.stopPropagation()}>
        <Card
          title={`安装 Agent · ${machine.name}`}
          description={`步骤 ${step + 1}/${steps.length}：${steps[step]} · ${machine.role === 'nat-ingress' ? '公网入口' : 'NAT IX'}`}
          actions={<button type="button" className="secondary small" onClick={onClose}>关闭</button>}
        >
          <div className="wizard-steps">
            {steps.map((label, i) => (
              <span key={label} className={`wizard-step ${i === step ? 'active' : i < step ? 'done' : ''}`}>
                <span className="wizard-step-num">{i + 1}</span>
                {label}
              </span>
            ))}
          </div>

          {step === 0 && (
            <div className="install-step-panel">
              <p className="muted">{roleHint[machine.role] || '在目标 Linux 服务器安装 Edge Tunnel Agent。'}</p>
              <ul className="install-checklist">
                <li>目标系统：Linux（amd64 / arm64），具备 root 或 sudo</li>
                <li>网络：可访问 Controller 地址（HTTPS/HTTP + WebSocket）</li>
                <li>依赖：<code>curl</code>、<code>bash</code>（安装脚本自动拉取 Agent 二进制）</li>
                <li>NAT IX 额外：建议开放转发端口段；公网入口需能访问 NAT IX 虚拟网</li>
              </ul>
              <dl className="kv-grid compact">
                <dt>机器 ID</dt><dd><code>{machine.id}</code></dd>
                <dt>角色</dt><dd>{machine.role}</dd>
              </dl>
            </div>
          )}

          {step === 1 && (
            <div className="install-step-panel">
              <p className="muted">在目标服务器以 <strong>root</strong> 执行以下命令（一键安装 Agent + ixtf）：</p>
              <CodeBlock title="安装命令" value={rootCommand || '正在生成…'} />
              {envBlock && (
                <>
                  <p className="muted" style={{ marginTop: '0.75rem' }}>环境变量提示（写入 <code>/etc/edge-tunnel-agent.env</code>）：</p>
                  <CodeBlock title="" value={envBlock} />
                </>
              )}
              <div className="actions" style={{ marginTop: '0.75rem' }}>
                <button type="button" onClick={() => onCopy?.(rootCommand, '安装命令')} disabled={!rootCommand}>复制安装命令</button>
              </div>
              <p className="muted install-tip">若复制失败，请手动选中上方文本。安装完成后 Agent 会自动携带 <code>machine_id</code> 注册。</p>
            </div>
          )}

          {step === 2 && (
            <div className="install-step-panel">
              <p className="muted">返回面板刷新，确认机器状态变为 online（首次注册约 10–30 秒）。</p>
              <div className="install-verify-box">
                <div className="install-verify-row">
                  <span>当前状态</span>
                  <StatusBadge status={registered ? 'online' : status === 'offline' ? 'offline' : 'waiting'}>
                    {status}
                  </StatusBadge>
                </div>
                {liveMachine?.last_seen_at && (
                  <div className="install-verify-row">
                    <span>最近心跳</span>
                    <span>{new Date(liveMachine.last_seen_at).toLocaleString('zh-CN')}</span>
                  </div>
                )}
                {liveMachine?.node_id && (
                  <div className="install-verify-row">
                    <span>Node ID</span>
                    <code>{liveMachine.node_id}</code>
                  </div>
                )}
              </div>
              <div className="actions" style={{ marginTop: '0.75rem' }}>
                <button type="button" className="secondary" onClick={onRefresh} disabled={loading}>{loading ? '刷新中…' : '刷新状态'}</button>
              </div>
              {!registered && (
                <p className="muted install-tip">仍为 pending？检查：Token 是否正确、防火墙、Controller 地址是否可从目标机访问。</p>
              )}
            </div>
          )}

          {step === 3 && (
            <div className="install-step-panel">
              {registered ? (
                <>
                  <p><strong>Agent 已注册</strong>，可继续：</p>
                  <ul className="install-checklist">
                    {machine.role === 'nat-transit' && (
                      <>
                        <li>前往「线路」创建 NAT IX 线路并应用规则</li>
                        <li>同步线路后在「接入码」Tab 复制完整码</li>
                      </>
                    )}
                    {machine.role === 'nat-ingress' && (
                      <>
                        <li>在「线路」使用「导入接入码」向导绑定此入口机</li>
                        <li>应用后在客户端测试入口端口连通性</li>
                      </>
                    )}
                    <li>在「诊断」页运行 ix_read_health 验证链路</li>
                  </ul>
                </>
              ) : (
                <>
                  <p><strong>安装命令已生成</strong>，Agent 尚未上线。</p>
                  <p className="muted">请先在服务器完成安装，再回到「验证注册」步骤刷新状态。</p>
                </>
              )}
            </div>
          )}

          <div className="actions wizard-actions">
            {step > 0 && (
              <button type="button" className="secondary" onClick={prevStep}>上一步</button>
            )}
            {step < steps.length - 1 ? (
              <button type="button" onClick={nextStep} disabled={step === 1 && !rootCommand}>下一步</button>
            ) : (
              <button type="button" onClick={onClose}>完成</button>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
