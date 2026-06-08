import { useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import { actionLabel, labelStatus, formatTime } from '../utils/format.js';

const roleLabel = { 'nat-transit': 'NAT IX', 'nat-ingress': '公网入口' };

export default function Diagnostics({ machines, tasks, onRunDiagnostics, onCopy, onRefresh, loading }) {
  const [selected, setSelected] = useState([]);
  const [lastBatch, setLastBatch] = useState(null);
  const ixDiagnosticTasks = tasks.filter((task) =>
    task.payload?.diagnostic_id && (task.action?.startsWith('ix_read_') || task.action?.startsWith('ix_write_'))
  );

  function toggleMachine(machineID) {
    setSelected((old) => old.includes(machineID) ? old.filter((item) => item !== machineID) : [...old, machineID]);
  }

  async function runDiagnostics() {
    const data = await onRunDiagnostics(selected);
    if (data?.diagnostic_id) {
      setLastBatch(data);
    }
  }

  const batchIDs = [...new Set(ixDiagnosticTasks.map((task) => task.payload?.diagnostic_id).filter(Boolean))].slice(-8).reverse();
  const batchTasks = lastBatch?.diagnostic_id
    ? ixDiagnosticTasks.filter((t) => t.payload?.diagnostic_id === lastBatch.diagnostic_id)
    : ixDiagnosticTasks.slice(0, 20);

  return (
    <div className="page-stack">
      <Card
        title="一键诊断 (v2)"
        description="对选定机器 enqueue ix_read_health + ix_read_diagnose 任务，结果通过 SSE/任务页查看。"
        actions={<><button className="secondary" onClick={onRefresh}>刷新任务</button><button onClick={runDiagnostics} disabled={loading}>{loading ? '运行中…' : '运行诊断'}</button></>}
      >
        <div className="form-grid drawer-form">
          <label className="wide-field">选择机器
            <div className="check-list">
              {machines.map((machine) => (
                <label key={machine.id} className="check">
                  <input type="checkbox" checked={selected.includes(machine.id)} onChange={() => toggleMachine(machine.id)} />
                  {machine.name} / {roleLabel[machine.role] || machine.role} / {labelStatus(machine.status)}
                </label>
              ))}
            </div>
          </label>
        </div>
        <p className="muted">不选择机器时，会对全部已注册机器创建诊断任务。</p>
      </Card>

      {batchIDs.length > 0 && (
        <Card title="历史诊断批次">
          <div className="button-grid">
            {batchIDs.map((id) => <button key={id} className="secondary" onClick={() => setLastBatch({ diagnostic_id: id })}>{id.slice(0, 12)}…</button>)}
          </div>
        </Card>
      )}

      <Card title="诊断任务">
        <DataTable
          rows={batchTasks}
          empty="暂无 ix 诊断任务。"
          columns={[
            { key: 'batch', title: '批次', render: (task) => String(task.payload?.diagnostic_id || '-').slice(0, 12) },
            { key: 'machine', title: '机器', render: (task) => task.payload?.machine_id || '-' },
            { key: 'action', title: '动作', render: (task) => actionLabel(task.action) || task.action },
            { key: 'status', title: '状态', render: (task) => <StatusBadge status={task.status}>{labelStatus(task.status)}</StatusBadge> },
            { key: 'time', title: '时间', render: (task) => formatTime(task.created_at) },
          ]}
        />
      </Card>

      {lastBatch && (
        <Card title="最近批次" actions={lastBatch.tasks ? <button className="secondary" onClick={() => onCopy(JSON.stringify(lastBatch, null, 2), '诊断批次')}>复制 JSON</button> : null}>
          <CodeBlock title="批次信息" value={lastBatch} onCopy={onCopy} />
        </Card>
      )}
    </div>
  );
}
