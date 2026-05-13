import { useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import DetailDrawer from '../components/DetailDrawer.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import EmptyState from '../components/EmptyState.jsx';
import { linkOptionLabel, labelStatus, nodeLabel, publicIP, ruleListenPort, ruleLandingPort, landingHost, transportModeLabel, shortID, pretty } from '../utils/format.js';

export default function Forwards({ forwards, networkLinks, nodeMap, forwardForm, setForwardForm, onCreateForward, onApplyForward, onVerifyForward, onDeleteForward, onRefresh, onCopy }) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const readyLinks = networkLinks.filter((link) => link.status === 'connected' || link.status === 'active');
  const selectedLink = networkLinks.find((item) => item.id === forwardForm.network_link_id);

  async function submit(apply) {
    const result = await onCreateForward({ apply });
    if (result) setDrawerOpen(false);
  }

  return (
    <div className="page-stack">
      <Card
        title="转发规则"
        description="基于已成功的组网链路，把 A 公网入口端口转发到 B 节点，再由 B 转发到落地服务器。"
        actions={<><button className="secondary" onClick={onRefresh}>刷新</button><button onClick={() => setDrawerOpen(true)}>创建转发规则</button></>}
      >
        {forwards.length === 0 ? (
          <EmptyState title="暂无转发规则" description="先完成组网链路，再创建公网端口到落地服务的转发。" />
        ) : (
          <DataTable
            rows={forwards}
            columns={[
              { key: 'name', title: '规则名', render: (rule) => <strong>{rule.name || '-'}</strong> },
              { key: 'protocol', title: '协议', render: (rule) => String(rule.protocol || '').toUpperCase() },
              { key: 'listen', title: 'A 公网端口', render: (rule) => ruleListenPort(rule) },
              { key: 'landing_node', title: 'B 节点', render: (rule) => nodeLabel(nodeMap[rule.landing_node_id || rule.backend_node_id]) },
              { key: 'landing', title: '落地地址', render: (rule) => landingHost(rule) },
              { key: 'landing_port', title: '落地端口', render: (rule) => ruleLandingPort(rule) },
              { key: 'status', title: '状态', render: (rule) => <StatusBadge status={rule.status}>{labelStatus(rule.status)}</StatusBadge> },
              { key: 'stages', title: '阶段', render: (rule) => <span>A {labelStatus(rule.entry_stage_status || 'pending')} / B {labelStatus(rule.landing_stage_status || 'pending')}</span> },
              { key: 'actions', title: '操作', render: (rule) => <div className="row-actions"><button className="small" onClick={() => onApplyForward(rule)}>应用</button><button className="secondary small" onClick={() => onVerifyForward(rule)}>验证</button><button className="danger small" onClick={() => onDeleteForward(rule)}>删除</button></div> },
            ]}
          />
        )}
      </Card>

      <div className="card-grid">
        {forwards.map((rule) => <ForwardSummary key={rule.id} rule={rule} nodeMap={nodeMap} onCopy={onCopy} />)}
      </div>

      <DetailDrawer open={drawerOpen} title="创建转发规则" subtitle="只填写公网端口、落地地址和落地端口，A/B 节点由组网链路自动确定。" onClose={() => setDrawerOpen(false)} wide>
        <div className="form-grid drawer-form">
          <label>选择组网链路<select value={forwardForm.network_link_id} onChange={(event) => setForwardForm({ ...forwardForm, network_link_id: event.target.value })}><option value="">请选择已成功的组网链路</option>{readyLinks.map((link) => <option key={link.id} value={link.id}>{linkOptionLabel(link, nodeMap)}</option>)}</select></label>
          <label>规则名称<input placeholder={forwardForm.public_listen_port ? `forward-${forwardForm.public_listen_port}` : 'forward-18081'} value={forwardForm.name} onChange={(event) => setForwardForm({ ...forwardForm, name: event.target.value })} /></label>
          <label>协议<select value={forwardForm.protocol} onChange={(event) => setForwardForm({ ...forwardForm, protocol: event.target.value })}><option value="tcp">TCP</option><option value="udp">UDP</option><option value="both">TCP+UDP</option></select></label>
          <label>公网监听端口<input type="number" min="1" max="65535" value={forwardForm.public_listen_port} onChange={(event) => setForwardForm({ ...forwardForm, public_listen_port: event.target.value })} placeholder="例如 18081" /></label>
          <label>落地服务器地址<input value={forwardForm.landing_host} onChange={(event) => setForwardForm({ ...forwardForm, landing_host: event.target.value })} placeholder="例如 1.2.3.4 或 backend.example.com" /></label>
          <label>落地服务器端口<input type="number" min="1" max="65535" value={forwardForm.landing_port} onChange={(event) => setForwardForm({ ...forwardForm, landing_port: event.target.value })} placeholder="例如 8080" /></label>
          <label>A 到 B 的传输方式<select value={forwardForm.transport_mode} onChange={(event) => setForwardForm({ ...forwardForm, transport_mode: event.target.value })}><option value="easytier">EasyTier 隧道</option><option value="public">B 公网直连</option></select></label>
          <label className="check"><input type="checkbox" checked={forwardForm.enabled} onChange={(event) => setForwardForm({ ...forwardForm, enabled: event.target.checked })} />启用规则</label>
        </div>
        <div className="route-preview">
          <strong>链路预览</strong>
          <p>{previewRoute(selectedLink, nodeMap, forwardForm)}</p>
          <small>{forwardForm.transport_mode === 'public' ? 'B 公网直连：A 通过 B 的公网 IP 转发，再由 B 落地到目标服务。' : 'EasyTier 隧道：A 通过 B 的 EasyTier 虚拟 IP 转发，再由 B 落地到目标服务。'}</small>
        </div>
        <details className="detail-box">
          <summary>高级设置</summary>
          <label>备注<input value={forwardForm.remark} onChange={(event) => setForwardForm({ ...forwardForm, remark: event.target.value })} /></label>
        </details>
        <div className="actions">
          <button onClick={() => submit(false)}>创建规则</button>
          <button onClick={() => submit(true)}>创建并应用转发</button>
        </div>
      </DetailDrawer>
    </div>
  );
}

function previewRoute(link, nodeMap, form) {
  const entry = link ? nodeMap[link.entry_node_id] : null;
  const landing = link ? nodeMap[link.backend_node_id] : null;
  const publicPort = form.public_listen_port || '公网端口';
  const landingAddr = `${form.landing_host || '落地服务器'}:${form.landing_port || '落地端口'}`;
  if (form.transport_mode === 'public') {
    return `外部客户端 → ${publicIP(entry)}:${publicPort} → A nftables → ${publicIP(landing)}:${publicPort} → B nftables → ${landingAddr}`;
  }
  return `外部客户端 → ${publicIP(entry)}:${publicPort} → A nftables → EasyTier → ${landing?.name || 'B 节点'}:${publicPort} → B nftables → ${landingAddr}`;
}

function ForwardSummary({ rule, nodeMap, onCopy }) {
  const entry = nodeMap[rule.entry_node_id];
  const landing = nodeMap[rule.landing_node_id || rule.backend_node_id];
  const listenPort = ruleListenPort(rule);
  const landingPort = ruleLandingPort(rule);
  const target = landingHost(rule);
  return (
    <article className="summary-card forward-card">
      <div className="summary-head">
        <strong>{rule.name || 'forward'}</strong>
        <StatusBadge status={rule.status}>{labelStatus(rule.status)}</StatusBadge>
      </div>
      <p className="route-line">外部 → {publicIP(entry)}:{listenPort} → {transportModeLabel(rule.transport_mode)} → {landing?.name || 'B 节点'} → {target}:{landingPort}</p>
      <div className="mini-metrics">
        <span>协议 {String(rule.protocol || '').toUpperCase()}</span>
        <span>A 侧 {labelStatus(rule.entry_stage_status || 'pending')}</span>
        <span>B 侧 {labelStatus(rule.landing_stage_status || 'pending')}</span>
        <span title={rule.id}>ID {shortID(rule.id)}</span>
      </div>
      <details>
        <summary>详情</summary>
        <CodeBlock title="转发规则 JSON" value={pretty(rule)} onCopy={onCopy} />
      </details>
    </article>
  );
}
