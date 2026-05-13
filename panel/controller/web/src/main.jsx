import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';
import { API_BASE_KEY, TOKEN_KEY, createApiClient } from './api.js';
import Layout from './components/Layout.jsx';
import Card from './components/Card.jsx';
import Dashboard from './pages/Dashboard.jsx';
import Nodes from './pages/Nodes.jsx';
import NetworkLinks from './pages/NetworkLinks.jsx';
import Forwards from './pages/Forwards.jsx';
import PBR from './pages/PBR.jsx';
import Diagnostics from './pages/Diagnostics.jsx';
import Tasks from './pages/Tasks.jsx';
import Settings from './pages/Settings.jsx';
import { copyText } from './utils/copy.js';
import { browserControllerURL } from './utils/validators.js';
import {
  DEFAULT_VERSION,
  tabs,
  actionLabel,
  safeList,
  lines,
  parseJSON,
  linkOptionLabel,
  publicIP,
  ruleListenPort,
  ruleLandingPort,
} from './utils/format.js';

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || '');
  const [apiBase, setApiBase] = useState(() => localStorage.getItem(API_BASE_KEY) || '');
  const [alert, setAlert] = useState(null);
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState(null);
  const [nodes, setNodes] = useState([]);
  const [tasks, setTasks] = useState([]);
  const [networkLinks, setNetworkLinks] = useState([]);
  const [networkProfiles, setNetworkProfiles] = useState([]);
  const [forwards, setForwards] = useState([]);
  const [pbrPolicies, setPBRPolicies] = useState([]);
  const [agentForm, setAgentForm] = useState({ controller_url: browserControllerURL(), node_name: 'edge-node-1', version: DEFAULT_VERSION, enable_tasks: true, enable_write_actions: true, download_source: 'official', github_mirrors: 'https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/' });
  const [agentCommand, setAgentCommand] = useState({ root: '', sudo: '', mirrorRoots: [], mirrorSudos: [] });
  const [quickForm, setQuickForm] = useState({ link_type: 'easytier', name: 'edge-net', network_name: 'edge-net', network_secret: '', cidr: '10.144.0.0/16', port: 11010, mtu: 1380, mss_clamp_enabled: true, mss_mode: 'auto', mss_value: '', entry_node_id: '', backend_node_id: '', landing_reachable_host: '', tcp: true, udp: true, showAdvanced: false, listeners: 'tcp://0.0.0.0:11010\nudp://0.0.0.0:11010', peers: '' });
  const [forwardForm, setForwardForm] = useState({ network_link_id: '', name: '', protocol: 'tcp', public_listen_port: '', landing_host: '', landing_port: '', transport_mode: 'easytier', enabled: true, remark: '' });
  const [pbrForm, setPBRForm] = useState({ node_id: '', forward_rule_id: '', name: '', route_group_name: '', route_group_gateway: '', route_group_table_id: '', route_group_table_name: '', route_group_matched_ip: '', source_type: 'forward', enabled: true });
  const [taskFilter, setTaskFilter] = useState('all');
  const [taskNodeFilter, setTaskNodeFilter] = useState('all');
  const [taskEasyTierOnly, setTaskEasyTierOnly] = useState(false);

  const api = useMemo(() => createApiClient({ apiBase, token }), [apiBase, token]);
  const strictAuth = health?.strict_auth !== false;
  const nodeMap = useMemo(() => Object.fromEntries(nodes.map((node) => [node.id, node])), [nodes]);
  const stats = useMemo(() => ({
    online: nodes.filter((node) => node.status === 'online').length,
    stale: nodes.filter((node) => node.status === 'stale').length,
    offline: nodes.filter((node) => node.status === 'offline').length,
    failed: tasks.filter((task) => task.status === 'failed').length,
  }), [nodes, tasks]);

  async function run(label, fn) {
    setLoading(true);
    setAlert(null);
    try {
      const result = await fn();
      setAlert({ type: 'success', message: `${label}成功` });
      return result;
    } catch (error) {
      setAlert({ type: 'error', message: error.message || String(error) });
      return null;
    } finally {
      setLoading(false);
    }
  }

  async function refreshHealth() { const data = await api('/health'); setHealth(data); return data; }
  async function refreshNodes() { const data = safeList(await api('/nodes')); setNodes(data); return data; }
  async function refreshTasks() { const data = safeList(await api('/tasks')); setTasks(data); return data; }
  async function refreshNetworkLinks() { const data = safeList(await api('/network-links')); setNetworkLinks(data); return data; }
  async function refreshNetworkProfiles() { const data = safeList(await api('/network-profiles')); setNetworkProfiles(data); return data; }
  async function refreshForwards() { const data = safeList(await api('/forwards')); setForwards(data); return data; }
  async function refreshPBRPolicies() { const data = safeList(await api('/pbr-policies')); setPBRPolicies(data); return data; }

  async function refreshAll() {
    const h = await refreshHealth();
    if (token || h.strict_auth === false) {
      await Promise.all([refreshNodes(), refreshTasks(), refreshNetworkLinks(), refreshNetworkProfiles(), refreshForwards(), refreshPBRPolicies()]);
    }
  }

  useEffect(() => { run('加载数据', refreshAll); }, []);
  useEffect(() => {
    const timer = window.setInterval(() => refreshNodes().catch(() => {}), 15000);
    return () => window.clearInterval(timer);
  }, [apiBase, token]);

  async function handleCopyValue(text, title = '内容') {
    const ok = await copyText(text);
    setAlert(ok ? { type: 'success', message: `已复制 ${title}` } : { type: 'error', message: '复制失败，请手动复制' });
  }

  async function generateAgentCommand() {
    const data = await run('生成一键命令', async () => api('/bootstrap/agent-install-command', {
      body: {
        controller_url: agentForm.controller_url,
        node_name: agentForm.node_name,
        version: agentForm.version || DEFAULT_VERSION,
        role: 'node',
        enable_tasks: agentForm.enable_tasks,
        enable_write_actions: agentForm.enable_write_actions,
        show_full_token: true,
        download_source: agentForm.download_source,
        github_mirrors: agentForm.github_mirrors,
      },
    }));
    if (data) setAgentCommand({ root: data.root_command || data.recommended_command || data.full_command || '', sudo: data.sudo_command || '', mirrorRoots: data.mirror_root_commands || [], mirrorSudos: data.mirror_sudo_commands || [] });
  }

  async function copyCommand(kind, text) {
    if (!text) { setAlert({ type: 'error', message: '请先生成一键命令' }); return; }
    const ok = await copyText(text);
    setAlert(ok ? { type: 'success', message: `已复制 ${kind} 一键命令` } : { type: 'error', message: '复制失败，请手动复制' });
  }

  async function createNodeTask(nodeID, action) {
    await run(actionLabel(action), async () => api('/tasks', { body: { node_id: nodeID, action, payload: {} } }));
    await refreshTasks();
  }

  async function deleteNode(node) {
    const mode = window.prompt('删除模式：record_only=仅删除记录；clean_deployed=清理组网/转发/PBR/MSS；purge_agent=清理并卸载 Agent', 'clean_deployed');
    if (!mode) return;
    if (!window.confirm(`确认执行 ${mode}？\n离线节点无法远程清理；如果 Agent 仍运行，仅删记录后会重新上线。`)) return;
    await run('删除 / 清理节点', async () => api(`/nodes/${encodeURIComponent(node.id)}?mode=${encodeURIComponent(mode)}`, { method: 'DELETE' }));
    await Promise.all([refreshNodes(), refreshTasks()]);
  }

  function scheduleLinkVerify(link) {
    if (!link?.id) return;
    window.setTimeout(async () => {
      await run('自动验证组网', async () => api(`/network-links/${encodeURIComponent(link.id)}/verify`, { body: {} }));
      await Promise.all([refreshNetworkLinks(), refreshTasks(), refreshNodes()]);
    }, 20000);
  }

  async function quickApplyNetwork() {
    const entryNode = nodeMap[quickForm.entry_node_id];
    const backendNode = nodeMap[quickForm.backend_node_id];
    if (!entryNode || !backendNode) { setAlert({ type: 'error', message: '请选择入口节点和后端节点' }); return null; }
    if (entryNode.id === backendNode.id) { setAlert({ type: 'error', message: '入口节点和后端节点不能相同' }); return null; }
    if (quickForm.link_type === 'direct') {
      if (!String(quickForm.landing_reachable_host || '').trim()) { setAlert({ type: 'error', message: '请填写 B 可达地址。' }); return null; }
      const data = await run('创建直连链路', async () => api('/network-links', {
        body: {
          link_type: 'direct',
          name: quickForm.name || 'direct-link',
          entry_node_id: quickForm.entry_node_id,
          landing_node_id: quickForm.backend_node_id,
          landing_reachable_host: quickForm.landing_reachable_host,
          transit_port: Number(quickForm.port || 11010),
          port: Number(quickForm.port || 11010),
          protocols,
        },
      }));
      if (data) await Promise.all([refreshNetworkLinks(), refreshTasks()]);
      return data;
    }
    if (!entryNode.public_ip && !entryNode.observed_ip) { setAlert({ type: 'error', message: '入口节点缺少公网 IP，无法生成后端 peers' }); return null; }
    const protocols = [];
    if (quickForm.tcp) protocols.push('tcp');
    if (quickForm.udp) protocols.push('udp');
    if (protocols.length === 0) { setAlert({ type: 'error', message: '请至少选择 TCP 或 UDP' }); return null; }
    const data = await run('创建并应用组网', async () => api('/network-links/quick-apply', {
      body: {
        name: quickForm.name,
        network_name: quickForm.network_name,
        network_secret: quickForm.network_secret,
        cidr: quickForm.cidr,
        port: Number(quickForm.port || 11010),
        mtu: Number(quickForm.mtu || 1380),
        mss_clamp_enabled: quickForm.mss_clamp_enabled,
        mss_mode: quickForm.mss_mode,
        mss_value: Number(quickForm.mss_value || 0),
        entry_node_id: quickForm.entry_node_id,
        backend_node_id: quickForm.backend_node_id,
        protocols,
        listeners: quickForm.showAdvanced ? lines(quickForm.listeners) : undefined,
        peers: quickForm.showAdvanced ? lines(quickForm.peers) : undefined,
      },
    }));
    if (data) {
      setAlert({ type: 'success', message: '已创建入口和后端组网任务。系统将在约 20 秒后自动验证组网。' });
      await Promise.all([refreshNetworkLinks(), refreshNetworkProfiles(), refreshTasks()]);
      scheduleLinkVerify(data.link);
    }
    return data;
  }

  async function reapplyLink(link) {
    const data = await run('启用并重新应用组网', async () => api(`/network-links/${encodeURIComponent(link.id)}/enable`, { body: {} }));
    await Promise.all([refreshNetworkLinks(), refreshTasks()]);
    scheduleLinkVerify(data?.link || link);
  }
  async function disableLink(link) {
    await run('禁用组网记录', async () => api(`/network-links/${encodeURIComponent(link.id)}/disable`, { body: {} }));
    await refreshNetworkLinks();
  }
  function editLink(link) {
    setQuickForm((old) => ({
      ...old,
      name: link.name || old.name,
      network_name: link.network_name || old.network_name,
      link_type: link.link_type || 'easytier',
      cidr: link.cidr || old.cidr,
      port: link.transit_port || link.port || old.port,
      entry_node_id: link.entry_node_id || '',
      backend_node_id: link.backend_node_id || '',
      landing_reachable_host: link.landing_reachable_host || '',
      tcp: safeList(link.protocols).includes('tcp') || safeList(link.protocols).length === 0,
      udp: safeList(link.protocols).includes('udp') || safeList(link.protocols).length === 0,
    }));
  }
  async function deleteLink(link) {
    if (!window.confirm('确认删除这条组网记录？不会停止远端 EasyTier 服务。')) return;
    await run('删除组网记录', async () => api(`/network-links/${encodeURIComponent(link.id)}`, { method: 'DELETE' }));
    await refreshNetworkLinks();
  }

  function selectedForwardLink() { return networkLinks.find((item) => item.id === forwardForm.network_link_id); }
  async function createForward(options = {}) {
    const link = selectedForwardLink();
    if (!link) { setAlert({ type: 'error', message: '请先选择一条已成功的组网链路。' }); return null; }
    if (link.status !== 'connected' && link.status !== 'active') { setAlert({ type: 'error', message: '该组网链路尚未显示“组网成功”，请等待自动验证完成。' }); return null; }
    if (!String(forwardForm.landing_host || '').trim()) { setAlert({ type: 'error', message: '请填写落地服务器 IP 或域名。' }); return null; }
    const body = {
      network_link_id: forwardForm.network_link_id,
      name: forwardForm.name || `forward-${forwardForm.public_listen_port || 'port'}`,
      protocol: forwardForm.protocol,
      public_listen_port: Number(forwardForm.public_listen_port),
      landing_host: forwardForm.landing_host.trim(),
      landing_port: Number(forwardForm.landing_port),
      transport_mode: link.link_type === 'direct' ? 'direct' : (forwardForm.transport_mode || 'easytier'),
      enabled: forwardForm.enabled,
      remark: forwardForm.remark,
    };
    const path = options.apply ? '/forwards/create-and-apply' : '/forwards';
    const result = await run(options.apply ? '创建并应用转发' : '创建转发规则', async () => api(path, { body }));
    if (result) {
      if (options.apply) await refreshTasks();
      setForwardForm((old) => ({ ...old, name: '', public_listen_port: '', landing_host: '', landing_port: '', remark: '' }));
      await refreshForwards();
      setAlert({ type: 'success', message: options.apply ? '已创建 A 侧入口转发和 B 侧落地转发任务，请到任务页查看结果。' : '已创建转发规则' });
    }
    return result;
  }
  async function deleteForward(rule) {
    if (!window.confirm('确认删除这条转发规则？')) return;
    await run('删除转发规则', async () => api(`/forwards/${encodeURIComponent(rule.id)}`, { method: 'DELETE' }));
    await refreshForwards();
  }
  async function applyForward(rule) {
    await run('应用转发规则', async () => api(`/forwards/${encodeURIComponent(rule.id)}/apply`, { body: {} }));
    await Promise.all([refreshForwards(), refreshTasks()]);
  }
  async function verifyForward(rule) {
    await run('验证转发规则', async () => api(`/forwards/${encodeURIComponent(rule.id)}/verify`, { body: {} }));
    await Promise.all([refreshForwards(), refreshTasks()]);
  }
  async function disableForward(rule) {
    await run('停用转发规则', async () => api(`/forwards/${encodeURIComponent(rule.id)}/disable`, { body: {} }));
    await Promise.all([refreshForwards(), refreshTasks()]);
  }

  async function detectInterfaces(nodeID) {
    if (!nodeID) { setAlert({ type: 'error', message: '请选择节点' }); return; }
    await run('识别网卡', async () => api('/tasks', { body: { node_id: nodeID, action: 'detect_network_interfaces', payload: {} } }));
    await refreshTasks();
    setAlert({ type: 'success', message: '已创建识别网卡任务，请在任务页查看默认出口和网关。' });
  }
  async function detectPBRRouteGroups(nodeID) {
    if (!nodeID) { setAlert({ type: 'error', message: '请选择 B 落地节点。' }); return; }
    await run('识别出口线路', async () => api('/tasks', { body: { node_id: nodeID, action: 'detect_pbr_route_groups', payload: {} } }));
    await refreshTasks();
    setAlert({ type: 'success', message: '已创建识别出口线路任务。Agent 执行后刷新本页，即可选择检测到的线路组。' });
  }
  function latestPBRRouteGroupResult(nodeID) {
    if (!nodeID) return {};
    const matched = tasks
      .filter((task) => task.node_id === nodeID && task.action === 'detect_pbr_route_groups' && task.status === 'succeeded')
      .sort((a, b) => String(b.finished_at || b.created_at || '').localeCompare(String(a.finished_at || a.created_at || '')));
    return parseJSON(matched[0]?.result);
  }
  function pbrRouteGroupsForNode(nodeID) { return safeList(latestPBRRouteGroupResult(nodeID).route_groups); }
  function selectedForwardName(id) { return forwards.find((rule) => rule.id === id)?.name || 'forward'; }
  function selectPBRRouteGroup(group) {
    setPBRForm({
      ...pbrForm,
      route_group_name: group.name || '',
      route_group_gateway: group.gateway || '',
      route_group_table_id: group.table_id || '',
      route_group_table_name: group.table_name || '',
      route_group_matched_ip: group.matched_ip || '',
      name: pbrForm.name || `pbr-${group.name || 'route'}-${selectedForwardName(pbrForm.forward_rule_id)}`,
    });
  }
  async function createPBR(apply = false) {
    if (!pbrForm.node_id) { setAlert({ type: 'error', message: '请选择节点。' }); return; }
    if (!pbrForm.forward_rule_id) { setAlert({ type: 'error', message: '请选择关联转发规则。' }); return; }
    if (!pbrForm.route_group_name) { setAlert({ type: 'error', message: '请先识别并选择出口线路。' }); return; }
    const body = { ...pbrForm, name: pbrForm.name || 'pbr-forward', source_type: 'forward', enabled: pbrForm.enabled };
    const path = apply ? '/pbr-policies/create-and-apply' : '/pbr-policies';
    const result = await run(apply ? '创建并应用出口策略' : '创建出口策略', async () => api(path, { body }));
    if (result) await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function applyPBR(policy) {
    await run('应用出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}/apply`, { body: {} }));
    await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function verifyPBR(policy) {
    await run('验证出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}/verify`, { body: {} }));
    await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function disablePBR(policy) {
    await run('禁用出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}/disable`, { body: {} }));
    await Promise.all([refreshPBRPolicies(), refreshTasks()]);
  }
  async function deletePBR(policy) {
    if (!window.confirm('确认删除这条出口策略？')) return;
    await run('删除出口策略', async () => api(`/pbr-policies/${encodeURIComponent(policy.id)}`, { method: 'DELETE' }));
    await refreshPBRPolicies();
  }

  async function runDiagnostics(nodeIDs = []) {
    const data = await run('运行一键诊断', async () => api('/diagnostics/run', { body: { node_ids: nodeIDs, include_controller: true } }));
    if (data) await refreshTasks();
    return data;
  }
  async function getDiagnostics(id) {
    return run('读取诊断报告', async () => api(`/diagnostics/${encodeURIComponent(id)}`));
  }

  function saveSettings() {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(API_BASE_KEY, apiBase);
    setAlert({ type: 'success', message: '设置已保存' });
  }
  function clearToken() {
    localStorage.removeItem(TOKEN_KEY);
    setToken('');
    setAlert({ type: 'success', message: 'Token 已清除' });
  }

  const selectedForward = forwards.find((rule) => rule.id === pbrForm.forward_rule_id);
  const recommendedNode = selectedForward?.landing_node_id || selectedForward?.backend_node_id || '';
  const selectedNodeID = pbrForm.node_id || recommendedNode;
  const routeGroups = pbrRouteGroupsForNode(selectedNodeID);
  const routeDetection = latestPBRRouteGroupResult(selectedNodeID);
  const selectedGroup = routeGroups.find((group) => group.name === pbrForm.route_group_name) || null;
  const availableForwards = forwards.filter((rule) => !selectedNodeID || (rule.landing_node_id || rule.backend_node_id) === selectedNodeID);
  const canApplyPBR = Boolean(selectedNodeID && pbrForm.forward_rule_id && selectedGroup);

  function renderLogin() {
    return (
      <Card title="登录 / Token" description="当前主控启用了严格鉴权，请输入 Operator Token。">
        <div className="form-grid drawer-form">
          <label>Operator Token<input type="password" value={token} onChange={(event) => setToken(event.target.value)} /></label>
          <label>API Base<input value={apiBase} onChange={(event) => setApiBase(event.target.value)} placeholder="默认同源" /></label>
        </div>
        <div className="actions"><button onClick={() => { saveSettings(); run('测试连接', refreshAll); }}>保存并连接</button><button className="secondary" onClick={clearToken}>清除 Token</button></div>
      </Card>
    );
  }

  function renderActiveTab() {
    if (strictAuth && !token && activeTab !== 'settings') return renderLogin();
    switch (activeTab) {
      case 'dashboard':
        return <Dashboard stats={stats} nodes={nodes} networkLinks={networkLinks} forwards={forwards} pbrPolicies={pbrPolicies} tasks={tasks} nodeMap={nodeMap} onNavigate={setActiveTab} onOpenAddNode={() => setActiveTab('nodes')} onRefresh={() => run('刷新', refreshAll)} />;
      case 'nodes':
        return <Nodes nodes={nodes} agentForm={agentForm} setAgentForm={setAgentForm} agentCommand={agentCommand} onGenerateAgentCommand={generateAgentCommand} onCopyCommand={copyCommand} onRefresh={refreshNodes} onCreateTask={createNodeTask} onDeleteNode={deleteNode} onCopy={handleCopyValue} loading={loading} />;
      case 'networks':
        return <NetworkLinks nodes={nodes} nodeMap={nodeMap} networkLinks={networkLinks} networkProfiles={networkProfiles} quickForm={quickForm} setQuickForm={setQuickForm} onQuickApply={quickApplyNetwork} onReapply={reapplyLink} onDisable={disableLink} onDelete={deleteLink} onEdit={editLink} onRefresh={() => Promise.all([refreshNetworkLinks(), refreshNetworkProfiles(), refreshNodes()])} onCopy={handleCopyValue} />;
      case 'forwards':
        return <Forwards forwards={forwards} networkLinks={networkLinks} nodeMap={nodeMap} forwardForm={forwardForm} setForwardForm={setForwardForm} onCreateForward={createForward} onApplyForward={applyForward} onVerifyForward={verifyForward} onDisableForward={disableForward} onDeleteForward={deleteForward} onRefresh={() => Promise.all([refreshForwards(), refreshNetworkLinks(), refreshNodes()])} onCopy={handleCopyValue} />;
      case 'pbr':
        return <PBR nodes={nodes} forwards={forwards} pbrPolicies={pbrPolicies} pbrForm={pbrForm} setPBRForm={setPBRForm} nodeMap={nodeMap} routeGroups={routeGroups} routeDetection={routeDetection} selectedNodeID={selectedNodeID} selectedGroup={selectedGroup} availableForwards={availableForwards} canApply={canApplyPBR} onDetectRouteGroups={detectPBRRouteGroups} onDetectInterfaces={detectInterfaces} onSelectRouteGroup={selectPBRRouteGroup} onCreatePBR={createPBR} onApplyPBR={applyPBR} onVerifyPBR={verifyPBR} onDisablePBR={disablePBR} onDeletePBR={deletePBR} onRefresh={() => Promise.all([refreshPBRPolicies(), refreshForwards(), refreshNodes(), refreshTasks()])} onCopy={handleCopyValue} />;
      case 'tasks':
        return <Tasks tasks={tasks} nodes={nodes} nodeMap={nodeMap} taskFilter={taskFilter} setTaskFilter={setTaskFilter} taskNodeFilter={taskNodeFilter} setTaskNodeFilter={setTaskNodeFilter} taskEasyTierOnly={taskEasyTierOnly} setTaskEasyTierOnly={setTaskEasyTierOnly} onRefresh={refreshTasks} onCopy={handleCopyValue} />;
      case 'diagnostics':
        return <Diagnostics nodes={nodes} tasks={tasks} onRunDiagnostics={runDiagnostics} onGetDiagnostics={getDiagnostics} onCopy={handleCopyValue} onRefresh={refreshTasks} />;
      case 'settings':
        return <Settings apiBase={apiBase} setApiBase={setApiBase} token={token} setToken={setToken} strictAuth={strictAuth} health={health} onSave={saveSettings} onClear={clearToken} onTest={() => run('测试连接', refreshHealth)} onCopy={handleCopyValue} />;
      default:
        return null;
    }
  }

  return (
    <Layout tabs={tabs} activeTab={activeTab} onTabChange={setActiveTab} health={health} version={DEFAULT_VERSION} strictAuth={strictAuth} loading={loading} alert={alert} onRefresh={() => run('刷新', refreshAll)}>
      {renderActiveTab()}
    </Layout>
  );
}

createRoot(document.getElementById('root')).render(<App />);
