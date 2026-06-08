import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

function formatBps(bps) {
  const n = Number(bps || 0);
  if (n <= 0) return '0 B/s';
  if (n < 1024) return `${n} B/s`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB/s`;
  return `${(n / 1024 / 1024).toFixed(1)} MB/s`;
}

export default function DashboardCharts({ taskTrend, healthBars, failedRecent, netTraffic }) {
  const { totalTx = 0, totalRx = 0, perNode = [] } = netTraffic || {};

  return (
    <>
      <div className="two-column">
        <div className="panel-card chart-card">
          <div className="panel-head">
            <div>
              <h2>任务趋势</h2>
              <p className="muted">近 7 日 ix 任务成功/失败</p>
            </div>
          </div>
          <div className="chart-wrap">
            {taskTrend.length ? (
              <ResponsiveContainer width="100%" height={220}>
                <AreaChart data={taskTrend}>
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--table-border)" />
                  <XAxis dataKey="day" tick={{ fill: 'var(--text-secondary)', fontSize: 12 }} />
                  <YAxis allowDecimals={false} tick={{ fill: 'var(--text-secondary)', fontSize: 12 }} />
                  <Tooltip contentStyle={{ background: 'var(--glass-bg-strong)', border: '1px solid var(--glass-border)' }} />
                  <Area type="monotone" dataKey="ok" stackId="1" stroke="var(--mac-green)" fill="rgba(52, 199, 89, 0.25)" name="成功" />
                  <Area type="monotone" dataKey="fail" stackId="1" stroke="var(--mac-red)" fill="rgba(255, 59, 48, 0.2)" name="失败" />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <p className="muted chart-empty">暂无任务数据，创建线路后将自动生成趋势。</p>
            )}
          </div>
        </div>
        <div className="panel-card chart-card">
          <div className="panel-head">
            <div>
              <h2>资源概览</h2>
              <p className="muted">线路与机器健康分布</p>
            </div>
          </div>
          <div className="health-bars">
            {healthBars.map((item) => (
              <div key={item.name} className="health-bar-row">
                <span>{item.name}</span>
                <div className="health-bar-track">
                  <div className="health-bar-fill" style={{ width: `${Math.min(item.value * 20, 100)}%`, background: item.fill }} />
                </div>
                <strong>{item.value}</strong>
              </div>
            ))}
          </div>
          {failedRecent.length > 0 && (
            <div className="alert error compact-alert">
              最近 {failedRecent.length} 条任务失败，请前往任务页或诊断页排查。
            </div>
          )}
        </div>
      </div>

      <div className="panel-card chart-card net-chart-card">
        <div className="panel-head">
          <div>
            <h2>网络流量</h2>
            <p className="muted">在线节点实时速率（WS 推送，参考 flux 节点页）</p>
          </div>
          <div className="net-total-pills">
            <span className="version-pill">↑ {formatBps(totalTx)}</span>
            <span className="version-pill">↓ {formatBps(totalRx)}</span>
          </div>
        </div>
        <div className="chart-wrap">
          {perNode.length ? (
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={perNode} layout="vertical" margin={{ left: 8, right: 16 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--table-border)" />
                <XAxis type="number" tick={{ fill: 'var(--text-secondary)', fontSize: 11 }} tickFormatter={(v) => formatBps(v)} />
                <YAxis type="category" dataKey="name" width={88} tick={{ fill: 'var(--text-secondary)', fontSize: 11 }} />
                <Tooltip formatter={(v) => formatBps(v)} contentStyle={{ background: 'var(--glass-bg-strong)', border: '1px solid var(--glass-border)' }} />
                <Bar dataKey="tx" fill="var(--mac-blue)" name="上行" radius={[0, 4, 4, 0]} />
                <Bar dataKey="rx" fill="var(--mac-green)" name="下行" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <p className="muted chart-empty">暂无流量数据，Agent 第二次 heartbeat 后开始显示速率。</p>
          )}
        </div>
      </div>
    </>
  );
}
