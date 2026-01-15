import React, { useState, useEffect } from 'react';
import { DashboardLayout } from './components/dashboard/DashboardLayout';
import { AIConsole } from './components/dashboard/AIConsole';
import { SystemMonitor } from './components/dashboard/SystemMonitor';
import { BotManager } from './components/dashboard/BotManager';
import { CryptoTools } from './components/dashboard/CryptoTools';
import { FileExplorer } from './components/dashboard/FileExplorer';
import { LogViewer } from './components/dashboard/LogViewer';
import { BlockchainExplorer } from './components/dashboard/BlockchainExplorer';
import { Terminal } from './components/dashboard/Terminal';
import { Settings } from './components/dashboard/Settings';
import { motion } from 'framer-motion';
import { useConfig } from './store/config';
import { client } from './lib/client';
import { Login } from './components/auth/Login';
import { Loader2 } from 'lucide-react';

function App() {
  const [currentView, setCurrentView] = useState('dashboard');
  const { theme } = useConfig();
  const [session, setSession] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
  }, [theme]);

  useEffect(() => {
    const initAuth = async () => {
      try {
        const { data } = await client.auth.getSession();
        if (data?.session) {
          setSession(data.session);
        }
      } catch (error) {
        console.error("Failed to get session:", error);
      } finally {
        setLoading(false);
      }
    };

    initAuth();

    const authListener = client.auth.onAuthStateChange((_event, session) => {
      console.log("Auth state changed:", _event, session);
      setSession(session);
      setLoading(false); // Ensure loading is off when session is set
    });

    return () => {
      if (authListener && authListener.data && authListener.data.subscription) {
        authListener.data.subscription.unsubscribe();
      }
    };
  }, []);

  const renderContent = () => {
    switch (currentView) {
      case 'monitor':
        return <SystemMonitor />;
      case 'bots':
        return <BotManager />;
      case 'crypto':
        return <CryptoTools />;
      case 'blockchain':
        return <BlockchainExplorer />;
      case 'terminal':
        return <Terminal />;
      case 'files':
        return <FileExplorer />;
      case 'logs':
        return <LogViewer />;
      case 'settings':
        return <Settings />;
      case 'admin':
        return (
          <div className="space-y-6">
            <h2 className="text-2xl font-bold text-white">Admin Management Console</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="glass-panel p-6 rounded-xl border border-indigo-500/20">
                <h3 className="text-lg font-bold text-indigo-400 mb-4">User Accounts</h3>
                <div className="space-y-2">
                  <div className="flex justify-between p-2 bg-white/5 rounded">
                    <span>admin@sovereign.ai</span>
                    <span className="text-emerald-400 text-xs">ACTIVE</span>
                  </div>
                </div>
              </div>
              <div className="glass-panel p-6 rounded-xl border border-purple-500/20">
                <h3 className="text-lg font-bold text-purple-400 mb-4">Database Health</h3>
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                  <span className="text-sm font-mono text-gray-400">POSTGRES_MASTER: CONNECTED</span>
                </div>
              </div>
            </div>
          </div>
        );
      case 'dashboard':
      default:
        return (
          <div className="space-y-6">
            <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
              <div className="xl:col-span-2">
                <SystemMonitor />
              </div>
              <BlockchainExplorer />
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 h-[600px]">
              <AIConsole />
              <div className="flex flex-col gap-6">
                <Terminal />
                <div className="flex-1 overflow-hidden min-h-[250px]">
                  <FileExplorer />
                </div>
              </div>
            </div>
            <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
              <div className="xl:col-span-2">
                <BotManager />
              </div>
              <Settings />
            </div>
          </div>
        );
    }
  };

  // Ultra-robust render to prevent blank screens
  try {
    return (
      <DashboardLayout currentView={currentView} onNavigate={setCurrentView}>
        {renderContent()}
      </DashboardLayout>
    );
  } catch (err) {
    console.error("Critical Render Error:", err);
    return (
      <div className="min-h-screen bg-slate-900 text-white p-20 font-mono">
        <h1 className="text-red-500 text-2xl mb-4">SYSTEM RECOVERY MODE</h1>
        <p className="mb-4">A critical error occurred while rendering the dashboard.</p>
        <pre className="bg-black p-4 rounded border border-red-500/30 overflow-auto max-w-full">
          {err instanceof Error ? err.stack : String(err)}
        </pre>
        <button 
          onClick={() => window.location.reload()}
          className="mt-8 px-6 py-2 bg-indigo-600 rounded hover:bg-indigo-500"
        >
          REBOOT SYSTEM
        </button>
      </div>
    );
  }
}

export default App;
