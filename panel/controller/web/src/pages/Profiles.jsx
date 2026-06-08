import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';

const roleLabel = { 'nat-transit': 'NAT IX 线路', 'nat-ingress': '公网入口线路' };

export default function Profiles({ profiles, machines, onRefresh, onCreate, onApply, onSync, onOpen, loading }) {
  const machineMap = Object.fromEntries((machines || []).map((m) => [m.id, m]));

  return (
    <div className="page-stack">
      <Card
        title="线路 Profile"
        description="一条线路对应 ix-transit-fabric 的一个 Profile。NAT IX 创建线路，公网入口导入接入码。"
        actions={<button className="secondary" onClick={onRefresh} disabled={loading}>{loading ? '刷新中' : '刷新'}</button>}
      >
        <div className="actions" style={{ marginBottom: '1rem' }}>
          <button onClick={onCreate}>创建 NAT IX 线路</button>
        </div>
        <DataTable
          rows={profiles}
          empty="暂无线路。"
          columns={[
            { key: 'name', title: '名称', render: (p) => p.name },
            { key: 'role', title: '类型', render: (p) => roleLabel[p.role] || p.role },
            { key: 'machine', title: '机器', render: (p) => machineMap[p.machine_id]?.name || p.machine_id || '-' },
            { key: 'status', title: '状态', render: (p) => <StatusBadge status={p.status === 'healthy' ? 'succeeded' : 'pending'}>{p.status || 'pending'}</StatusBadge> },
            { key: 'rules', title: '规则', render: (p) => (p.rules?.length ?? 0) },
            {
              key: 'actions',
              title: '操作',
              render: (p) => (
                <div className="row-actions">
                  <button className="small" onClick={() => onOpen(p)}>详情</button>
                  <button className="small secondary" onClick={() => onApply(p)}>应用</button>
                  <button className="small secondary" onClick={() => onSync(p)}>同步</button>
                </div>
              ),
            },
          ]}
        />
      </Card>
    </div>
  );
}
