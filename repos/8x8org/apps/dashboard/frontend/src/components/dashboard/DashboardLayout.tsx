import React, { useEffect, useState } from 'react';
import { Terminal, Activity, Cpu, Shield, FolderOpen, Settings, Menu, Bell, ScrollText, Blocks, Box, ChevronRight, X, Award, User } from 'lucide-react';
import { cn } from '../../lib/utils';
import { motion, AnimatePresence } from 'framer-motion';

interface DashboardLayoutProps {
  children: React.ReactNode;
  currentView: string;
  onNavigate: (view: string) => void;
}

export function DashboardLayout({ children, currentView, onNavigate }: DashboardLayoutProps) {
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const checkMobile = () => {
      const mobile = window.innerWidth < 1024;
      setIsMobile(mobile);
      if (mobile) setSidebarOpen(false);
      else setSidebarOpen(true);
    };
    
    checkMobile();
    window.addEventListener('resize', checkMobile);
    return () => window.removeEventListener('resize', checkMobile);
  }, []);

  const toggleSidebar = () => setSidebarOpen(!sidebarOpen);

  return (
    <div className="min-h-screen text-gray-100 relative overflow-hidden bg-[var(--bg-deep)] font-sans selection:bg-indigo-500/30">
      {/* Matrix Background - Fixed in CSS to be pointer-events-none */}
      <div className="matrix-bg" />

      {/* Mobile Overlay */}
      <AnimatePresence>
        {isMobile && sidebarOpen && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setSidebarOpen(false)}
            className="fixed inset-0 bg-black/60 backdrop-blur-sm z-40 lg:hidden"
          />
        )}
      </AnimatePresence>

      {/* Sidebar */}
      <motion.aside 
        initial={false}
        animate={{ 
          x: sidebarOpen ? 0 : -280,
        }}
        transition={{ type: "spring", stiffness: 300, damping: 30 }}
        className="fixed left-0 top-0 bottom-0 z-50 w-[280px] glass-panel border-r border-white/5 overflow-hidden shadow-2xl"
      >
        <div className="h-full flex flex-col overflow-y-auto custom-scrollbar bg-slate-900/95 backdrop-blur-xl">
          {/* Logo Area */}
          <div className="p-6 flex items-center justify-between border-b border-white/5 sticky top-0 z-10 bg-slate-900/50 backdrop-blur-xl">
            <div className="flex items-center gap-4">
              <div className="relative group">
                <div className="absolute -inset-1 bg-gradient-to-r from-indigo-500 to-purple-600 rounded-lg blur opacity-25 group-hover:opacity-75 transition duration-1000 group-hover:duration-200" />
                <div className="relative p-2 bg-slate-900 rounded-lg border border-white/10">
                  <Shield className="w-6 h-6 text-indigo-400" />
                </div>
              </div>
              <div className="flex flex-col">
                <h1 className="font-bold text-lg tracking-wider text-white">SOVEREIGN</h1>
                <div className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                  <p className="text-[10px] text-emerald-400 font-mono tracking-widest uppercase">System Online</p>
                </div>
              </div>
            </div>
            {isMobile && (
              <button onClick={() => setSidebarOpen(false)} className="p-1 hover:bg-white/10 rounded-lg">
                <X className="w-5 h-5 text-gray-400" />
              </button>
            )}
          </div>

          {/* Navigation */}
          <nav className="flex-1 p-4 space-y-8">
            <NavGroup title="Core Operations">
              <NavItem icon={<Terminal />} label="Dashboard" active={currentView === 'dashboard'} onClick={() => { onNavigate('dashboard'); if(isMobile) setSidebarOpen(false); }} />
              <NavItem icon={<Award />} label="Missions" active={currentView === 'tasks'} onClick={() => { onNavigate('tasks'); if(isMobile) setSidebarOpen(false); }} />
              <NavItem icon={<Activity />} label="System Monitor" active={currentView === 'monitor'} onClick={() => { onNavigate('monitor'); if(isMobile) setSidebarOpen(false); }} />
              <NavItem icon={<Cpu />} label="Bot Manager" active={currentView === 'bots'} onClick={() => { onNavigate('bots'); if(isMobile) setSidebarOpen(false); }} />
            </NavGroup>
            
            <NavGroup title="Financial Tools">
              <NavItem icon={<Shield />} label="Crypto Tools" active={currentView === 'crypto'} onClick={() => { onNavigate('crypto'); if(isMobile) setSidebarOpen(false); }} />
              <NavItem icon={<Blocks />} label="Blockchain" active={currentView === 'blockchain'} onClick={() => { onNavigate('blockchain'); if(isMobile) setSidebarOpen(false); }} />
              <NavItem icon={<Box />} label="Terminal" active={currentView === 'terminal'} onClick={() => { onNavigate('terminal'); if(isMobile) setSidebarOpen(false); }} />
            </NavGroup>
            
            <NavGroup title="System">
              <NavItem icon={<FolderOpen />} label="File Explorer" active={currentView === 'files'} onClick={() => { onNavigate('files'); if(isMobile) setSidebarOpen(false); }} />
              <NavItem icon={<ScrollText />} label="System Logs" active={currentView === 'logs'} onClick={() => { onNavigate('logs'); if(isMobile) setSidebarOpen(false); }} />
              <NavItem icon={<User />} label="Identity" active={currentView === 'profile'} onClick={() => { onNavigate('profile'); if(isMobile) setSidebarOpen(false); }} />
            </NavGroup>
          </nav>

          {/* Footer */}
          <div className="p-4 border-t border-white/5 bg-slate-900/30">
            <NavItem icon={<Settings />} label="Settings" active={currentView === 'settings'} onClick={() => { onNavigate('settings'); if(isMobile) setSidebarOpen(false); }} />
            <div className="mt-4 px-4 py-3 rounded-xl bg-gradient-to-br from-indigo-500/10 to-purple-500/10 border border-white/5">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs text-gray-400">CPU Usage</span>
                <span className="text-xs font-mono text-indigo-400">34%</span>
              </div>
              <div className="h-1 bg-slate-800 rounded-full overflow-hidden">
                <motion.div 
                  className="h-full bg-indigo-500"
                  initial={{ width: 0 }}
                  animate={{ width: '34%' }}
                  transition={{ duration: 2, repeat: Infinity, repeatType: "reverse" }}
                />
              </div>
            </div>
          </div>
        </div>
      </motion.aside>

      {/* Main Content */}
      <main 
        className={cn(
          "min-h-screen flex flex-col transition-all duration-300 ease-[cubic-bezier(0.25,0.1,0.25,1.0)]",
          !isMobile && sidebarOpen ? "pl-[280px]" : "pl-0"
        )}
      >
        {/* Header */}
        <header className="h-20 px-4 sm:px-8 flex items-center justify-between sticky top-0 z-30 bg-[var(--bg-deep)]/80 backdrop-blur-md border-b border-white/5">
          <div className="flex items-center gap-4">
            <button 
              onClick={toggleSidebar}
              className="p-2 hover:bg-white/5 rounded-lg transition-colors text-gray-400 hover:text-white"
            >
              <Menu className="w-5 h-5" />
            </button>
            
            <div className="h-6 w-px bg-white/10 mx-2 hidden sm:block" />
            
            <div className="flex items-center gap-2 text-sm text-gray-400">
              <span className="opacity-50 hidden sm:inline">Console</span>
              <ChevronRight className="w-4 h-4 opacity-30 hidden sm:inline" />
              <span className="text-white font-medium capitalize truncate max-w-[150px]">{currentView.replace('-', ' ')}</span>
            </div>
          </div>

          <div className="flex items-center gap-4 sm:gap-6">
            <div className="flex items-center gap-4">
              <button className="p-2 hover:bg-white/5 rounded-lg transition-colors relative group">
                <Bell className="w-5 h-5 text-gray-400 group-hover:text-white transition-colors" />
                <span className="absolute top-2 right-2 w-2 h-2 bg-indigo-500 rounded-full ring-4 ring-[var(--bg-deep)]" />
              </button>
            </div>
            
            <div className="h-8 w-px bg-white/10 hidden sm:block" />
            
            <div className="flex items-center gap-3 pl-2">
              <div className="text-right hidden sm:block">
                <div className="text-sm font-medium text-white">Admin User</div>
                <div className="text-xs text-gray-500 font-mono">ID: 0x8...3F2</div>
              </div>
              <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-500 to-purple-500 p-[1px]">
                <div className="w-full h-full rounded-[10px] bg-slate-900 flex items-center justify-center">
                  <span className="font-bold text-indigo-400">A</span>
                </div>
              </div>
            </div>
          </div>
        </header>

        {/* Page Content */}
        <div className="flex-1 p-4 sm:p-8 overflow-x-hidden relative z-0">
          <AnimatePresence mode="wait">
            <motion.div
              key={currentView}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.2 }}
              className="max-w-7xl mx-auto"
            >
              {children}
            </motion.div>
          </AnimatePresence>
        </div>
      </main>
    </div>
  );
}

function NavGroup({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-2">
      <h3 className="px-4 text-xs font-semibold text-gray-500 uppercase tracking-wider">{title}</h3>
      <div className="space-y-1">
        {children}
      </div>
    </div>
  );
}

function NavItem({ icon, label, active, onClick }: { icon: React.ReactNode; label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "w-full flex items-center gap-3 px-4 py-2.5 rounded-lg transition-all duration-200 group relative overflow-hidden",
        active 
          ? "bg-indigo-500/10 text-white shadow-[0_0_20px_rgba(99,102,241,0.1)]" 
          : "text-gray-400 hover:text-white hover:bg-white/5"
      )}
    >
      {active && (
        <motion.div
          layoutId="activeNav"
          className="absolute left-0 top-0 bottom-0 w-1 bg-indigo-500 rounded-r-full"
        />
      )}
      <div className={cn(
        "transition-colors duration-200",
        active ? "text-indigo-400" : "text-gray-500 group-hover:text-gray-300"
      )}>
        {React.cloneElement(icon as React.ReactElement, { size: 18 })}
      </div>
      <span className="font-medium text-sm">{label}</span>
    </button>
  );
}
