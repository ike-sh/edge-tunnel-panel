import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import { actionLabel, labelStatus, displayLatency, cleanLoss, displayTunnels, displayRoute, nodeLabel, formatTime } from '../utils/format.js';

export default function Dashboard({ stats, nodes, networkLinks, forwards, pbrPolicies, tasks, nodeMap, onNavigate, onOpenAddNode, onRefresh }) {
  const recent = tasks.slice(0, 6);
  const activeLinks = networkLinks.filter((link) => ['active', 'connected'].includes(link.status)).length;
  const appliedForwards = forwards.filter((rule) => ['applied', 'verified'].includes(rule.status)).length;
  const verifiedPBR = pbrPolicies.filter((policy) => policy.status === 'verified').length;
  return (
    <div className="page-stack">
      <div className="metric-grid">
        <Metric title="节点" value={nodes.length} detail={`在线 ${stats.online} / 离线 ${stats.offline}`} />
        <Metric title="组网链路" value={networkLinks.length} detail={`成功 ${activeLinks} 条`} />
        <Metric title="转发规则" value={forwards.length} detail={`已应用 ${appliedForwards} 条`} />
        <Metric title="出口策略" value={pbrPolicies.length} detail={`已验证 ${verifiedPBR} 条`} />
      </div>

      <Card title="快捷入口" description="按上线测试流程从左到右执行。" actions={<button className="secondary" onClick={onRefresh}>刷新数据</button>}>
        <div className="quick-actions">
          <button onClick={onOpenAddNode}>添加节点</button>
          <button onClick={() => onNavigate('networks')}>快速组网</button>
          <button onClick={() => onNavigate('forwards')}>创建转发</button>
          <button onClick={() => onNavigate('pbr')}>创建 PBR</button>
          <button onClick={() => onNavigate('diagnostics')}>一键诊断</button>
        </div>
      </Card>

      <div className="two-column">
        <Card title="链路健康" description="最近一次上报的组网指标。">
          <DataTable
            rows={networkLinks.slice(0, 5)}
            empty="暂无组网链路。"
            columns={[
              { key: 'name', title: '名称', render: (link) => link.name || link.network_name || '-' },
              { key: 'status', title: '状态', render: (link) => <StatusBadge status={link.status}>{['active', 'connected'].includes(link.status) ? '组网成功' : labelStatus(link.status)}</StatusBadge> },
              { key: 'nodes', title: '链路', render: (link) => `${nodeMap[link.entry_node_id]?.name || '-'} → ${nodeMap[link.backend_node_id]?.name || '-'}` },
              { key: 'latency', title: '延迟', render: (link) => displayLatency(link.best_latency_ms) },
              { key: 'route', title: '路由', render: (link) => displayRoute(link.route_type, ['active', 'connected'].includes(link.status)) },
            ]}
          />
        </Card>
        <Card title="最近任务" description="失败任务会在任务页默认展开详情。">
          <DataTable
            rows={recent}
            empty="暂无任务。"
            columns={[
              { key: 'action', title: '动作', render: (task) => actionLabel(task.action) },
              { key: 'node', title: '节点', render: (task) => nodeLabel(nodeMap[task.node_id]) },
              { key: 'status', title: '状态', render: (task) => <StatusBadge status={task.status}>{labelStatus(task.status)}</StatusBadge> },
              { key: 'time', title: '时间', render: (task) => formatTime(task.created_at) },
            ]}
          />
        </Card>
      </div>
    </div>
  );
}

function Metric({ title, value, detail }) {
  return (
    <div className="metric-card">
      <span>{title}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </div>
  );
}
