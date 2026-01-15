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
import { Shield, Loader2 } from 'lucide-react';

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
            <h2 className="text-2xl font-bold text-white flex items-center gap-3">
              <Shield className="w-6 h-6 text-indigo-400" />
              Admin Management Console
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <div className="glass-panel p-6 rounded-xl border border-indigo-500/20">
                <h3 className="text-lg font-bold text-indigo-400 mb-4">User Accounts</h3>
                <div className="space-y-2">
                  <div className="flex justify-between p-3 bg-white/5 rounded-lg border border-white/5">
                    <div className="flex flex-col">
                      <span className="text-sm font-medium">admin@sovereign.ai</span>
                      <span className="text-[10px] text-indigo-400 font-mono uppercase">Master Admin</span>
                    </div>
                    <span className="text-emerald-400 text-xs font-bold self-center">ACTIVE</span>
                  </div>
                </div>
              </div>
              <div className="glass-panel p-6 rounded-xl border border-purple-500/20">
                <h3 className="text-lg font-bold text-purple-400 mb-4">Database Health</h3>
                <div className="space-y-4">
                  <div className="flex items-center gap-3">
                    <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                    <span className="text-sm font-mono text-gray-400">POSTGRES_MASTER: CONNECTED</span>
                  </div>
                  <div className="h-1.5 bg-white/5 rounded-full overflow-hidden">
                    <div className="h-full bg-purple-500 w-[85%]" />
                  </div>
                  <p className="text-[10px] text-gray-500 uppercase tracking-widest font-mono">Storage: 8.5GB / 10GB</p>
                </div>
              </div>
              <div className="glass-panel p-6 rounded-xl border border-amber-500/20">
                <h3 className="text-lg font-bold text-amber-400 mb-4">AI Nodes</h3>
                <div className="space-y-2 text-xs font-mono text-gray-400">
                  <div className="flex justify-between"><span>Ollama Local:</span> <span className="text-emerald-500">ONLINE</span></div>
                  <div className="flex justify-between"><span>DeepSeek API:</span> <span className="text-emerald-500">ONLINE</span></div>
                  <div className="flex justify-between"><span>OpenAI Cloud:</span> <span className="text-emerald-500">ONLINE</span></div>
                </div>
              </div>
            </div>
          </div>
        );
      case 'dashboard':
      default:
        return (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 pb-6">
            {/* Column 1: Interactive & Command */}
            <div className="space-y-6">
              <AIConsole />
              <Terminal />
            </div>

            {/* Column 2: Monitoring & Management */}
            <div className="space-y-6">
              <SystemMonitor />
              <BotManager />
              <LogViewer />
            </div>

            {/* Column 3: Tools & Data */}
            <div className="space-y-6">
              <CryptoTools />
              <BlockchainExplorer />
              <FileExplorer />
              
              {/* Quick Actions Panel */}
              <motion.div 
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.5 }}
                className="glass-panel rounded-xl p-6 border border-white/10"
              >
                <h3 className="font-bold text-white mb-4 flex items-center gap-2">
                  <span className="w-1.5 h-4 bg-indigo-500 rounded-full" />
                  Quick Actions
                </h3>
                <div className="grid grid-cols-2 gap-3">
                  <button className="p-3 bg-indigo-500/10 hover:bg-indigo-500/20 border border-indigo-500/20 rounded-lg text-indigo-300 text-sm transition-all hover:scale-105 active:scale-95">
                    Deploy Bot
                  </button>
                  <button className="p-3 bg-emerald-500/10 hover:bg-emerald-500/20 border border-emerald-500/20 rounded-lg text-emerald-300 text-sm transition-all hover:scale-105 active:scale-95">
                    Run Diagnostics
                  </button>
                  <button className="p-3 bg-purple-500/10 hover:bg-purple-500/20 border border-purple-500/20 rounded-lg text-purple-300 text-sm transition-all hover:scale-105 active:scale-95">
                    View Analytics
                  </button>
                  <button className="p-3 bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 rounded-lg text-blue-300 text-sm transition-all hover:scale-105 active:scale-95">
                    System Update
                  </button>
                </div>
              </motion.div>
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
