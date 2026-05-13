import Card from '../components/Card.jsx';
import DataTable from '../components/DataTable.jsx';
import StatusBadge from '../components/StatusBadge.jsx';
import EmptyState from '../components/EmptyState.jsx';
import CodeBlock from '../components/CodeBlock.jsx';
import { labelStatus, nodeLabel, publicIP, ruleListenPort, ruleLandingPort, safeList, pretty } from '../utils/format.js';

export default function PBR({ nodes, forwards, pbrPolicies, pbrForm, setPBRForm, nodeMap, routeGroups, routeDetection, selectedNodeID, selectedGroup, availableForwards, canApply, onDetectRouteGroups, onDetectInterfaces, onSelectRouteGroup, onCreatePBR, onApplyPBR, onVerifyPBR, onDisablePBR, onDeletePBR, onRefresh, onCopy }) {
  return (
    <div className="page-stack">
      <Card
        title="出口策略 / PBR"
        description="为 B 落地执行节点上的转发流量选择出口线路。先识别节点线路组，再选择线路并应用策略。"
        actions={<button className="secondary" onClick={onRefresh}>刷新</button>}
      >
        <div className="form-grid drawer-form">
          <label>选择节点<select value={selectedNodeID} onChange={(event) => setPBRForm({ ...pbrForm, node_id: event.target.value, forward_rule_id: '', route_group_name: '', route_group_gateway: '', route_group_table_id: '', route_group_table_name: '', route_group_matched_ip: '' })}><option value="">请选择 B 落地节点</option>{nodes.map((node) => <option key={node.id} value={node.id}>{node.name || node.id} / {publicIP(node)} / {node.easytier_ip || '-'} / {labelStatus(node.status)}</option>)}</select></label>
          <label>关联转发规则<select value={pbrForm.forward_rule_id} onChange={(event) => { const rule = forwards.find((item) => item.id === event.target.value); setPBRForm({ ...pbrForm, forward_rule_id: event.target.value, node_id: rule?.landing_node_id || rule?.backend_node_id || selectedNodeID, name: pbrForm.name || `pbr-${pbrForm.route_group_name || 'line'}-${rule?.name || 'forward'}` }); }}><option value="">请选择转发规则</option>{availableForwards.map((rule) => <option key={rule.id} value={rule.id}>{rule.name} / {nodeLabel(nodeMap[rule.landing_node_id || rule.backend_node_id])} / {ruleListenPort(rule)}→{ruleLandingPort(rule)}</option>)}</select></label>
          <label>策略名称<input value={pbrForm.name} onChange={(event) => setPBRForm({ ...pbrForm, name: event.target.value })} placeholder="pbr-CN2-forward" /></label>
          <label className="check"><input type="checkbox" checked={pbrForm.enabled} onChange={(event) => setPBRForm({ ...pbrForm, enabled: event.target.checked })} />启用策略</label>
        </div>
        <div className="actions">
          <button className="secondary" onClick={() => onDetectRouteGroups(selectedNodeID)}>识别出口线路</button>
          <button className="secondary" onClick={() => onDetectInterfaces(selectedNodeID)}>识别网卡</button>
        </div>
        {selectedNodeID && routeGroups.length > 0 && (
          <div className="route-group-grid">
            {routeGroups.map((group) => (
              <button key={group.name} className={`route-group-card ${pbrForm.route_group_name === group.name ? 'selected' : ''}`} onClick={() => onSelectRouteGroup(group)}>
                <strong>{group.name}</strong>
                <span>网关 {group.gateway}</span>
                <span>表 {group.table_name}</span>
                <span>匹配 {group.matched_ip}</span>
              </button>
            ))}
          </div>
        )}
        {selectedNodeID && routeGroups.length === 0 && safeList(routeDetection.warnings).length > 0 && (
          <div className="alert warning">当前节点未检测到可用多出口线路组。PBR 仅适合具备 10.7/10.8/10.3/10.4 等线路地址的多出口节点。</div>
        )}
        {selectedGroup && (
          <details className="detail-box">
            <summary>高级参数</summary>
            <dl className="kv-grid">
              <dt>线路</dt><dd>{selectedGroup.name}</dd>
              <dt>网关</dt><dd>{selectedGroup.gateway}</dd>
              <dt>table_id</dt><dd>{selectedGroup.table_id}</dd>
              <dt>table_name</dt><dd>{selectedGroup.table_name}</dd>
              <dt>priority / fwmark</dt><dd>由 Controller 自动生成</dd>
              <dt>match_port</dt><dd>从关联转发规则自动生成</dd>
            </dl>
          </details>
        )}
        <div className="actions">
          <button disabled={!canApply} onClick={() => onCreatePBR(false)}>创建策略</button>
          <button disabled={!canApply} onClick={() => onCreatePBR(true)}>创建并应用策略</button>
        </div>
      </Card>

      <Card title="策略列表" description="当前版本每个节点只支持一条启用中的 PBR 策略。">
        {pbrPolicies.length === 0 ? <EmptyState title="暂无出口策略" description="先选择 B 落地节点并识别出口线路。" /> : (
          <DataTable
            rows={pbrPolicies}
            columns={[
              { key: 'name', title: '策略名', render: (policy) => <strong>{policy.name}</strong> },
              { key: 'node', title: '节点', render: (policy) => nodeLabel(nodeMap[policy.node_id]) },
              { key: 'forward', title: '转发规则', render: (policy) => forwards.find((rule) => rule.id === policy.forward_rule_id)?.name || policy.forward_rule_id || '-' },
              { key: 'group', title: '线路组', render: (policy) => policy.route_group_name || '-' },
              { key: 'route', title: '网关/表', render: (policy) => `${policy.route_group_gateway || '-'} / ${policy.route_group_table_name || '-'}` },
              { key: 'status', title: '状态', render: (policy) => <StatusBadge status={policy.status}>{labelStatus(policy.status)}</StatusBadge> },
              { key: 'actions', title: '操作', render: (policy) => <div className="row-actions"><button className="small" onClick={() => onApplyPBR(policy)}>应用</button><button className="secondary small" onClick={() => onVerifyPBR(policy)}>验证</button><button className="secondary small" onClick={() => onDisablePBR(policy)}>禁用</button><button className="danger small" onClick={() => onDeletePBR(policy)}>删除</button></div> },
            ]}
          />
        )}
      </Card>

      <details className="detail-box muted-box">
        <summary>最近线路识别结果</summary>
        <CodeBlock title="detect_pbr_route_groups" value={pretty(routeDetection)} onCopy={onCopy} />
      </details>
    </div>
  );
}
