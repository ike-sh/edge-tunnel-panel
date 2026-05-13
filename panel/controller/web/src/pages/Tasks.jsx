import { useMemo, useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import DetailDrawer from '../components/DetailDrawer.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import { actionLabel, labelStatus, nodeLabel, formatTime, parseJSON, displayLatency, cleanLoss, displayTunnels, displayRoute, pretty, easyTierActions, pbrActions, forwardingActions } from '../utils/format.js';

export default function Tasks({ tasks, nodes, nodeMap, taskFilter, setTaskFilter, taskNodeFilter, setTaskNodeFilter, taskEasyTierOnly, setTaskEasyTierOnly, onRefresh, onCopy }) {
  const [detailTask, setDetailTask] = useState(null);
  const filteredTasks = useMemo(() => tasks.filter((task) =>
    (taskFilter === 'all' || task.status === taskFilter) &&
    (taskNodeFilter === 'all' || task.node_id === taskNodeFilter) &&
    (!taskEasyTierOnly || easyTierActions.includes(task.action) || pbrActions.includes(task.action))
  ), [tasks, taskFilter, taskNodeFilter, taskEasyTierOnly]);

  return (
    <div className="page-stack">
      <Card title="任务" description="集中查看任务状态、nft 内容、错误输出和 Agent 诊断。" actions={<button className="secondary" onClick={onRefresh}>刷新</button>}>
        <div className="toolbar-filters">
          <label>状态<select value={taskFilter} onChange={(event) => setTaskFilter(event.target.value)}><option value="all">全部状态</option>{['pending', 'running', 'succeeded', 'failed', 'expired', 'cancelled'].map((status) => <option key={status} value={status}>{labelStatus(status)}</option>)}</select></label>
          <label>节点<select value={taskNodeFilter} onChange={(event) => setTaskNodeFilter(event.target.value)}><option value="all">全部节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id} / {labelStatus(node.status)}</option>)}</select></label>
          <button className="secondary" onClick={() => setTaskFilter('failed')}>只看失败</button>
          <button className={taskEasyTierOnly ? '' : 'secondary'} onClick={() => setTaskEasyTierOnly(!taskEasyTierOnly)}>EasyTier/PBR 相关</button>
        </div>
        <DataTable
          rows={filteredTasks}
          empty="暂无匹配任务。"
          columns={[
            { key: 'id', title: 'ID', render: (task) => <span title={task.id}>{String(task.id || '').slice(0, 10) || '-'}</span> },
            { key: 'node', title: '节点', render: (task) => nodeLabel(nodeMap[task.node_id]) },
            { key: 'action', title: '动作', render: (task) => <div><strong>{actionLabel(task.action)}</strong><small>{task.action}</small></div> },
            { key: 'status', title: '状态', render: (task) => <StatusBadge status={task.status}>{labelStatus(task.status)}</StatusBadge> },
            { key: 'time', title: '创建/完成', render: (task) => <div><span>{formatTime(task.created_at)}</span><small>{formatTime(task.finished_at)}</small></div> },
            { key: 'summary', title: '摘要', render: (task) => <TaskSummary task={task} /> },
            { key: 'actions', title: '操作', render: (task) => <button className="secondary small" onClick={() => setDetailTask(task)}>查看详情</button> },
          ]}
        />
      </Card>
      <DetailDrawer open={Boolean(detailTask)} title={detailTask ? actionLabel(detailTask.action) : '任务详情'} subtitle={detailTask ? `${nodeLabel(nodeMap[detailTask.node_id])} / ${labelStatus(detailTask.status)}` : ''} onClose={() => setDetailTask(null)} wide>
        {detailTask && <TaskDetails task={detailTask} onCopy={onCopy} />}
      </DetailDrawer>
    </div>
  );
}

function TaskSummary({ task }) {
  const result = parseJSON(task.result);
  const text = String(task.error || task.result || '').slice(0, 160);
  if (task.action === 'verify_network_connectivity' && result.network_ok) {
    return <span>组网成功，Peer {result.peer_count || 0} 个，延迟 {displayLatency(result.best_latency_ms)}，丢包 {cleanLoss(result.packet_loss)}，隧道 {displayTunnels(result.tunnels)}，路由 {displayRoute(result.route_type, true)}</span>;
  }
  if (forwardingActions.includes(task.action) && result.nft_path) {
    const target = result.stage === 'landing'
      ? `${result.landing_host_resolved || result.target_host || '-'}:${result.target_port || '-'}`
      : `${result.target_host || result.target_ip || '-'}:${result.target_port || '-'}`;
    return <span>{result.applied ? '转发已应用' : '转发未应用'}：端口 {result.listen_port || '-'} → {target}</span>;
  }
  if (task.action === 'apply_pbr_policy' || task.action === 'verify_pbr_policy') {
    return <span>{result.route_group_name || result.table_name || 'PBR'} / {result.fwmark || '-'} / {result.verified ? '已验证' : labelStatus(task.status)}</span>;
  }
  return <span>{text || '-'}</span>;
}

function TaskDetails({ task, onCopy }) {
  const result = parseJSON(task.result);
  const failed = task.status === 'failed';
  const diskHint = String(task.error || task.result || '').includes('no space left on device') || String(task.error || task.result || '').includes('磁盘空间不足');
  return (
    <div className="drawer-section">
      {failed && <div className="alert error">任务失败。请优先查看 error、stderr 和 result 中的诊断字段。</div>}
      {diskHint && <div className="alert error">该节点磁盘空间不足，建议清理磁盘或更换更大磁盘节点后重试。</div>}
      {forwardingActions.includes(task.action) && result.nft_check_stderr && <div className="alert error">nft 检查失败：{result.nft_check_stderr}</div>}
      <dl className="kv-grid">
        <dt>任务 ID</dt><dd>{task.id}</dd>
        <dt>节点 ID</dt><dd>{task.node_id}</dd>
        <dt>原始 action</dt><dd>{task.action}</dd>
        <dt>创建</dt><dd>{formatTime(task.created_at)}</dd>
        <dt>开始</dt><dd>{formatTime(task.started_at)}</dd>
        <dt>完成</dt><dd>{formatTime(task.finished_at)}</dd>
      </dl>
      <CodeBlock title="payload" value={task.payload} onCopy={onCopy} />
      <CodeBlock title="result" value={task.result} onCopy={onCopy} />
      {result.nft_content && <CodeBlock title="nft_content" value={result.nft_content} onCopy={onCopy} />}
      {result.nft_check_stderr && <CodeBlock title="nft_check_stderr" value={result.nft_check_stderr} onCopy={onCopy} />}
      <CodeBlock title="stdout" value={task.stdout} onCopy={onCopy} />
      <CodeBlock title="stderr" value={task.stderr} onCopy={onCopy} />
      <CodeBlock title="error" value={task.error} onCopy={onCopy} />
      <CodeBlock title="raw task" value={pretty(task)} onCopy={onCopy} />
    </div>
  );
}
