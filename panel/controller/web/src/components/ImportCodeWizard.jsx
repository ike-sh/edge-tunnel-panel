import { useState } from 'react';
import Card from '../components/Card.jsx';

const steps = ['选择入口机', '粘贴接入码', '端口映射', '确认导入'];

export default function ImportCodeWizard({ open, machines, onClose, onSubmit, loading }) {
  const [step, setStep] = useState(0);
  const [form, setForm] = useState({
    machine_id: '',
    name: 'ingress-1',
    code: '',
    local_port: '30000',
  });

  if (!open) return null;

  const ingressMachines = machines.filter((m) => m.role === 'nat-ingress');
  const selected = machines.find((m) => m.id === form.machine_id);

  function update(key, value) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function stepError(current) {
    if (current === 0 && !form.machine_id) return '请选择公网入口机器';
    if (current === 1 && !form.code.trim()) return '请粘贴接入码';
    if (current === 2 && !form.local_port.trim()) return '请填写客户端入口端口';
    return '';
  }

  function nextStep() {
    const err = stepError(step);
    if (err) return;
    setStep((s) => s + 1);
  }

  async function submit() {
    const ok = await onSubmit({
      name: form.name,
      machine_id: form.machine_id,
      role: 'nat-ingress',
      code: form.code.trim(),
      config: {
        LOCAL_PORT: Number(form.local_port || 0) || undefined,
      },
    });
    if (ok) {
      setStep(0);
      onClose();
    }
  }

  return (
    <div className="wizard-overlay" onClick={onClose}>
      <div className="wizard-panel" onClick={(e) => e.stopPropagation()}>
        <Card
          title="导入接入码"
          description={`步骤 ${step + 1}/${steps.length}：${steps[step]}`}
          actions={<button className="secondary small" onClick={onClose}>关闭</button>}
        >
          <div className="wizard-steps">
            {steps.map((label, i) => (
              <span key={label} className={`wizard-step ${i === step ? 'active' : i < step ? 'done' : ''}`}>
                <span className="wizard-step-num">{i + 1}</span>{label}
              </span>
            ))}
          </div>
          {stepError(step) && <p className="wizard-error">{stepError(step)}</p>}

          {step === 0 && (
            <div className="form-grid drawer-form">
              <label className="wide-field">公网入口机器
                <select value={form.machine_id} onChange={(e) => update('machine_id', e.target.value)}>
                  <option value="">请选择入口机器</option>
                  {ingressMachines.map((m) => <option key={m.id} value={m.id}>{m.name} ({m.status})</option>)}
                </select>
              </label>
              <label>线路名称<input value={form.name} onChange={(e) => update('name', e.target.value)} /></label>
            </div>
          )}

          {step === 1 && (
            <label className="wide-field">接入码
              <textarea rows={8} value={form.code} onChange={(e) => update('code', e.target.value)} placeholder="IXTF1:..." />
            </label>
          )}

          {step === 2 && (
            <div className="form-grid drawer-form">
              <label>客户端入口端口<input value={form.local_port} onChange={(e) => update('local_port', e.target.value)} placeholder="30000" /></label>
            </div>
          )}

          {step === 3 && (
            <div className="drawer-section">
              <dl className="kv-grid">
                <dt>机器</dt><dd>{selected?.name || '—'}</dd>
                <dt>线路</dt><dd>{form.name}</dd>
                <dt>入口端口</dt><dd>{form.local_port || '—'}</dd>
                <dt>接入码</dt><dd><code>{form.code ? `${form.code.slice(0, 24)}…` : '—'}</code></dd>
              </dl>
            </div>
          )}

          <div className="actions wizard-actions">
            {step > 0 && <button className="secondary" onClick={() => setStep((s) => s - 1)} disabled={loading}>上一步</button>}
            {step < steps.length - 1 && (
              <button onClick={nextStep} disabled={loading}>下一步</button>
            )}
            {step === steps.length - 1 && (
              <button onClick={submit} disabled={loading || !form.machine_id || !form.code.trim()}>{loading ? '导入中…' : '导入并应用'}</button>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
