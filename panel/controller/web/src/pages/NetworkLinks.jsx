import { useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import DetailDrawer from '../components/DetailDrawer.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import EmptyState from '../components/EmptyState.jsx';
import { linkStatusText, labelStatus, statusClass, linkNodeNames, nodeOptionLabel, displayLatency, cleanLoss, displayTunnels, displayRoute, safeList, pretty, randomSecret } from '../utils/format.js';

export default function NetworkLinks({ nodes, nodeMap, networkLinks, networkProfiles, quickForm, setQuickForm, onQuickApply, onReapply, onDisable, onDelete, onEdit, onRefresh, onCopy }) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const onlineNodes = nodes.filter((node) => node.status === 'online');

  function startEdit(link) {
    onEdit(link);
    setDrawerOpen(true);
  }

  return (
    <div className="page-stack">
      <Card
        title="组网链路"
        description="选择 A 公网入口节点和 B 落地节点，系统自动下发 EasyTier 配置并自动验证。"
        actions={<><button className="secondary" onClick={onRefresh}>刷新</button><button onClick={() => setDrawerOpen(true)}>快速创建链路</button></>}
      >
        {networkLinks.length === 0 ? (
          <EmptyState title="暂无组网链路" description="点击右上角“快速创建链路”，选择入口节点和后端节点即可开始。" />
        ) : (
          <DataTable
            rows={networkLinks}
            columns={[
              { key: 'name', title: '名称', render: (link) => <strong>{link.name || link.network_name || 'edge-net'}</strong> },
              { key: 'nodes', title: '链路', render: (link) => linkNodeNames(link, nodeMap) },
              { key: 'status', title: '状态', render: (link) => <StatusBadge status={['active', 'connected'].includes(link.status) ? 'succeeded' : link.status}>{linkStatusText(link)}</StatusBadge> },
              { key: 'peer', title: 'Peer', render: (link) => `入口 ${link.entry_peer_count || 0} / 后端 ${link.backend_peer_count || 0}` },
              { key: 'latency', title: '延迟', render: (link) => displayLatency(link.best_latency_ms) },
              { key: 'mss', title: 'MTU/MSS', render: (link) => `${link.mtu || 1380} / ${link.mss_clamp_enabled === false ? '未启用' : '已启用'}` },
              { key: 'actions', title: '操作', render: (link) => <div className="row-actions"><button className="secondary small" onClick={() => startEdit(link)}>修改</button><button className="small" onClick={() => onReapply(link)}>启用</button><button className="secondary small" onClick={() => onDisable(link)}>禁用</button><button className="danger small" onClick={() => onDelete(link)}>删除</button></div> },
            ]}
          />
        )}
      </Card>

      <div className="card-grid">
        {networkLinks.map((link) => <NetworkLinkSummary key={link.id} link={link} nodeMap={nodeMap} onCopy={onCopy} />)}
      </div>

      <DetailDrawer open={drawerOpen} title="快速组网" subtitle="普通测试建议只填写基础字段，高级参数按需展开。" onClose={() => setDrawerOpen(false)} wide>
        <div className="form-grid drawer-form">
          <label>组网名称<input value={quickForm.name} onChange={(event) => setQuickForm({ ...quickForm, name: event.target.value })} /></label>
          <label>网络名<input value={quickForm.network_name} onChange={(event) => setQuickForm({ ...quickForm, network_name: event.target.value })} /></label>
          <label>网络密钥<div className="input-with-button"><input value={quickForm.network_secret} onChange={(event) => setQuickForm({ ...quickForm, network_secret: event.target.value })} placeholder="留空由 Controller 自动生成" /><button className="secondary small" onClick={() => setQuickForm({ ...quickForm, network_secret: randomSecret() })}>生成</button></div></label>
          <label>CIDR<input value={quickForm.cidr} onChange={(event) => setQuickForm({ ...quickForm, cidr: event.target.value })} /></label>
          <label>监听端口<input type="number" value={quickForm.port} onChange={(event) => setQuickForm({ ...quickForm, port: event.target.value })} /></label>
          <label>公网入口节点<select value={quickForm.entry_node_id} onChange={(event) => setQuickForm({ ...quickForm, entry_node_id: event.target.value })}><option value="">请选择在线入口节点</option>{onlineNodes.map((node) => <option key={node.id} value={node.id}>{nodeOptionLabel(node)}</option>)}</select></label>
          <label>后端节点<select value={quickForm.backend_node_id} onChange={(event) => setQuickForm({ ...quickForm, backend_node_id: event.target.value })}><option value="">请选择在线后端节点</option>{onlineNodes.map((node) => <option key={node.id} value={node.id}>{nodeOptionLabel(node)}</option>)}</select></label>
          <label className="check"><input type="checkbox" checked={quickForm.tcp} onChange={(event) => setQuickForm({ ...quickForm, tcp: event.target.checked })} />TCP</label>
          <label className="check"><input type="checkbox" checked={quickForm.udp} onChange={(event) => setQuickForm({ ...quickForm, udp: event.target.checked })} />UDP</label>
        </div>
        <details className="detail-box">
          <summary>高级参数</summary>
          <div className="form-grid drawer-form">
            <label>MTU<input type="number" value={quickForm.mtu} onChange={(event) => setQuickForm({ ...quickForm, mtu: event.target.value })} /></label>
            <label>MSS 模式<select value={quickForm.mss_mode} onChange={(event) => setQuickForm({ ...quickForm, mss_mode: event.target.value })}><option value="auto">自动</option><option value="fixed">固定</option><option value="disabled">禁用</option></select></label>
            <label>固定 MSS<input type="number" value={quickForm.mss_value} onChange={(event) => setQuickForm({ ...quickForm, mss_value: event.target.value })} /></label>
            <label className="check"><input type="checkbox" checked={quickForm.mss_clamp_enabled} onChange={(event) => setQuickForm({ ...quickForm, mss_clamp_enabled: event.target.checked })} />启用 MSS clamp</label>
            <label>自定义 listeners<textarea value={quickForm.listeners} onChange={(event) => setQuickForm({ ...quickForm, listeners: event.target.value })} /></label>
            <label>自定义 peers<textarea value={quickForm.peers} onChange={(event) => setQuickForm({ ...quickForm, peers: event.target.value })} /></label>
            <label className="check"><input type="checkbox" checked={quickForm.showAdvanced} onChange={(event) => setQuickForm({ ...quickForm, showAdvanced: event.target.checked })} />提交自定义 listeners/peers</label>
          </div>
          <CodeBlock title="原始配置预览" value={{ ...quickForm, protocols: [quickForm.tcp && 'tcp', quickForm.udp && 'udp'].filter(Boolean) }} onCopy={onCopy} />
        </details>
        <div className="actions">
          <button onClick={async () => { await onQuickApply(); setDrawerOpen(false); }}>创建并应用组网</button>
        </div>
      </DetailDrawer>

      <details className="detail-box muted-box">
        <summary>历史组网配置 / 已保存配置</summary>
        {networkProfiles.length === 0 ? <p className="muted">暂无历史配置。</p> : networkProfiles.map((profile) => <CodeBlock key={profile.id} title={profile.name || profile.id} value={profile} onCopy={onCopy} />)}
      </details>
    </div>
  );
}

function NetworkLinkSummary({ link, nodeMap, onCopy }) {
  const ok = link.status === 'active' || link.status === 'connected';
  return (
    <article className="summary-card">
      <div className="summary-head">
        <strong>{link.name || link.network_name}</strong>
        <StatusBadge status={ok ? 'succeeded' : link.status}>{linkStatusText(link)}</StatusBadge>
      </div>
      <p className="route-line">{linkNodeNames(link, nodeMap)}</p>
      <div className="mini-metrics">
        <span>Peer {link.entry_peer_count || 0}/{link.backend_peer_count || 0}</span>
        <span>延迟 {displayLatency(link.best_latency_ms)}</span>
        <span>丢包 {cleanLoss(link.packet_loss)}</span>
        <span>隧道 {displayTunnels(link.tunnels)}</span>
        <span>路由 {displayRoute(link.route_type, ok)}</span>
        <span>MTU {link.mtu || 1380}</span>
      </div>
      <details>
        <summary>详情</summary>
        <CodeBlock title="组网链路 JSON" value={pretty(link)} onCopy={onCopy} />
      </details>
    </article>
  );
}
