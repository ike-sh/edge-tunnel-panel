import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import EmptyState from '../components/EmptyState.jsx';
import StatusBadge from '../components/StatusBadge.jsx';

const roleLabel = { 'nat-transit': 'NAT IX 线路', 'nat-ingress': '公网入口线路' };

export default function Profiles({ profiles, machines, onRefresh, onCreate, onOpenWizard, onApply, onSync, onOpen, loading }) {
  const machineMap = Object.fromEntries((machines || []).map((m) => [m.id, m]));
  const handleCreate = onOpenWizard || onCreate;

  return (
    <div className="page-stack">
      <Card
        title="线路 Profile"
        description="一条线路对应 ix-transit-fabric 的一个 Profile。NAT IX 创建线路，公网入口导入接入码。"
        actions={<button type="button" className="secondary" onClick={onRefresh} disabled={loading}>{loading ? '刷新中' : '刷新'}</button>}
      >
        <div className="actions" style={{ marginBottom: '1rem' }}>
          <button type="button" onClick={handleCreate}>创建 NAT IX 线路</button>
        </div>
        {!profiles.length ? (
          <EmptyState
            title="还没有线路"
            description="先添加 NAT IX 机器，再通过向导创建线路或导入公网入口接入码。"
            action={<button type="button" onClick={handleCreate}>创建 NAT IX 线路</button>}
          />
        ) : (
          <div className="table-scroll">
            <DataTable
              rows={profiles}
              empty="暂无线路。"
              columns={[
                { key: 'name', title: '名称', render: (p) => <button type="button" className="secondary small linkish" onClick={() => onOpen(p)}>{p.name}</button> },
                { key: 'role', title: '类型', render: (p) => roleLabel[p.role] || p.role },
                { key: 'machine', title: '机器', render: (p) => machineMap[p.machine_id]?.name || p.machine_id || '-' },
                { key: 'status', title: '状态', render: (p) => <StatusBadge status={p.status === 'healthy' ? 'succeeded' : 'pending'}>{p.status || 'pending'}</StatusBadge> },
                { key: 'rules', title: '规则', render: (p) => (p.rules?.length ?? 0) },
                {
                  key: 'actions',
                  title: '操作',
                  render: (p) => (
                    <div className="row-actions">
                      <button type="button" className="small" onClick={() => onOpen(p)}>详情</button>
                      <button type="button" className="small secondary" onClick={() => onApply(p)}>应用</button>
                      <button type="button" className="small secondary" onClick={() => onSync(p)}>同步</button>
                    </div>
                  ),
                },
              ]}
            />
          </div>
        )}
      </Card>
    </div>
  );
}
