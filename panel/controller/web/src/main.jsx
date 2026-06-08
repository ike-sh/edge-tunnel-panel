import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';
import { API_BASE_KEY, TOKEN_KEY, createApiClient } from './api.js';
import { createApiV2Client } from './api/v2.js';
import { watchTasks } from './api/taskStream.js';
import CreateProfileWizard from './components/CreateProfileWizard.jsx';
import ImportCodeWizard from './components/ImportCodeWizard.jsx';
import Layout from './components/Layout.jsx';
import Card from './components/Card.jsx';
import Dashboard from './pages/Dashboard.jsx';
import Machines from './pages/Machines.jsx';
import Profiles from './pages/Profiles.jsx';
import ProfileDetail from './pages/ProfileDetail.jsx';
import Diagnostics from './pages/Diagnostics.jsx';
import Tasks from './pages/Tasks.jsx';
import Settings from './pages/Settings.jsx';
import { copyText } from './utils/copy.js';
import {
  DEFAULT_VERSION,
  tabs,
  safeList,
} from './utils/format.js';

const THEME_KEY = 'etp-theme';

function taskIDsFromResponse(data) {
  if (!data) return [];
  if (Array.isArray(data.tasks)) return data.tasks.map((task) => task.id).filter(Boolean);
  if (data.task?.id) return [data.task.id];
  return [];
}

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [theme, setTheme] = useState(() => localStorage.getItem(THEME_KEY) || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || '');
  const [apiBase, setApiBase] = useState(() => localStorage.getItem(API_BASE_KEY) || '');
  const [alert, setAlert] = useState(null);
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState(null);
  const [nodes, setNodes] = useState([]);
  const [tasks, setTasks] = useState([]);
  const [machines, setMachines] = useState([]);
  const [ixProfiles, setIxProfiles] = useState([]);
  const [selectedProfileId, setSelectedProfileId] = useState(null);
  const [pendingTaskIds, setPendingTaskIds] = useState([]);
  const [taskFilter, setTaskFilter] = useState('all');
  const [taskNodeFilter, setTaskNodeFilter] = useState('all');
  const [taskIxOnly, setTaskIxOnly] = useState(false);
  const [showWizard, setShowWizard] = useState(false);
  const [showImportWizard, setShowImportWizard] = useState(false);
  const stopStreamsRef = useRef(null);

  const api = useMemo(() => createApiClient({ apiBase, token }), [apiBase, token]);
  const apiV2 = useMemo(() => createApiV2Client({ apiBase, token }), [apiBase, token]);
  const strictAuth = health?.strict_auth !== false;
  const nodeMap = useMemo(() => Object.fromEntries(nodes.map((node) => [node.id, node])), [nodes]);
  const stats = useMemo(() => ({
    online: machines.filter((m) => m.status === 'online').length,
    stale: machines.filter((m) => m.status === 'pending').length,
    offline: machines.filter((m) => m.status === 'offline').length,
    failed: tasks.filter((task) => task.status === 'failed').length,
    profiles: ixProfiles.length,
    healthyProfiles: ixProfiles.filter((p) => p.status === 'healthy').length,
  }), [machines, tasks, ixProfiles]);
  const selectedProfile = ixProfiles.find((p) => p.id === selectedProfileId) || null;
  const selectedMachine = machines.find((m) => m.id === selectedProfile?.machine_id) || null;

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
  async function refreshMachines() { const data = safeList(await apiV2('/machines')); setMachines(data); return data; }
  async function refreshIxProfiles() { const data = safeList(await apiV2('/profiles')); setIxProfiles(data); return data; }

  async function refreshAll() {
    const h = await refreshHealth();
    if (token || h.strict_auth === false) {
      await Promise.all([refreshTasks(), refreshMachines(), refreshIxProfiles(), refreshNodes()]);
    }
  }

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(THEME_KEY, theme);
  }, [theme]);

  function toggleTheme() {
    setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'));
  }

  function mergeTaskUpdate(task) {
    if (!task?.id) return;
    setTasks((prev) => {
      const index = prev.findIndex((item) => item.id === task.id);
      if (index === -1) return [task, ...prev];
      const next = [...prev];
      next[index] = { ...next[index], ...task };
      return next;
    });
  }

  function trackTasks(data, label) {
    const ids = taskIDsFromResponse(data);
    if (!ids.length) return;
    setPendingTaskIds((prev) => [...new Set([...prev, ...ids])]);
    stopStreamsRef.current?.();
    stopStreamsRef.current = watchTasks(apiBase, token, ids, {
      onUpdate: (task) => mergeTaskUpdate(task),
      onDone: async (task) => {
        mergeTaskUpdate(task);
        setPendingTaskIds((prev) => prev.filter((id) => id !== task.id));
        await Promise.all([refreshIxProfiles(), refreshTasks()]);
        if (task.status === 'failed') {
          setAlert({ type: 'error', message: `${label || '任务'}失败：${task.error || task.result || '未知错误'}` });
        }
      },
      onError: () => refreshTasks().catch(() => {}),
    });
  }

  useEffect(() => () => stopStreamsRef.current?.(), []);

  async function installMachine(machine) {
    const data = await run('生成安装命令', async () => apiV2('/bootstrap/install', { body: { machine_id: machine.id } }));
    if (data?.root_command) {
      await handleCopyValue(`${data.root_command}\n# Agent 注册 payload 携带 machine_id=${machine.id}`, '安装命令');
    }
  }

  async function createMachine(role) {
    const name = window.prompt('机器名称', role === 'nat-transit' ? 'nat-ix-1' : 'ingress-1');
    if (!name) return;
    await run('创建机器', async () => apiV2('/machines', { body: { name, role } }));
    await refreshMachines();
  }

  async function createIxProfileFromWizard(body) {
    const data = await run('创建线路', async () => apiV2('/profiles', { body }));
    if (!data) return false;
    trackTasks(data, '创建线路');
    await Promise.all([refreshIxProfiles(), refreshTasks()]);
    return true;
  }

  async function importIxProfileFromWizard(body) {
    const data = await run('导入接入码', async () => apiV2('/profiles', { body }));
    if (!data) return false;
    trackTasks(data, '导入接入码');
    await Promise.all([refreshIxProfiles(), refreshTasks()]);
    return true;
  }

  async function createIxProfile() {
    const machineId = machines[0]?.id || window.prompt('机器 ID (machine_id)');
    if (!machineId) { setAlert({ type: 'error', message: '请先添加机器' }); return; }
    const name = window.prompt('线路名称', 'ix-line-1');
    if (!name) return;
    const natHost = window.prompt('商家 NAT 地址', '');
    const landingHost = window.prompt('落地地址', '');
    const data = await run('创建线路', async () => apiV2('/profiles', {
      body: {
        name,
        machine_id: machineId,
        role: 'nat-transit',
        config: { NAT_PUBLIC_HOST: natHost || '', LANDING_HOST: landingHost || '' },
      },
    }));
    trackTasks(data, '创建线路');
    await Promise.all([refreshIxProfiles(), refreshTasks()]);
  }

  async function applyIxProfile(profile) {
    const data = await run('应用线路', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/apply`, { body: {} }));
    trackTasks(data, '应用线路');
    await refreshTasks();
  }

  async function syncIxProfile(profile) {
    const data = await run('同步线路', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/sync`, { body: {} }));
    trackTasks(data, '同步线路');
    await refreshTasks();
    return data;
  }

  async function refreshIxProfileCode(profile) {
    const data = await run('刷新接入码', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/code/refresh`, { body: {} }));
    trackTasks(data, '刷新接入码');
    await refreshTasks();
  }

  async function openProfile(profile) {
    setSelectedProfileId(profile.id);
    setActiveTab('profiles');
  }

  useEffect(() => { run('加载数据', refreshAll); }, []);
  useEffect(() => {
    const timer = window.setInterval(() => {
      refreshNodes().catch(() => {});
      refreshMachines().catch(() => {});
    }, 15000);
    return () => window.clearInterval(timer);
  }, [apiBase, token]);

  async function handleCopyValue(text, title = '内容') {
    const ok = await copyText(text);
    setAlert(ok ? { type: 'success', message: `已复制 ${title}` } : { type: 'error', message: '复制失败，请手动复制' });
  }

  async function runDiagnostics(machineIDs = []) {
    const data = await run('运行一键诊断', async () => apiV2('/diagnostics/run', { body: { machine_ids: machineIDs } }));
    if (data?.tasks) trackTasks(data, '诊断');
    if (data) await refreshTasks();
    return data;
  }

  async function getDiagnostics(id) {
    return null;
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
        return (
          <Dashboard
            stats={stats}
            machines={machines}
            profiles={ixProfiles}
            tasks={tasks}
            onNavigate={setActiveTab}
            onOpenAddNode={() => setActiveTab('machines')}
            onOpenWizard={() => setShowWizard(true)}
            onOpenImport={() => setShowImportWizard(true)}
            onOpenProfile={(p) => openProfile(p)}
            onRefresh={() => run('刷新', refreshAll)}
          />
        );
      case 'machines':
        return <Machines machines={machines} onRefresh={refreshMachines} onCreate={createMachine} onInstall={installMachine} loading={loading} />;
      case 'profiles':
        if (selectedProfile) {
          return (
            <ProfileDetail
              profile={selectedProfile}
              machine={selectedMachine}
              pendingTaskIds={pendingTaskIds}
              onBack={() => setSelectedProfileId(null)}
              onApply={applyIxProfile}
              onSync={syncIxProfile}
              onRefreshCode={refreshIxProfileCode}
              loading={loading}
            />
          );
        }
        return (
          <Profiles
            profiles={ixProfiles}
            machines={machines}
            onRefresh={refreshIxProfiles}
            onCreate={createIxProfile}
            onApply={applyIxProfile}
            onSync={syncIxProfile}
            onOpen={openProfile}
            loading={loading}
          />
        );
      case 'tasks':
        return (
          <Tasks
            tasks={tasks}
            nodes={nodes}
            nodeMap={nodeMap}
            taskFilter={taskFilter}
            setTaskFilter={setTaskFilter}
            taskNodeFilter={taskNodeFilter}
            setTaskNodeFilter={setTaskNodeFilter}
            taskIxOnly={taskIxOnly}
            setTaskIxOnly={setTaskIxOnly}
            onRefresh={refreshTasks}
            onCopy={handleCopyValue}
          />
        );
      case 'diagnostics':
        return <Diagnostics machines={machines} tasks={tasks} onRunDiagnostics={runDiagnostics} onCopy={handleCopyValue} onRefresh={refreshTasks} loading={loading} />;
      case 'settings':
        return <Settings apiBase={apiBase} setApiBase={setApiBase} token={token} setToken={setToken} strictAuth={strictAuth} health={health} onSave={saveSettings} onClear={clearToken} onTest={() => run('测试连接', refreshHealth)} onCopy={handleCopyValue} />;
      default:
        return null;
    }
  }

  return (
    <Layout tabs={tabs} activeTab={activeTab} onTabChange={setActiveTab} health={health} version={DEFAULT_VERSION} strictAuth={strictAuth} loading={loading} alert={alert} onRefresh={() => run('刷新', refreshAll)} theme={theme} onThemeToggle={toggleTheme}>
      <CreateProfileWizard open={showWizard} machines={machines} loading={loading} onClose={() => setShowWizard(false)} onSubmit={createIxProfileFromWizard} />
      <ImportCodeWizard open={showImportWizard} machines={machines} loading={loading} onClose={() => setShowImportWizard(false)} onSubmit={importIxProfileFromWizard} />
      <div key={activeTab} className="animate-fade-in">{renderActiveTab()}</div>
    </Layout>
  );
}

createRoot(document.getElementById('root')).render(<App />);
