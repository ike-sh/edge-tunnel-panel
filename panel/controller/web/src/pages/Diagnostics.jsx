import { useState } from 'react';
import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import { actionLabel, labelStatus, nodeLabel, pretty } from '../utils/format.js';

export default function Diagnostics({ nodes, tasks, onRunDiagnostics, onGetDiagnostics, onCopy, onRefresh }) {
  const [selected, setSelected] = useState([]);
  const [report, setReport] = useState(null);
  const diagnosticTasks = tasks.filter((task) => task.payload?.diagnostic_id);

  function toggleNode(nodeID) {
    setSelected((old) => old.includes(nodeID) ? old.filter((item) => item !== nodeID) : [...old, nodeID]);
  }

  async function runDiagnostics() {
    const data = await onRunDiagnostics(selected);
    if (data?.diagnostic_id) {
      setReport(data);
    }
  }

  async function loadReport(id) {
    const data = await onGetDiagnostics(id);
    if (data) setReport(data);
  }

  const latestIDs = [...new Set(diagnosticTasks.map((task) => task.payload?.diagnostic_id).filter(Boolean))].slice(-8).reverse();

  return (
    <div className="page-stack">
      <Card
        title="一键诊断"
        description="收集 Controller、节点、EasyTier、nftables、PBR、MSS/MTU 和最近失败任务，生成可复制的诊断报告。"
        actions={<><button className="secondary" onClick={onRefresh}>刷新任务</button><button onClick={runDiagnostics}>运行诊断</button></>}
      >
        <div className="form-grid drawer-form">
          <label className="wide-field">选择节点
            <div className="check-list">
              {nodes.map((node) => (
                <label key={node.id} className="check">
                  <input type="checkbox" checked={selected.includes(node.id)} onChange={() => toggleNode(node.id)} />
                  {node.name || node.id} / {labelStatus(node.status)}
                </label>
              ))}
            </div>
          </label>
        </div>
        <p className="muted">不选择节点时，会对全部节点创建只读诊断任务。</p>
      </Card>

      {latestIDs.length > 0 && (
        <Card title="历史诊断批次">
          <div className="button-grid">
            {latestIDs.map((id) => <button key={id} className="secondary" onClick={() => loadReport(id)}>{id}</button>)}
          </div>
        </Card>
      )}

      <Card title="诊断任务">
        <DataTable
          rows={diagnosticTasks.slice(0, 80)}
          empty="暂无诊断任务。"
          columns={[
            { key: 'id', title: '批次', render: (task) => task.payload?.diagnostic_id || '-' },
            { key: 'node', title: '节点', render: (task) => nodeLabel(nodes.find((node) => node.id === task.node_id)) },
            { key: 'action', title: '动作', render: (task) => actionLabel(task.action) },
            { key: 'status', title: '状态', render: (task) => <StatusBadge status={task.status}>{labelStatus(task.status)}</StatusBadge> },
            { key: 'error', title: '摘要', render: (task) => task.error || '-' },
          ]}
        />
      </Card>

      {report && (
        <Card title="诊断报告" actions={<button className="secondary" onClick={() => onCopy(report.markdown || pretty(report), '诊断报告')}>复制报告</button>}>
          <CodeBlock title="Markdown 报告" value={report.markdown || pretty(report)} onCopy={onCopy} />
        </Card>
      )}
    </div>
  );
}
