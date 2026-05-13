import { useMemo, useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import DetailDrawer from '../components/DetailDrawer.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import EmptyState from '../components/EmptyState.jsx';
import { DEFAULT_VERSION, readActions, writeActions, actionLabel, labelStatus, statusClass, networkStatusText, cleanLoss, displayLatency, displayTunnels, displayRoute, publicIP, shortID, timeAgo, pretty } from '../utils/format.js';

export default function Nodes({ nodes, agentForm, setAgentForm, agentCommand, onGenerateAgentCommand, onCopyCommand, onRefresh, onCreateTask, onDeleteNode, onCopy, loading }) {
  const [addOpen, setAddOpen] = useState(false);
  const [actionNode, setActionNode] = useState(null);
  const [detailNode, setDetailNode] = useState(null);
  const rows = useMemo(() => nodes, [nodes]);

  return (
    <div className="page-stack">
      <Card
        title="节点"
        description="管理已接入的被控服务器，节点操作和接入命令都放在抽屉中，不再撑开页面。"
        actions={<><button className="secondary" onClick={onRefresh}>刷新</button><button onClick={() => setAddOpen(true)}>添加节点</button></>}
      >
        {rows.length === 0 ? (
          <EmptyState title="暂无节点" description="点击右上角“添加节点”生成 Agent 接入命令。" />
        ) : (
          <DataTable
            rows={rows}
            columns={[
              { key: 'name', title: '节点', render: (node) => <div><strong>{node.name || '-'}</strong><small title={node.id}>ID {shortID(node.id)}</small></div> },
              { key: 'status', title: '状态', render: (node) => <StatusBadge status={node.status}>{labelStatus(node.status)}</StatusBadge> },
              { key: 'public_ip', title: '公网 IP', render: (node) => publicIP(node) },
              { key: 'easytier_ip', title: '虚拟 IP', render: (node) => node.easytier_ip || '未分配' },
              { key: 'easytier_status', title: 'EasyTier', render: (node) => <StatusBadge status={node.easytier_status}>{labelStatus(node.easytier_status)}</StatusBadge> },
              { key: 'peer', title: 'Peer/延迟', render: (node) => `${node.easytier_peer_count || 0} 个 / ${displayLatency(node.easytier_best_latency_ms)}` },
              { key: 'seen', title: '最后上报', render: (node) => timeAgo(node.last_seen_at) },
              { key: 'actions', title: '操作', render: (node) => <div className="row-actions"><button className="secondary small" onClick={() => setDetailNode(node)}>详情</button><button className="small" onClick={() => setActionNode(node)}>节点操作</button><button className="danger small" onClick={() => onDeleteNode(node)}>删除记录</button></div> },
            ]}
          />
        )}
      </Card>

      <DetailDrawer open={addOpen} title="新节点接入" subtitle="复制命令到被控服务器执行，节点会自动上线。" onClose={() => setAddOpen(false)} wide>
        <div className="form-grid drawer-form">
          <label>节点名称<input value={agentForm.node_name} onChange={(event) => setAgentForm({ ...agentForm, node_name: event.target.value })} placeholder="edge-node-1" /></label>
          <label>Controller 地址<input value={agentForm.controller_url} onChange={(event) => setAgentForm({ ...agentForm, controller_url: event.target.value })} /></label>
          <label>版本<input value={agentForm.version} onChange={(event) => setAgentForm({ ...agentForm, version: event.target.value })} placeholder={DEFAULT_VERSION} /></label>
          <label className="check"><input type="checkbox" checked={agentForm.enable_tasks} onChange={(event) => setAgentForm({ ...agentForm, enable_tasks: event.target.checked })} />启用任务轮询</label>
          <label className="check"><input type="checkbox" checked={agentForm.enable_write_actions} onChange={(event) => setAgentForm({ ...agentForm, enable_write_actions: event.target.checked })} />允许写入动作</label>
        </div>
        <div className="alert warning">命令包含 Agent 接入 Token，请勿泄露。默认 root 命令适合已使用 root 登录的服务器。</div>
        <div className="actions">
          <button onClick={onGenerateAgentCommand} disabled={loading}>获取一键安装命令</button>
          <button className="secondary" onClick={() => onCopyCommand('root', agentCommand.root)}>复制 root 命令</button>
          <button className="secondary" onClick={() => onCopyCommand('sudo', agentCommand.sudo)}>复制 sudo 命令</button>
        </div>
        <CodeBlock title="root 命令" value={agentCommand.root || '请先点击“获取一键安装命令”。'} onCopy={onCopy} />
        <CodeBlock title="sudo 命令" value={agentCommand.sudo || '请先点击“获取一键安装命令”。'} onCopy={onCopy} />
      </DetailDrawer>

      <DetailDrawer open={Boolean(actionNode)} title={actionNode ? `节点操作：${actionNode.name || actionNode.id}` : '节点操作'} subtitle={actionNode ? `${labelStatus(actionNode.status)} / ${publicIP(actionNode)} / ${actionNode.easytier_ip || '未分配'}` : ''} onClose={() => setActionNode(null)} wide>
        {actionNode && <NodeActions node={actionNode} onCreateTask={onCreateTask} onDeleteNode={onDeleteNode} />}
      </DetailDrawer>

      <DetailDrawer open={Boolean(detailNode)} title={detailNode ? `节点详情：${detailNode.name || detailNode.id}` : '节点详情'} onClose={() => setDetailNode(null)} wide>
        {detailNode && <NodeDetails node={detailNode} onCopy={onCopy} />}
      </DetailDrawer>
    </div>
  );
}

function NodeActions({ node, onCreateTask, onDeleteNode }) {
  return (
    <div className="action-sections">
      <ActionGroup title="只读检查" actions={readActions} node={node} onCreateTask={onCreateTask} />
      <ActionGroup title="写入维护" tone="warning" description="这些操作会修改节点服务状态，请只在可信节点执行。" actions={writeActions} node={node} onCreateTask={onCreateTask} />
      <div className="action-group danger-zone">
        <h3>危险操作</h3>
        <p>仅删除主控面板中的节点记录，不会卸载远端 Agent。</p>
        <button className="danger" onClick={() => onDeleteNode(node)}>删除节点记录</button>
      </div>
    </div>
  );
}

function ActionGroup({ title, description, actions, node, onCreateTask, tone }) {
  return (
    <div className={`action-group ${tone || ''}`.trim()}>
      <h3>{title}</h3>
      {description && <p>{description}</p>}
      <div className="button-grid">
        {actions.map((action) => <button key={action} className={tone === 'warning' ? 'warning-btn' : 'secondary'} onClick={() => onCreateTask(node.id, action)}>{actionLabel(action)}</button>)}
      </div>
    </div>
  );
}

function NodeDetails({ node, onCopy }) {
  const networkOK = node.easytier_network_ok || Number(node.easytier_peer_count || 0) > 0;
  return (
    <div className="drawer-section">
      <dl className="kv-grid">
        <dt>节点 ID</dt><dd title={node.id}>{node.id}</dd>
        <dt>公网 IP</dt><dd>{publicIP(node)}</dd>
        <dt>内网 IP</dt><dd>{node.private_ip || '-'}</dd>
        <dt>虚拟 IP</dt><dd>{node.easytier_ip || '未分配'}</dd>
        <dt>组网状态</dt><dd>{networkStatusText(node)}</dd>
        <dt>Peer</dt><dd>{node.easytier_peer_count || 0} 个</dd>
        <dt>延迟</dt><dd>{displayLatency(node.easytier_best_latency_ms)}</dd>
        <dt>丢包</dt><dd>{cleanLoss(node.easytier_packet_loss)}</dd>
        <dt>隧道</dt><dd>{displayTunnels(node.easytier_tunnels)}</dd>
        <dt>路由</dt><dd>{displayRoute(node.easytier_route_type, networkOK)}</dd>
        <dt>状态原因</dt><dd>{node.status_reason || '-'}</dd>
      </dl>
      {node.easytier_status === 'active' && Number(node.easytier_peer_count || 0) === 0 && <div className="alert warning">EasyTier 已运行，但未发现远端 Peer。请检查 peers、安全组和网络密钥。</div>}
      <CodeBlock title="完整节点数据" value={pretty(node)} onCopy={onCopy} />
    </div>
  );
}
