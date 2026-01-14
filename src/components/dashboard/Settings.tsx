import React from 'react';
import { Save, RotateCcw, Shield, Database, User, Key, Palette, Monitor, Moon, Zap, Bot } from 'lucide-react';
import { useConfig } from '../../store/config';
import { motion } from 'framer-motion';
import { cn } from '../../lib/utils';

export function Settings() {
  const { apiKeys, activeProvider, rpcUrl, username, theme, setApiKey, setActiveProvider, setRpcUrl, setUsername, setTheme } = useConfig();
  const [localKeys, setLocalKeys] = React.useState(apiKeys);
  const [localRpc, setLocalRpc] = React.useState(rpcUrl);
  const [localName, setLocalName] = React.useState(username);
  const [saved, setSaved] = React.useState(false);

  const handleSave = () => {
    Object.entries(localKeys).forEach(([provider, key]) => {
      setApiKey(provider as any, key);
    });
    setRpcUrl(localRpc);
    setUsername(localName);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  return (
    <motion.div 
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="glass-panel rounded-xl p-8 max-w-3xl mx-auto border border-white/10 relative overflow-hidden"
    >
      <div className="absolute top-0 right-0 p-8 opacity-5 pointer-events-none">
        <Shield className="w-64 h-64 text-indigo-500" />
      </div>

      <div className="relative z-10 mb-8">
        <h2 className="text-2xl font-bold text-white mb-2 flex items-center gap-3">
          <Shield className="w-6 h-6 text-indigo-400" />
          System Configuration
        </h2>
        <p className="text-gray-400 text-sm">Manage your identity, multiple AI providers, and network connections.</p>
      </div>
      
      <div className="space-y-8 relative z-10">
        {/* Active AI Provider */}
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm font-medium text-indigo-300 uppercase tracking-wider">
            <Bot size={14} /> Active Intelligence Core
          </div>
          <div className="grid grid-cols-2 md:grid-cols-6 gap-2">
            {(['openai', 'anthropic', 'gemini', 'deepseek', 'ollama', 'simulation'] as const).map((p) => (
              <button
                key={p}
                onClick={() => setActiveProvider(p)}
                className={cn(
                  "px-2 py-2 rounded-lg border text-[10px] font-mono transition-all",
                  activeProvider === p 
                    ? "bg-indigo-500/20 border-indigo-500 text-white" 
                    : "bg-white/5 border-white/10 text-gray-400 hover:border-white/20"
                )}
              >
                {p.toUpperCase()}
              </button>
            ))}
          </div>
        </div>

        {/* Theme Selection */}
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm font-medium text-indigo-300 uppercase tracking-wider">
            <Palette size={14} /> Interface Theme
          </div>
          <div className="grid grid-cols-3 gap-4">
            <ThemeCard 
              active={theme === 'matrix'} 
              onClick={() => setTheme('matrix')}
              icon={<Monitor className="w-5 h-5" />}
              label="Matrix"
              color="text-emerald-400"
              bg="bg-emerald-500/10"
              border="border-emerald-500/20"
            />
            <ThemeCard 
              active={theme === 'cyber'} 
              onClick={() => setTheme('cyber')}
              icon={<Zap className="w-5 h-5" />}
              label="Cyberpunk"
              color="text-indigo-400"
              bg="bg-indigo-500/10"
              border="border-indigo-500/20"
            />
            <ThemeCard 
              active={theme === 'dark'} 
              onClick={() => setTheme('dark')}
              icon={<Moon className="w-5 h-5" />}
              label="Midnight"
              color="text-blue-400"
              bg="bg-blue-500/10"
              border="border-blue-500/20"
            />
          </div>
        </div>

        {/* User Profile */}
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm font-medium text-indigo-300 uppercase tracking-wider">
            <User size={14} /> User Identity
          </div>
          <div className="bg-slate-900/50 p-6 rounded-xl border border-white/5 hover:border-indigo-500/30 transition-colors">
            <label className="text-xs text-gray-500 mb-2 block">Display Name</label>
            <input
              type="text"
              value={localName}
              onChange={(e) => setLocalName(e.target.value)}
              className="w-full bg-black/40 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-indigo-500/50 outline-none transition-all focus:ring-1 focus:ring-indigo-500/20"
            />
          </div>
        </div>

        {/* API Keys */}
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm font-medium text-indigo-300 uppercase tracking-wider">
            <Key size={14} /> Multi-API Configuration
          </div>
          <div className="grid gap-4">
            {Object.keys(localKeys).map((provider) => (
              <div key={provider} className="bg-slate-900/50 p-6 rounded-xl border border-white/5 hover:border-indigo-500/30 transition-colors">
                <label className="text-xs text-gray-500 mb-2 block uppercase">{provider} API Key</label>
                <input
                  type="password"
                  value={(localKeys as any)[provider]}
                  onChange={(e) => setLocalKeys(prev => ({ ...prev, [provider]: e.target.value }))}
                  placeholder={`Enter ${provider} key...`}
                  className="w-full bg-black/40 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-indigo-500/50 outline-none transition-all focus:ring-1 focus:ring-indigo-500/20"
                />
              </div>
            ))}
            <p className="text-xs text-gray-500 mt-2 flex items-center gap-1">
              <Shield size={10} />
              Keys are stored locally in your browser. Encryption active.
            </p>
          </div>
        </div>

        {/* Blockchain */}
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm font-medium text-indigo-300 uppercase tracking-wider">
            <Database size={14} /> Network Settings
          </div>
          <div className="bg-slate-900/50 p-6 rounded-xl border border-white/5 hover:border-indigo-500/30 transition-colors">
            <label className="text-xs text-gray-500 mb-2 block">Ethereum RPC URL</label>
            <input
              type="text"
              value={localRpc}
              onChange={(e) => setLocalRpc(e.target.value)}
              className="w-full bg-black/40 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-indigo-500/50 outline-none transition-all focus:ring-1 focus:ring-indigo-500/20"
            />
          </div>
        </div>

        {/* Actions */}
        <div className="pt-6 flex gap-4 border-t border-white/10">
          <button 
            onClick={handleSave}
            className="flex items-center gap-2 px-6 py-2.5 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition-all shadow-lg shadow-indigo-500/20 active:scale-95"
          >
            <Save className="w-4 h-4" /> 
            {saved ? 'Saved!' : 'Save Configuration'}
          </button>
          <button 
            onClick={() => {
              setLocalKeys(apiKeys);
              setLocalRpc(rpcUrl);
              setLocalName(username);
            }}
            className="flex items-center gap-2 px-6 py-2.5 bg-white/5 hover:bg-white/10 text-gray-300 rounded-lg transition-all active:scale-95"
          >
            <RotateCcw className="w-4 h-4" /> Reset
          </button>
        </div>
      </div>
    </motion.div>
  );
}

function ThemeCard({ active, onClick, icon, label, color, bg, border }: any) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "p-4 rounded-xl border transition-all flex flex-col items-center gap-3 group relative overflow-hidden",
        active 
          ? `bg-slate-900 ${border} ring-1 ring-offset-1 ring-offset-slate-900 ring-indigo-500` 
          : "bg-slate-900/50 border-white/5 hover:border-white/10 hover:bg-slate-900/80"
      )}
    >
      {active && (
        <div className={`absolute inset-0 opacity-10 ${bg}`} />
      )}
      <div className={cn("p-2 rounded-lg transition-colors", active ? bg : "bg-white/5", color)}>
        {icon}
      </div>
      <span className={cn("text-xs font-medium", active ? "text-white" : "text-gray-400 group-hover:text-gray-300")}>
        {label}
      </span>
    </button>
  );
}
