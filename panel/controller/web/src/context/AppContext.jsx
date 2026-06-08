import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { API_BASE_KEY, TOKEN_KEY, createApiClient } from '../api.js';
import { createApiV2Client } from '../api/v2.js';
import { watchTasks } from '../api/taskStream.js';
import { watchMachineStream } from '../api/machineStream.js';
import { copyText } from '../utils/copy.js';
import { setUnauthorizedHandler, taskBelongsToProfile, taskOutput } from '../utils/auth.js';
import { DEFAULT_VERSION, safeList } from '../utils/format.js';

const THEME_KEY = 'etp-theme';

const AppContext = createContext(null);

function taskIDsFromResponse(data) {
  if (!data) return [];
  if (Array.isArray(data.tasks)) return data.tasks.map((task) => task.id).filter(Boolean);
  if (data.task?.id) return [data.task.id];
  return [];
}

export function AppProvider({ children }) {
  const navigate = useNavigate();
  const [theme, setTheme] = useState(() => localStorage.getItem(THEME_KEY) || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY) || '');
  const [apiBase, setApiBase] = useState(() => localStorage.getItem(API_BASE_KEY) || '');
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState(null);
  const [nodes, setNodes] = useState([]);
  const [tasks, setTasks] = useState([]);
  const [machines, setMachines] = useState([]);
  const [ixProfiles, setIxProfiles] = useState([]);
  const [pendingTaskIds, setPendingTaskIds] = useState([]);
  const [taskFilter, setTaskFilter] = useState('all');
  const [taskNodeFilter, setTaskNodeFilter] = useState('all');
  const [taskIxOnly, setTaskIxOnly] = useState(false);
  const [showWizard, setShowWizard] = useState(false);
  const [showImportWizard, setShowImportWizard] = useState(false);
  const [streamLive, setStreamLive] = useState(false);
  const [bootstrapped, setBootstrapped] = useState(false);
  const stopStreamsRef = useRef(null);
  const machineStreamRef = useRef(null);
  const alertKeysRef = useRef(new Set());

  const api = useMemo(() => createApiClient({ apiBase, token }), [apiBase, token]);
  const apiV2 = useMemo(() => createApiV2Client({ apiBase, token }), [apiBase, token]);
  const strictAuth = health?.strict_auth !== false;
  const nodeMap = useMemo(() => Object.fromEntries(nodes.map((node) => [node.id, node])), [nodes]);
  const stats = useMemo(() => ({
    online: machines.filter((m) => m.status === 'online').length,
    stale: machines.filter((m) => m.status === 'stale').length,
    pending: machines.filter((m) => m.status === 'pending').length,
    offline: machines.filter((m) => m.status === 'offline').length,
    failed: tasks.filter((task) => task.status === 'failed').length,
    profiles: ixProfiles.length,
    healthyProfiles: ixProfiles.filter((p) => p.status === 'healthy').length,
  }), [machines, tasks, ixProfiles]);

  const run = useCallback(async (label, fn, { silent = false } = {}) => {
    setLoading(true);
    try {
      const result = await fn();
      if (!silent) toast.success(`${label}成功`);
      return result;
    } catch (error) {
      toast.error(error.message || String(error));
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  const refreshHealth = useCallback(async () => {
    const data = await api('/health');
    setHealth(data);
    return data;
  }, [api]);

  const refreshNodes = useCallback(async () => {
    const data = safeList(await api('/nodes'));
    setNodes(data);
    return data;
  }, [api]);

  const refreshTasks = useCallback(async () => {
    const data = safeList(await api('/tasks'));
    setTasks(data);
    return data;
  }, [api]);

  const refreshMachines = useCallback(async () => {
    const data = safeList(await apiV2('/machines'));
    setMachines(data);
    return data;
  }, [apiV2]);

  const refreshIxProfiles = useCallback(async () => {
    const data = safeList(await apiV2('/profiles'));
    setIxProfiles(data);
    return data;
  }, [apiV2]);

  const refreshAll = useCallback(async () => {
    const h = await refreshHealth();
    if (token || h.strict_auth === false) {
      await Promise.all([refreshTasks(), refreshMachines(), refreshIxProfiles(), refreshNodes()]);
    }
  }, [token, refreshHealth, refreshTasks, refreshMachines, refreshIxProfiles, refreshNodes]);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(THEME_KEY, theme);
  }, [theme]);

  useEffect(() => {
    setUnauthorizedHandler(() => {
      localStorage.removeItem(TOKEN_KEY);
      setToken('');
      toast.error('登录已失效，请重新输入 Token');
      navigate('/login', { replace: true, state: { from: window.location.pathname } });
    });
    return () => setUnauthorizedHandler(() => {});
  }, [navigate]);

  const toggleTheme = useCallback(() => {
    setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'));
  }, []);

  const mergeTaskUpdate = useCallback((task) => {
    if (!task?.id) return;
    setTasks((prev) => {
      const index = prev.findIndex((item) => item.id === task.id);
      if (index === -1) return [task, ...prev];
      const next = [...prev];
      next[index] = { ...next[index], ...task };
      return next;
    });
  }, []);

  const getProfilePendingTaskIds = useCallback((profileId) => {
    const pending = new Set(pendingTaskIds);
    return tasks
      .filter((t) => pending.has(t.id) && taskBelongsToProfile(t, profileId))
      .map((t) => t.id);
  }, [pendingTaskIds, tasks]);

  const trackTasks = useCallback((data, label) => {
    const ids = taskIDsFromResponse(data);
    if (!ids.length) return;
    setPendingTaskIds((prev) => [...new Set([...prev, ...ids])]);
    const stops = ids.filter(Boolean).map((taskId) => watchTasks(apiBase, token, [taskId], {
      onUpdate: (task) => mergeTaskUpdate(task),
      onDone: async (task) => {
        mergeTaskUpdate(task);
        setPendingTaskIds((prev) => prev.filter((id) => id !== task.id));
        await Promise.all([refreshIxProfiles(), refreshTasks()]);
        if (task.status === 'failed') {
          toast.error(`${label || '任务'}失败：${task.error || task.result || '未知错误'}`);
        } else if (label) {
          toast.success(`${label}已完成`);
        }
      },
      onError: () => refreshTasks().catch(() => {}),
    }));
    const prevStop = stopStreamsRef.current;
    stopStreamsRef.current = () => {
      prevStop?.();
      stops.forEach((stop) => stop());
    };
  }, [apiBase, token, mergeTaskUpdate, refreshIxProfiles, refreshTasks]);

  useEffect(() => () => stopStreamsRef.current?.(), []);

  useEffect(() => {
    let cancelled = false;
    setBootstrapped(false);
    refreshAll()
      .catch(() => {})
      .finally(() => {
        if (!cancelled) setBootstrapped(true);
      });
    return () => { cancelled = true; };
  }, [token, apiBase, refreshAll]);

  useEffect(() => {
    if (health === null) return undefined;
    if (strictAuth && !token) return undefined;
    machineStreamRef.current?.();
    machineStreamRef.current = watchMachineStream(apiBase, token, {
      onOpen: () => setStreamLive(true),
      onClose: () => setStreamLive(false),
      onSnapshot: (data) => {
        if (Array.isArray(data.machines)) setMachines(data.machines);
        if (Array.isArray(data.nodes)) setNodes(data.nodes);
      },
    });
    return () => {
      machineStreamRef.current?.();
      machineStreamRef.current = null;
      setStreamLive(false);
    };
  }, [apiBase, token, strictAuth, health]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      if (!streamLive) {
        refreshNodes().catch(() => {});
        refreshMachines().catch(() => {});
      }
    }, 15000);
    return () => window.clearInterval(timer);
  }, [refreshNodes, refreshMachines, streamLive]);

  useEffect(() => {
    if (!bootstrapped) return;
    machines.forEach((m) => {
      if (m.status !== 'stale' && m.status !== 'offline') return;
      const key = `machine:${m.id}:${m.status}`;
      if (alertKeysRef.current.has(key)) return;
      alertKeysRef.current.add(key);
      const label = m.status === 'stale' ? '心跳延迟（stale）' : '已离线';
      toast.error(`机器「${m.name || m.id}」${label}`, { id: key, duration: 8000 });
    });
    ixProfiles.forEach((p) => {
      const machine = machines.find((m) => m.id === p.machine_id);
      if (p.status === 'failed') {
        const key = `profile-failed:${p.id}`;
        if (!alertKeysRef.current.has(key)) {
          alertKeysRef.current.add(key);
          toast.error(`线路「${p.name}」应用失败，请检查任务日志`, { id: key, duration: 8000 });
        }
      }
      if (machine && (machine.status === 'stale' || machine.status === 'offline') && p.status === 'healthy') {
        const key = `profile-stale:${p.id}:${machine.status}`;
        if (!alertKeysRef.current.has(key)) {
          alertKeysRef.current.add(key);
          toast(`线路「${p.name}」绑定机器 ${machine.status === 'stale' ? '心跳延迟' : '离线'}`, {
            id: key,
            icon: '⚠️',
            duration: 8000,
          });
        }
      }
    });
  }, [machines, ixProfiles, bootstrapped]);

  const handleCopyValue = useCallback(async (text, title = '内容') => {
    const ok = await copyText(text);
    if (ok) toast.success(`已复制 ${title}`);
    else toast.error('复制失败，请手动复制');
    return ok;
  }, []);

  const installMachine = useCallback(async (machine) => {
    const data = await run('生成安装命令', async () => apiV2('/bootstrap/install', { body: { machine_id: machine.id } }));
    return data;
  }, [apiV2, run]);

  const createMachine = useCallback(async ({ name, role }) => {
    const data = await run('创建机器', async () => apiV2('/machines', { body: { name, role } }));
    if (data) await refreshMachines();
    return data;
  }, [apiV2, run, refreshMachines]);

  const rotateMachineToken = useCallback(async (machine) => {
    const data = await run('轮换 Token', async () => apiV2(`/machines/${encodeURIComponent(machine.id)}/rotate-token`, { body: {} }));
    return data;
  }, [apiV2, run]);

  const createIxProfileFromWizard = useCallback(async (body) => {
    const data = await run('创建线路', async () => apiV2('/profiles', { body }), { silent: true });
    if (!data) return false;
    trackTasks(data, '创建线路');
    await Promise.all([refreshIxProfiles(), refreshTasks()]);
    return true;
  }, [apiV2, run, trackTasks, refreshIxProfiles, refreshTasks]);

  const importIxProfileFromWizard = useCallback(async (body) => {
    const data = await run('导入接入码', async () => apiV2('/profiles', { body }), { silent: true });
    if (!data) return false;
    trackTasks(data, '导入接入码');
    await Promise.all([refreshIxProfiles(), refreshTasks()]);
    return true;
  }, [apiV2, run, trackTasks, refreshIxProfiles, refreshTasks]);

  const applyIxProfile = useCallback(async (profile, extra = {}) => {
    const data = await run('应用线路', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/apply`, {
      body: extra,
    }), { silent: true });
    trackTasks(data, '应用线路');
    await refreshTasks();
    return data;
  }, [apiV2, run, trackTasks, refreshTasks]);

  const syncIxProfile = useCallback(async (profile) => {
    const data = await run('同步线路', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/sync`, { body: {} }), { silent: true });
    trackTasks(data, '同步线路');
    await refreshTasks();
    return data;
  }, [apiV2, run, trackTasks, refreshTasks]);

  const refreshIxProfileCode = useCallback(async (profile) => {
    const data = await run('刷新接入码', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/code/refresh`, { body: {} }), { silent: true });
    trackTasks(data, '刷新接入码');
    await refreshTasks();
  }, [apiV2, run, trackTasks, refreshTasks]);

  const saveProfileRules = useCallback(async (profile, rules) => {
    const data = await run('保存规则', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/apply`, {
      body: { rules },
    }), { silent: true });
    setIxProfiles((prev) => prev.map((p) => (p.id === profile.id ? { ...p, rules } : p)));
    trackTasks(data, '应用规则');
    await refreshTasks();
    return data;
  }, [apiV2, run, trackTasks, refreshTasks]);

  const pauseIxProfile = useCallback(async (profile) => {
    const data = await run('暂停线路', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/pause`, { body: {} }), { silent: true });
    trackTasks(data, '暂停线路');
    await Promise.all([refreshIxProfiles(), refreshTasks()]);
    return data;
  }, [apiV2, run, trackTasks, refreshIxProfiles, refreshTasks]);

  const resumeIxProfile = useCallback(async (profile) => {
    const data = await run('恢复线路', async () => apiV2(`/profiles/${encodeURIComponent(profile.id)}/resume`, { body: {} }), { silent: true });
    trackTasks(data, '恢复线路');
    await Promise.all([refreshIxProfiles(), refreshTasks()]);
    return data;
  }, [apiV2, run, trackTasks, refreshIxProfiles, refreshTasks]);

  const diagnoseIxProfile = useCallback((profile) => new Promise((resolve, reject) => {
    (async () => {
      try {
        const data = await apiV2(`/profiles/${encodeURIComponent(profile.id)}/diagnose`, { body: {} });
        const taskId = data?.task?.id;
        if (!taskId) {
          reject(new Error('未创建诊断任务'));
          return;
        }
        setPendingTaskIds((prev) => [...new Set([...prev, taskId])]);
        watchTasks(apiBase, token, [taskId], {
          onUpdate: (task) => mergeTaskUpdate(task),
          onDone: async (task) => {
            mergeTaskUpdate(task);
            setPendingTaskIds((prev) => prev.filter((id) => id !== task.id));
            await refreshTasks();
            if (task.status === 'succeeded') {
              resolve(taskOutput(task));
            } else {
              reject(new Error(task.error || task.result || '诊断失败'));
            }
          },
          onError: (err) => reject(err),
        });
      } catch (error) {
        reject(error);
      }
    })();
  }), [apiV2, apiBase, token, mergeTaskUpdate, refreshTasks]);

  const fetchIxProfileCode = useCallback((profile) => new Promise((resolve, reject) => {
    (async () => {
      try {
        const data = await apiV2(`/profiles/${encodeURIComponent(profile.id)}/code`);
        const taskId = data?.task?.id;
        if (!taskId) {
          reject(new Error('未创建拉取任务'));
          return;
        }
        setPendingTaskIds((prev) => [...new Set([...prev, taskId])]);
        watchTasks(apiBase, token, [taskId], {
          onUpdate: (task) => mergeTaskUpdate(task),
          onDone: async (task) => {
            mergeTaskUpdate(task);
            setPendingTaskIds((prev) => prev.filter((id) => id !== task.id));
            await refreshIxProfiles();
            if (task.status === 'succeeded') {
              const text = (task.stdout || task.result || '').trim();
              resolve(text || profile.code_redacted || '');
            } else {
              reject(new Error(task.error || task.result || '拉取接入码失败'));
            }
          },
          onError: (err) => reject(err),
        });
      } catch (error) {
        reject(error);
      }
    })();
  }), [apiV2, apiBase, token, mergeTaskUpdate, refreshIxProfiles]);

  const openProfile = useCallback((profile) => {
    navigate(`/profiles/${profile.id}`);
  }, [navigate]);

  const runDiagnostics = useCallback(async (machineIDs = []) => {
    const data = await run('运行一键诊断', async () => apiV2('/diagnostics/run', { body: { machine_ids: machineIDs } }));
    if (data?.tasks) trackTasks(data, '诊断');
    if (data) await refreshTasks();
    return data;
  }, [apiV2, run, trackTasks, refreshTasks]);

  const saveSettings = useCallback(async () => {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(API_BASE_KEY, apiBase);
    toast.success('设置已保存');
    await refreshAll();
  }, [token, apiBase, refreshAll]);

  const clearToken = useCallback(() => {
    localStorage.removeItem(TOKEN_KEY);
    setToken('');
    toast.success('Token 已清除');
    if (strictAuth) {
      navigate('/login', { replace: true });
    }
  }, [strictAuth, navigate]);

  const value = {
    theme,
    toggleTheme,
    token,
    setToken,
    apiBase,
    setApiBase,
    loading,
    health,
    strictAuth,
    version: DEFAULT_VERSION,
    nodes,
    nodeMap,
    tasks,
    machines,
    ixProfiles,
    pendingTaskIds,
    getProfilePendingTaskIds,
    taskFilter,
    setTaskFilter,
    taskNodeFilter,
    setTaskNodeFilter,
    taskIxOnly,
    setTaskIxOnly,
    stats,
    showWizard,
    setShowWizard,
    showImportWizard,
    setShowImportWizard,
    streamLive,
    bootstrapped,
    run,
    refreshAll,
    refreshMachines,
    refreshIxProfiles,
    refreshTasks,
    refreshHealth,
    handleCopyValue,
    installMachine,
    createMachine,
    rotateMachineToken,
    createIxProfileFromWizard,
    importIxProfileFromWizard,
    applyIxProfile,
    syncIxProfile,
    refreshIxProfileCode,
    saveProfileRules,
    pauseIxProfile,
    resumeIxProfile,
    diagnoseIxProfile,
    fetchIxProfileCode,
    openProfile,
    runDiagnostics,
    saveSettings,
    clearToken,
    navigate,
  };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useApp() {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error('useApp must be used within AppProvider');
  return ctx;
}

export function getProfileById(profiles, id) {
  return profiles.find((p) => p.id === id) || null;
}
