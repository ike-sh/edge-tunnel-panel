import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';

const roleLabel = { 'nat-transit': 'NAT IX', 'nat-ingress': '公网入口' };

export default function Machines({ machines, onRefresh, onCreate, onInstall, loading }) {
  return (
    <div className="page-stack">
      <Card
        title="机器管理"
        description="NAT IX 中转机器与公网入口机。安装 Agent 时在注册 payload 中携带 machine_id。"
        actions={<button className="secondary" onClick={onRefresh} disabled={loading}>{loading ? '刷新中' : '刷新'}</button>}
      >
        <div className="actions" style={{ marginBottom: '1rem' }}>
          <button onClick={() => onCreate('nat-transit')}>添加 NAT IX 机器</button>
          <button className="secondary" onClick={() => onCreate('nat-ingress')}>添加入口机器</button>
        </div>
        <DataTable
          rows={machines}
          empty="暂无机器，请先添加。"
          columns={[
            { key: 'name', title: '名称', render: (m) => m.name },
            { key: 'role', title: '角色', render: (m) => roleLabel[m.role] || m.role },
            { key: 'status', title: '状态', render: (m) => <StatusBadge status={m.status === 'online' ? 'online' : 'waiting'}>{m.status || 'pending'}</StatusBadge> },
            { key: 'node', title: 'Agent', render: (m) => m.node_id || '未注册' },
            {
              key: 'install',
              title: '安装',
              render: (m) => <button className="small secondary" onClick={() => onInstall(m)} disabled={loading}>生成命令</button>,
            },
          ]}
        />
      </Card>
    </div>
  );
}
