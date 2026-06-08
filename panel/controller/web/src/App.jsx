import { Navigate, Route, Routes, useLocation, useParams } from 'react-router-dom';
import Layout from './components/Layout.jsx';
import CreateProfileWizard from './components/CreateProfileWizard.jsx';
import ImportCodeWizard from './components/ImportCodeWizard.jsx';
import Card from './components/Card.jsx';
import Dashboard from './pages/Dashboard.jsx';
import Machines from './pages/Machines.jsx';
import Profiles from './pages/Profiles.jsx';
import ProfileDetail from './pages/ProfileDetail.jsx';
import Diagnostics from './pages/Diagnostics.jsx';
import Tasks from './pages/Tasks.jsx';
import Settings from './pages/Settings.jsx';
import { AppProvider, getProfileById, useApp } from './context/AppContext.jsx';

function LoginGate({ children }) {
  const { strictAuth, token } = useApp();
  const location = useLocation();
  if (strictAuth && !token && location.pathname !== '/settings') {
    return <Navigate to="/settings" replace state={{ from: location.pathname }} />;
  }
  return children;
}

function ProfileDetailRoute() {
  const { id } = useParams();
  const {
    ixProfiles,
    machines,
    pendingTaskIds,
    loading,
    applyIxProfile,
    syncIxProfile,
    refreshIxProfileCode,
    saveProfileRules,
    navigate,
  } = useApp();
  const profile = getProfileById(ixProfiles, id);
  const machine = machines.find((m) => m.id === profile?.machine_id) || null;

  if (!profile) {
    return (
      <Card title="线路不存在" description="该线路可能已被删除或尚未加载。">
        <div className="actions">
          <button type="button" onClick={() => navigate('/profiles')}>返回线路列表</button>
        </div>
      </Card>
    );
  }

  return (
    <ProfileDetail
      profile={profile}
      machine={machine}
      pendingTaskIds={pendingTaskIds}
      onBack={() => navigate('/profiles')}
      onApply={applyIxProfile}
      onSync={syncIxProfile}
      onRefreshCode={refreshIxProfileCode}
      onSaveRules={saveProfileRules}
      loading={loading}
    />
  );
}

function AppRoutes() {
  const ctx = useApp();
  const {
    stats,
    machines,
    ixProfiles,
    tasks,
    nodes,
    nodeMap,
    loading,
    showWizard,
    setShowWizard,
    showImportWizard,
    setShowImportWizard,
    taskFilter,
    setTaskFilter,
    taskNodeFilter,
    setTaskNodeFilter,
    taskIxOnly,
    setTaskIxOnly,
    refreshAll,
    refreshMachines,
    refreshIxProfiles,
    refreshTasks,
    handleCopyValue,
    createIxProfileFromWizard,
    importIxProfileFromWizard,
    applyIxProfile,
    syncIxProfile,
    openProfile,
    runDiagnostics,
    navigate,
  } = ctx;

  return (
    <>
      <CreateProfileWizard
        open={showWizard}
        machines={machines}
        loading={loading}
        onClose={() => setShowWizard(false)}
        onSubmit={createIxProfileFromWizard}
      />
      <ImportCodeWizard
        open={showImportWizard}
        machines={machines}
        loading={loading}
        onClose={() => setShowImportWizard(false)}
        onSubmit={importIxProfileFromWizard}
      />
      <Routes>
        <Route
          path="/dashboard"
          element={(
            <Dashboard
              stats={stats}
              machines={machines}
              profiles={ixProfiles}
              tasks={tasks}
              nodes={nodes}
              onNavigate={(path) => navigate(path.startsWith('/') ? path : `/${path}`)}
              onOpenAddNode={() => navigate('/machines')}
              onOpenWizard={() => setShowWizard(true)}
              onOpenImport={() => setShowImportWizard(true)}
              onOpenProfile={openProfile}
              onRefresh={() => ctx.run('刷新', refreshAll)}
            />
          )}
        />
        <Route path="/machines" element={<Machines />} />
        <Route
          path="/profiles"
          element={(
            <Profiles
              profiles={ixProfiles}
              machines={machines}
              onRefresh={refreshIxProfiles}
              onOpenWizard={() => setShowWizard(true)}
              onCreate={() => setShowWizard(true)}
              onApply={applyIxProfile}
              onSync={syncIxProfile}
              onOpen={openProfile}
              loading={loading}
            />
          )}
        />
        <Route path="/profiles/:id" element={<ProfileDetailRoute />} />
        <Route
          path="/tasks"
          element={(
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
          )}
        />
        <Route
          path="/diagnostics"
          element={(
            <Diagnostics
              machines={machines}
              tasks={tasks}
              onRunDiagnostics={runDiagnostics}
              onCopy={handleCopyValue}
              onRefresh={refreshTasks}
              loading={loading}
            />
          )}
        />
        <Route path="/settings" element={<Settings />} />
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </>
  );
}

export default function App() {
  return (
    <AppProvider>
      <LoginGate>
        <Layout>
          <AppRoutes />
        </Layout>
      </LoginGate>
    </AppProvider>
  );
}
