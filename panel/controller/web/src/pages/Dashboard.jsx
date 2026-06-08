import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import { StatCard } from '../components/ui/GlassPanel.jsx';
import { actionLabel, labelStatus, formatTime } from '../utils/format.js';

export default function Dashboard({ stats, machines, profiles, tasks, onNavigate, onOpenAddNode, onOpenWizard, onOpenImport, onOpenProfile, onRefresh }) {
  const recent = tasks.filter((t) => t.action?.startsWith('ix_')).slice(0, 6);
  const healthy = profiles.filter((p) => p.status === 'healthy').length;
  const natCount = profiles.filter((p) => p.role === 'nat-transit').length;
  const ingressCount = profiles.filter((p) => p.role === 'nat-ingress').length;
  const sample = profiles.find((p) => p.role === 'nat-transit') || profiles[0];
  const cfg = sample?.config || {};
  return (
    <div className="page-stack">
      <div className="metric-grid">
        <StatCard label="机器" value={machines.length} detail={`在线 ${stats.online} / 待注册 ${stats.stale}`} />
        <StatCard label="线路" value={profiles.length} detail={`健康 ${healthy} · NAT ${natCount} / 入口 ${ingressCount}`} />
        <StatCard label="任务" value={tasks.length} detail={`失败 ${stats.failed} 条`} />
        <StatCard label="Agent" value={stats.online} detail={`离线 ${stats.offline}`} />
      </div>

      {sample && (
        <Card title="链路拓扑预览" description="基于首条 NAT IX 线路配置示意。">
          <div className="topology-flow">
            <span className="topology-node">客户端</span>
            <span className="topology-arrow">→</span>
            <span className="topology-node">公网入口:{cfg.LOCAL_PORT || '—'}</span>
            <span className="topology-arrow">→</span>
            <span className="topology-node">ET 虚拟网</span>
            <span className="topology-arrow">→</span>
            <span className="topology-node">NAT IX:{cfg.TRANSIT_PORT || cfg.NAT_PUBLIC_PORT || '—'}</span>
            <span className="topology-arrow">→</span>
            <span className="topology-node">{cfg.LANDING_HOST || '落地'}:{cfg.LANDING_PORT || '—'}</span>
          </div>
        </Card>
      )}

      <Card title="快捷入口" description="NAT IX 正式流程：创建 NAT IX 线路 → 生成接入码 → 公网入口导入。" actions={<button className="secondary" onClick={onRefresh}>刷新数据</button>}>
        <div className="quick-actions">
          <button onClick={onOpenAddNode}>添加机器</button>
          <button onClick={onOpenWizard}>创建 NAT IX 线路</button>
          <button className="secondary" onClick={onOpenImport}>导入接入码</button>
          <button onClick={() => onNavigate('profiles')}>线路列表</button>
          <button onClick={() => onNavigate('diagnostics')}>一键诊断</button>
        </div>
      </Card>

      <div className="two-column">
        <Card title="线路概览" description="点击线路名称查看详情 Tab。">
          <DataTable
            rows={profiles.slice(0, 5)}
            empty="暂无线路，请先创建 NAT IX 线路。"
            columns={[
              { key: 'name', title: '名称', render: (p) => <button className="secondary small" onClick={() => onOpenProfile(p)}>{p.name}</button> },
              { key: 'role', title: '类型', render: (p) => (p.role === 'nat-transit' ? 'NAT IX' : '公网入口') },
              { key: 'status', title: '状态', render: (p) => <StatusBadge status={p.status === 'healthy' ? 'succeeded' : 'pending'}>{p.status || 'pending'}</StatusBadge> },
            ]}
          />
        </Card>
        <Card title="最近任务" description="ix_read / ix_write 任务执行记录。">
          <DataTable
            rows={recent}
            empty="暂无任务。"
            columns={[
              { key: 'action', title: '动作', render: (task) => actionLabel(task.action) || task.action },
              { key: 'status', title: '状态', render: (task) => <StatusBadge status={task.status}>{labelStatus(task.status)}</StatusBadge> },
              { key: 'time', title: '时间', render: (task) => formatTime(task.created_at) },
            ]}
          />
        </Card>
      </div>
    </div>
  );
}
