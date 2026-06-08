import { useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import Modal from '../components/Modal.jsx';
import ConfirmDialog from '../components/ConfirmDialog.jsx';

const roleLabel = { 'nat-transit': 'NAT IX 线路', 'nat-ingress': '公网入口线路' };

const emptyRule = {
  nat_public_port: '',
  transit_port: '',
  local_port: '',
  landing_host: '',
  landing_port: '',
  remark: '',
  enabled: true,
};

function ruleFromForm(form, profileId, existing) {
  return {
    id: existing?.id || existing?.rule_id || `rule-${Date.now()}`,
    profile_id: profileId,
    nat_public_port: Number(form.nat_public_port) || 0,
    transit_port: Number(form.transit_port) || 0,
    local_port: Number(form.local_port) || 0,
    landing_host: form.landing_host.trim(),
    landing_port: Number(form.landing_port) || 0,
    remark: form.remark.trim(),
    enabled: form.enabled !== false,
  };
}

function formFromRule(rule) {
  return {
    nat_public_port: rule.nat_public_port || '',
    transit_port: rule.transit_port || '',
    local_port: rule.local_port || '',
    landing_host: rule.landing_host || '',
    landing_port: rule.landing_port || '',
    remark: rule.remark || '',
    enabled: rule.enabled !== false,
  };
}

export default function ProfileDetail({
  profile,
  machine,
  pendingTaskIds = [],
  onBack,
  onApply,
  onSync,
  onRefreshCode,
  onSaveRules,
  loading,
}) {
  const [tab, setTab] = useState('overview');
  const [ruleModal, setRuleModal] = useState(null);
  const [deleteRule, setDeleteRule] = useState(null);
  const [ruleForm, setRuleForm] = useState(emptyRule);

  if (!profile) return null;

  const rules = profile.rules || [];
  const syncing = pendingTaskIds.length > 0;

  function openAddRule() {
    const cfg = profile.config || {};
    setRuleForm({
      ...emptyRule,
      landing_host: cfg.LANDING_HOST || '',
      landing_port: cfg.LANDING_PORT || '',
      transit_port: cfg.TRANSIT_PORT || cfg.NAT_PUBLIC_PORT || '',
    });
    setRuleModal({ mode: 'add' });
  }

  function openEditRule(rule) {
    setRuleForm(formFromRule(rule));
    setRuleModal({ mode: 'edit', rule });
  }

  async function submitRule() {
    const next = ruleModal.mode === 'edit'
      ? rules.map((r) => ((r.id || r.rule_id) === (ruleModal.rule.id || ruleModal.rule.rule_id) ? ruleFromForm(ruleForm, profile.id, ruleModal.rule) : r))
      : [...rules, ruleFromForm(ruleForm, profile.id)];
    setRuleModal(null);
    await onSaveRules(profile, next);
  }

  async function confirmDeleteRule() {
    const id = deleteRule.id || deleteRule.rule_id;
    const next = rules.filter((r) => (r.id || r.rule_id) !== id);
    setDeleteRule(null);
    await onSaveRules(profile, next);
  }

  return (
    <div className="page-stack">
      <Card
        title={profile.name}
        description={`${roleLabel[profile.role] || profile.role} · ${machine?.name || profile.machine_id}`}
        actions={(
          <div className="head-actions">
            <button type="button" className="secondary small" onClick={onBack}>返回列表</button>
            <button type="button" className="secondary small" onClick={() => onSync(profile)} disabled={loading || syncing}>{syncing ? '同步中…' : '同步'}</button>
            <button type="button" className="small" onClick={() => onApply(profile)} disabled={loading || syncing}>应用</button>
          </div>
        )}
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
            <div className="actions" style={{ marginBottom: '0.75rem' }}>
              <button type="button" onClick={openAddRule} disabled={loading}>添加规则</button>
              <button type="button" className="secondary" onClick={() => onSync(profile)} disabled={loading}>从机器同步</button>
            </div>
            <DataTable
              rows={rules}
              empty="暂无转发规则，点击「添加规则」或「从机器同步」。"
              columns={[
                { key: 'id', title: '规则 ID', render: (r) => r.id || r.rule_id || '-' },
                { key: 'nat', title: '商家入口', render: (r) => r.nat_public_port || '-' },
                { key: 'transit', title: '中转端口', render: (r) => r.transit_port || '-' },
                { key: 'local', title: '客户端入口', render: (r) => r.local_port || '-' },
                { key: 'landing', title: '落地', render: (r) => `${r.landing_host || '-'}:${r.landing_port || '-'}` },
                { key: 'enabled', title: '状态', render: (r) => <StatusBadge status={r.enabled !== false ? 'active' : 'inactive'}>{r.enabled !== false ? '启用' : '禁用'}</StatusBadge> },
                {
                  key: 'ops',
                  title: '操作',
                  render: (r) => (
                    <div className="row-actions">
                      <button type="button" className="small secondary" onClick={() => openEditRule(r)}>编辑</button>
                      <button type="button" className="small danger" onClick={() => setDeleteRule(r)}>删除</button>
                    </div>
                  ),
                },
              ]}
            />
          </div>
        )}

        {tab === 'code' && (
          <div className="drawer-section profile-tab-panel">
            <p className="muted">接入码含组网密钥，仅用于公网入口机导入。展示内容为脱敏结果，完整码通过 Agent 任务获取。</p>
            <div className="code-block">
              <div className="code-title"><span>接入码</span><button type="button" className="small secondary" onClick={() => onRefreshCode(profile)} disabled={loading}>刷新接入码</button></div>
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

      <Modal
        open={!!ruleModal}
        title={ruleModal?.mode === 'edit' ? '编辑转发规则' : '添加转发规则'}
        description="参考 flux-panel 转发 CRUD，保存后将 enqueue ix_write_apply_rules。"
        onClose={() => setRuleModal(null)}
        wide
        footer={(
          <div className="actions right">
            <button type="button" className="secondary" onClick={() => setRuleModal(null)}>取消</button>
            <button type="button" onClick={submitRule} disabled={loading}>保存并应用</button>
          </div>
        )}
      >
        <div className="form-grid drawer-form">
          <label>商家 NAT 端口<input type="number" value={ruleForm.nat_public_port} onChange={(e) => setRuleForm((f) => ({ ...f, nat_public_port: e.target.value }))} /></label>
          <label>中转端口<input type="number" value={ruleForm.transit_port} onChange={(e) => setRuleForm((f) => ({ ...f, transit_port: e.target.value }))} /></label>
          <label>客户端入口端口<input type="number" value={ruleForm.local_port} onChange={(e) => setRuleForm((f) => ({ ...f, local_port: e.target.value }))} /></label>
          <label>落地地址<input value={ruleForm.landing_host} onChange={(e) => setRuleForm((f) => ({ ...f, landing_host: e.target.value }))} /></label>
          <label>落地端口<input type="number" value={ruleForm.landing_port} onChange={(e) => setRuleForm((f) => ({ ...f, landing_port: e.target.value }))} /></label>
          <label>备注<input value={ruleForm.remark} onChange={(e) => setRuleForm((f) => ({ ...f, remark: e.target.value }))} /></label>
          <label className="check"><input type="checkbox" checked={ruleForm.enabled !== false} onChange={(e) => setRuleForm((f) => ({ ...f, enabled: e.target.checked }))} />启用</label>
        </div>
      </Modal>

      <ConfirmDialog
        open={!!deleteRule}
        title="删除规则"
        message="确认删除该转发规则？保存后将重新应用 nft 规则集。"
        confirmText="删除"
        danger
        onConfirm={confirmDeleteRule}
        onClose={() => setDeleteRule(null)}
      />
    </div>
  );
}
