import { useMemo, useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import EmptyState from '../components/EmptyState.jsx';
import Modal from '../components/Modal.jsx';
import CopyModal from '../components/CopyModal.jsx';
import InstallWizardModal from '../components/InstallWizardModal.jsx';
import ConfirmDialog from '../components/ConfirmDialog.jsx';
import { useApp } from '../context/AppContext.jsx';
import { timeAgo } from '../utils/format.js';

const roleLabel = { 'nat-transit': 'NAT IX', 'nat-ingress': '公网入口' };
const emptyForm = { name: '', role: 'nat-transit' };

function formatBps(bps) {
  const n = Number(bps || 0);
  if (n <= 0) return '-';
  if (n < 1024) return `${n} B/s`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB/s`;
  return `${(n / 1024 / 1024).toFixed(1)} MB/s`;
}

function formatBytes(bytes) {
  const n = Number(bytes || 0);
  if (n <= 0) return '-';
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

function MetricBar({ label, value, max = 100, tone = 'blue' }) {
  const pct = Math.min(100, Math.max(0, (value / max) * 100));
  return (
    <div className="metric-bar">
      <div className="metric-bar-head">
        <span>{label}</span>
        <span>{value}{max === 100 ? '%' : ''}</span>
      </div>
      <div className="metric-bar-track">
        <div className={`metric-bar-fill ${tone}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

export default function Machines() {
  const {
    machines,
    nodeMap,
    loading,
    streamLive,
    refreshMachines,
    createMachine,
    installMachine,
    rotateMachineToken,
    handleCopyValue,
  } = useApp();

  const [createOpen, setCreateOpen] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [installWizard, setInstallWizard] = useState(null);
  const [tokenModal, setTokenModal] = useState(null);
  const [rotateTarget, setRotateTarget] = useState(null);

  const rows = useMemo(() => machines.map((m) => ({
    ...m,
    node: m.node_id ? nodeMap[m.node_id] : null,
  })), [machines, nodeMap]);

  async function submitCreate() {
    if (!form.name.trim()) return;
    const data = await createMachine({ name: form.name.trim(), role: form.role });
    setCreateOpen(false);
    setForm(emptyForm);
    if (data?.token) {
      setTokenModal({
        title: '机器凭证（仅显示一次）',
        description: '请立即复制保存，关闭后将无法再次查看完整 Token。',
        content: `# 机器凭证\nmachine_id=${data.id}\nEDGE_MACHINE_ID=${data.id}\nEDGE_CONTROLLER_TOKEN=${data.token}`,
      });
    }
  }

  async function showInstall(machine) {
    const data = await installMachine(machine);
    if (data?.root_command) {
      setInstallWizard({ machine, data });
    }
  }

  async function confirmRotate() {
    if (!rotateTarget) return;
    const data = await rotateMachineToken(rotateTarget);
    setRotateTarget(null);
    if (data?.token) {
      setTokenModal({
        title: '新 Token（仅显示一次）',
        description: `机器「${rotateTarget.name}」Token 已轮换，请更新 Agent 配置并重启。`,
        content: `# 新 Token\nmachine_id=${data.machine_id || rotateTarget.id}\nEDGE_MACHINE_ID=${data.machine_id || rotateTarget.id}\nEDGE_CONTROLLER_TOKEN=${data.token}`,
      });
    }
  }

  return (
    <div className="page-stack">
      <Card
        title="机器管理"
        description="NAT IX 中转机器与公网入口机。参考 flux-panel 节点页：Modal 安装命令 + 实时 Agent 状态。"
        actions={(
          <div className="head-actions">
            {streamLive ? <span className="live-pill">● 实时</span> : <span className="version-pill">轮询</span>}
            <button type="button" className="secondary" onClick={refreshMachines} disabled={loading}>{loading ? '刷新中' : '刷新'}</button>
          </div>
        )}
      >
        <div className="actions" style={{ marginBottom: '1rem' }}>
          <button type="button" onClick={() => { setForm({ name: 'nat-ix-1', role: 'nat-transit' }); setCreateOpen(true); }}>添加 NAT IX 机器</button>
          <button type="button" className="secondary" onClick={() => { setForm({ name: 'ingress-1', role: 'nat-ingress' }); setCreateOpen(true); }}>添加入口机器</button>
        </div>
        {!rows.length ? (
          <EmptyState
            title="还没有机器"
            description="添加 NAT IX 中转或公网入口机器，复制安装命令到服务器完成 Agent 注册。"
            action={(
              <>
                <button type="button" onClick={() => { setForm({ name: 'nat-ix-1', role: 'nat-transit' }); setCreateOpen(true); }}>添加 NAT IX 机器</button>
                <button type="button" className="secondary" onClick={() => { setForm({ name: 'ingress-1', role: 'nat-ingress' }); setCreateOpen(true); }}>添加入口机器</button>
              </>
            )}
          />
        ) : (
        <div className="table-scroll">
        <DataTable
          rows={rows}
          empty="暂无机器，请先添加。"
          columns={[
            { key: 'name', title: '名称', render: (m) => <div><strong>{m.name}</strong><small>{m.id}</small></div> },
            { key: 'role', title: '角色', render: (m) => roleLabel[m.role] || m.role },
            {
              key: 'status',
              title: '状态',
              render: (m) => (
                <div className="machine-status-cell">
                  <StatusBadge status={m.status === 'online' ? 'online' : m.status === 'offline' ? 'offline' : m.status === 'stale' ? 'stale' : 'waiting'}>
                    {m.status || 'pending'}
                  </StatusBadge>
                  {m.last_seen_at && <small>心跳 {timeAgo(m.last_seen_at)}</small>}
                </div>
              ),
            },
            {
              key: 'agent',
              title: 'Agent / 组网',
              render: (m) => {
                const node = m.node;
                if (!node) return <span className="muted">未注册</span>;
                return (
                  <div className="machine-metrics">
                    <small>{node.hostname || node.name} · {node.public_ip || node.observed_ip || '-'}</small>
                    {node.cpu_percent > 0 && (
                      <MetricBar label="CPU" value={Math.round(node.cpu_percent)} max={100} tone={node.cpu_percent > 85 ? 'yellow' : 'blue'} />
                    )}
                    {node.mem_percent > 0 && (
                      <MetricBar label="内存" value={Math.round(node.mem_percent)} max={100} tone={node.mem_percent > 85 ? 'yellow' : 'blue'} />
                    )}
                    <MetricBar label="Peer" value={Math.min(node.easytier_peer_count || 0, 10)} max={10} tone={node.easytier_network_ok ? 'green' : 'yellow'} />
                    {node.easytier_best_latency_ms > 0 && (
                      <small>延迟 {Math.round(node.easytier_best_latency_ms)} ms · {node.easytier_status || '-'}</small>
                    )}
                    {node.mem_total_mb > 0 && (
                      <small>{node.mem_used_mb || 0} / {node.mem_total_mb} MB</small>
                    )}
                    {(node.net_tx_bps > 0 || node.net_rx_bps > 0) && (
                      <small>↑ {formatBps(node.net_tx_bps)} · ↓ {formatBps(node.net_rx_bps)}</small>
                    )}
                    {(node.bytes_sent > 0 || node.bytes_received > 0) && (
                      <small className="muted">累计 ↑ {formatBytes(node.bytes_sent)} · ↓ {formatBytes(node.bytes_received)}</small>
                    )}
                  </div>
                );
              },
            },
            {
              key: 'ops',
              title: '操作',
              render: (m) => (
                <div className="row-actions">
                  <button type="button" className="small secondary" onClick={() => showInstall(m)} disabled={loading}>安装命令</button>
                  <button type="button" className="small secondary" onClick={() => setRotateTarget(m)} disabled={loading}>轮换 Token</button>
                </div>
              ),
            },
          ]}
        />
        </div>
        )}
      </Card>

      <Modal
        open={createOpen}
        title="添加机器"
        description="创建后将生成一次性 Agent Token。"
        onClose={() => setCreateOpen(false)}
        footer={(
          <div className="actions right">
            <button type="button" className="secondary" onClick={() => setCreateOpen(false)}>取消</button>
            <button type="button" onClick={submitCreate} disabled={loading || !form.name.trim()}>创建</button>
          </div>
        )}
      >
        <div className="form-grid drawer-form">
          <label>
            机器名称
            <input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} placeholder="nat-ix-1" />
          </label>
          <label>
            角色
            <select value={form.role} onChange={(e) => setForm((f) => ({ ...f, role: e.target.value }))}>
              <option value="nat-transit">NAT IX 中转</option>
              <option value="nat-ingress">公网入口</option>
            </select>
          </label>
        </div>
      </Modal>

      <InstallWizardModal
        open={!!installWizard}
        machine={installWizard?.machine}
        installData={installWizard?.data}
        liveMachine={installWizard?.machine ? machines.find((m) => m.id === installWizard.machine.id) : null}
        loading={loading}
        onClose={() => setInstallWizard(null)}
        onCopy={handleCopyValue}
        onRefresh={refreshMachines}
      />

      <CopyModal
        open={!!tokenModal}
        title={tokenModal?.title || ''}
        description={tokenModal?.description || ''}
        content={tokenModal?.content || ''}
        onClose={() => setTokenModal(null)}
        onCopy={(text) => handleCopyValue(text, 'Token')}
      />

      <ConfirmDialog
        open={!!rotateTarget}
        title="轮换 Agent Token"
        message={rotateTarget ? `确认轮换「${rotateTarget.name}」的 Token？\n旧 Token 将立即失效，需更新 Agent 配置并重启。` : ''}
        confirmText="确认轮换"
        danger
        onConfirm={confirmRotate}
        onClose={() => setRotateTarget(null)}
      />
    </div>
  );
}
