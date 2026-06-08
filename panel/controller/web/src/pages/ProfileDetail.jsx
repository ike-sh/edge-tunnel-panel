import { useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';

const roleLabel = { 'nat-transit': 'NAT IX 线路', 'nat-ingress': '公网入口线路' };

export default function ProfileDetail({ profile, machine, pendingTaskIds = [], onBack, onApply, onSync, onRefreshCode, loading }) {
  const [tab, setTab] = useState('overview');
  if (!profile) return null;

  const rules = profile.rules || [];
  const syncing = pendingTaskIds.length > 0;

  return (
    <div className="page-stack">
      <Card
        title={profile.name}
        description={`${roleLabel[profile.role] || profile.role} · ${machine?.name || profile.machine_id}`}
        actions={
          <div className="head-actions">
            <button className="secondary small" onClick={onBack}>返回列表</button>
            <button className="secondary small" onClick={() => onSync(profile)} disabled={loading || syncing}>{syncing ? '同步中…' : '同步'}</button>
            <button className="small" onClick={() => onApply(profile)} disabled={loading || syncing}>应用</button>
          </div>
        }
      >
        {syncing && <p className="muted">任务执行中（SSE），完成后自动刷新 port_map / code / rules…</p>}
        <div className="profile-tabs">
          {['overview', 'rules', 'code', 'portmap'].map((key) => (
            <button key={key} type="button" className={`secondary small ${tab === key ? 'active' : ''}`} onClick={() => setTab(key)}>
              {{ overview: '概览', rules: '规则', code: '接入码', portmap: '端口地图' }[key]}
            </button>
          ))}
        </div>

        {tab === 'overview' && (
          <div className="drawer-section profile-tab-panel">
            <div className="route-preview">
              <p><strong>链路拓扑</strong></p>
              <p>客户端 → 公网入口:{profile.config?.LOCAL_PORT || '—'} → ET 虚拟网 → NAT IX:{profile.config?.TRANSIT_PORT || '—'} → {profile.config?.LANDING_HOST || '落地'}:{profile.config?.LANDING_PORT || '—'}</p>
            </div>
            <dl className="kv-grid">
              <dt>状态</dt><dd><StatusBadge status={profile.status === 'healthy' ? 'succeeded' : 'pending'}>{profile.status || 'pending'}</StatusBadge></dd>
              <dt>机器</dt><dd>{machine?.name || profile.machine_id}</dd>
              <dt>规则数</dt><dd>{rules.length}</dd>
              <dt>Profile ID</dt><dd><code>{profile.id}</code></dd>
            </dl>
          </div>
        )}

        {tab === 'rules' && (
          <div className="profile-tab-panel">
          <DataTable
            rows={rules}
            empty="暂无转发规则，请在 NAT IX 机器上通过 ix 添加。"
            columns={[
              { key: 'id', title: '规则 ID', render: (r) => r.id || r.rule_id || '-' },
              { key: 'nat', title: '商家入口', render: (r) => r.nat_public_port || '-' },
              { key: 'transit', title: '中转端口', render: (r) => r.transit_port || '-' },
              { key: 'local', title: '客户端入口', render: (r) => r.local_port || '-' },
              { key: 'landing', title: '落地', render: (r) => `${r.landing_host || '-'}:${r.landing_port || '-'}` },
              { key: 'enabled', title: '状态', render: (r) => <StatusBadge status={r.enabled !== false ? 'active' : 'inactive'}>{r.enabled !== false ? '启用' : '禁用'}</StatusBadge> },
            ]}
          />
          </div>
        )}

        {tab === 'code' && (
          <div className="drawer-section profile-tab-panel">
            <p className="muted">接入码含组网密钥，仅用于公网入口机导入。展示内容为脱敏结果，完整码通过 Agent 任务获取。</p>
            <div className="code-block">
              <div className="code-title"><span>接入码</span><button className="small secondary" onClick={() => onRefreshCode(profile)} disabled={loading}>刷新接入码</button></div>
              <pre>{profile.code_redacted || '点击「刷新接入码」从 NAT IX 机器拉取（脱敏）'}</pre>
            </div>
          </div>
        )}

        {tab === 'portmap' && (
          <div className="drawer-section profile-tab-panel">
            <p className="muted">端口地图来自 Agent `ix_read_port_map` 任务结果。</p>
            <pre className="detail-box">{profile.port_map || '暂无端口地图，请先「同步」线路状态。'}</pre>
          </div>
        )}
      </Card>
    </div>
  );
}
