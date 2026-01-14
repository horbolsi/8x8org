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
        setSession(data.session);
      } catch (error) {
        console.error("Failed to get session:", error);
      } finally {
        setLoading(false);
      }
    };

    initAuth();

    const authListener = client.auth.onAuthStateChange((_event, session) => {
      setSession(session);
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

  if (loading) {
    return (
      <div className="min-h-screen bg-black flex items-center justify-center">
        <Loader2 className="w-8 h-8 text-indigo-500 animate-spin" />
      </div>
    );
  }

  if (!session) {
    return <Login />;
  }

  return (
    <DashboardLayout currentView={currentView} onNavigate={setCurrentView}>
      {renderContent()}
    </DashboardLayout>
  );
}

export default App;
