import { useState } from 'react';
import Card from '../components/Card.jsx';

const steps = ['选择机器', 'NAT/落地', '预览创建'];

export default function CreateProfileWizard({ open, machines, onClose, onSubmit, loading }) {
  const [step, setStep] = useState(0);
  const [form, setForm] = useState({
    machine_id: '',
    name: 'ix-line-1',
    nat_host: '',
    nat_port: '',
    landing_host: '',
    landing_port: '',
    network_name: 'ix-net-1',
    cidr: '10.144.0.0/16',
  });

  if (!open) return null;

  const natMachines = machines.filter((m) => m.role === 'nat-transit');
  const selected = machines.find((m) => m.id === form.machine_id);

  function update(key, value) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function stepError(current) {
    if (current === 0 && !form.machine_id) return '请选择 NAT IX 机器';
    if (current === 1) {
      if (!form.landing_host.trim()) return '请填写落地地址';
      if (!form.nat_host.trim()) return '请填写商家 NAT 地址';
    }
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
      role: 'nat-transit',
      config: {
        NAT_PUBLIC_HOST: form.nat_host,
        NAT_PUBLIC_PORT: Number(form.nat_port || 0) || undefined,
        LANDING_HOST: form.landing_host,
        LANDING_PORT: Number(form.landing_port || 0) || undefined,
        NETWORK_NAME: form.network_name,
        CIDR: form.cidr,
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
          title="创建 NAT IX 线路"
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
              <label className="wide-field">目标机器
                <select value={form.machine_id} onChange={(e) => update('machine_id', e.target.value)}>
                  <option value="">请选择 NAT IX 机器</option>
                  {natMachines.map((m) => <option key={m.id} value={m.id}>{m.name} ({m.status})</option>)}
                </select>
              </label>
              <label>线路名称<input value={form.name} onChange={(e) => update('name', e.target.value)} /></label>
            </div>
          )}

          {step === 1 && (
            <div className="form-grid drawer-form">
              <label>商家 NAT 地址<input value={form.nat_host} onChange={(e) => update('nat_host', e.target.value)} placeholder="nat.example.com" /></label>
              <label>商家 NAT 端口<input value={form.nat_port} onChange={(e) => update('nat_port', e.target.value)} placeholder="20000" /></label>
              <label>落地地址<input value={form.landing_host} onChange={(e) => update('landing_host', e.target.value)} placeholder="1.2.3.4" /></label>
              <label>落地端口<input value={form.landing_port} onChange={(e) => update('landing_port', e.target.value)} placeholder="50000" /></label>
              <label>组网名称<input value={form.network_name} onChange={(e) => update('network_name', e.target.value)} /></label>
              <label>CIDR<input value={form.cidr} onChange={(e) => update('cidr', e.target.value)} /></label>
            </div>
          )}

          {step === 2 && (
            <div className="drawer-section">
              <dl className="kv-grid">
                <dt>机器</dt><dd>{selected?.name || form.machine_id || '—'}</dd>
                <dt>线路</dt><dd>{form.name}</dd>
                <dt>NAT</dt><dd>{form.nat_host || '—'}:{form.nat_port || '—'}</dd>
                <dt>落地</dt><dd>{form.landing_host || '—'}:{form.landing_port || '—'}</dd>
                <dt>组网</dt><dd>{form.network_name} / {form.cidr}</dd>
              </dl>
            </div>
          )}

          <div className="actions wizard-actions">
            {step > 0 && <button className="secondary" onClick={() => setStep((s) => s - 1)} disabled={loading}>上一步</button>}
            {step < steps.length - 1 && (
              <button onClick={nextStep} disabled={loading}>下一步</button>
            )}
            {step === steps.length - 1 && (
              <button onClick={submit} disabled={loading || !form.machine_id}>{loading ? '创建中…' : '创建并应用'}</button>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
