import React, { useState, useEffect } from 'react';
import { Bot, Play, Square, RefreshCw, AlertCircle, MoreHorizontal, Terminal, Trash2 } from 'lucide-react';
import { cn } from '../../lib/utils';
import { motion, AnimatePresence } from 'framer-motion';
import { StorageService, type Bot as BotType } from '../../lib/storage';

export function BotManager() {
  const [bots, setBots] = useState<BotType[]>([]);
  const [deploying, setDeploying] = useState(false);

  useEffect(() => {
    const loadBots = async () => {
      const data = await StorageService.getBots();
      setBots(data);
    };
    loadBots();
  }, []);

  const saveBots = async (newBots: BotType[]) => {
    setBots(newBots);
    await StorageService.saveBots(newBots);
  };

  const toggleBot = (id: string) => {
    const newBots = bots.map(bot => {
      if (bot.id === id) {
        const newStatus = bot.status === 'running' ? 'stopped' : 'running';
        return {
          ...bot,
          status: newStatus,
          load: newStatus === 'running' ? '10%' : '0%',
          uptime: newStatus === 'running' ? '0m' : '-'
        } as BotType;
      }
      return bot;
    });
    saveBots(newBots);
  };

  const deleteBot = (id: string) => {
    const newBots = bots.filter(b => b.id !== id);
    saveBots(newBots);
  };

  const deployNew = () => {
    setDeploying(true);
    setTimeout(() => {
      const newBot: BotType = {
        id: `bot_${Date.now()}`,
        name: `Agent ${bots.length + 1}`,
        type: 'General',
        status: 'running',
        uptime: '0m',
        load: '5%'
      };
      saveBots([...bots, newBot]);
      setDeploying(false);
    }, 1500);
  };

  return (
    <div className="glass-panel rounded-xl p-6 border border-white/10 relative overflow-hidden">
      <div className="absolute top-0 right-0 p-4 opacity-5 pointer-events-none">
        <Bot className="w-64 h-64 text-indigo-500" />
      </div>

      <div className="flex items-center justify-between mb-8 relative z-10">
        <div>
          <h3 className="font-bold text-white flex items-center gap-2 text-lg">
            <Bot className="w-5 h-5 text-indigo-400" />
            Autonomous Agents
          </h3>
          <p className="text-xs text-gray-500 mt-1 font-mono">Manage and monitor active bot instances</p>
        </div>
        <button 
          onClick={deployNew}
          disabled={deploying}
          className="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-medium rounded-lg transition-all shadow-lg shadow-indigo-500/20 flex items-center gap-2 group disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {deploying ? <RefreshCw className="w-3 h-3 animate-spin" /> : <Play className="w-3 h-3 group-hover:scale-110 transition-transform" />}
          {deploying ? 'Deploying...' : 'Deploy New Agent'}
        </button>
      </div>

      <div className="overflow-hidden rounded-xl border border-white/10 bg-slate-900/40 backdrop-blur-sm relative z-10">
        <table className="w-full text-sm text-left">
          <thead className="bg-white/5 text-gray-400 font-mono text-xs uppercase tracking-wider">
            <tr>
              <th className="px-6 py-4 font-medium">Bot Name</th>
              <th className="px-6 py-4 font-medium">Type</th>
              <th className="px-6 py-4 font-medium">Status</th>
              <th className="px-6 py-4 font-medium">Load</th>
              <th className="px-6 py-4 font-medium">Uptime</th>
              <th className="px-6 py-4 font-medium text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            <AnimatePresence>
              {bots.map((bot, index) => (
                <motion.tr 
                  key={bot.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: 20 }}
                  transition={{ delay: index * 0.05 }}
                  className="hover:bg-white/5 transition-colors group"
                >
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-lg bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400">
                        <Terminal size={16} />
                      </div>
                      <div>
                        <div className="font-medium text-white group-hover:text-indigo-300 transition-colors">{bot.name}</div>
                        <div className="text-[10px] text-gray-500 font-mono">{bot.id}</div>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <span className="px-2 py-1 rounded text-xs bg-white/5 text-gray-300 border border-white/10">
                      {bot.type}
                    </span>
                  </td>
                  <td className="px-6 py-4">
                    <StatusBadge status={bot.status} />
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-2">
                      <div className="w-16 h-1.5 bg-slate-800 rounded-full overflow-hidden">
                        <motion.div 
                          className={cn("h-full rounded-full", 
                            bot.status === 'running' ? "bg-indigo-500" : "bg-gray-600"
                          )} 
                          initial={{ width: 0 }}
                          animate={{ width: bot.load }}
                          transition={{ duration: 1 }}
                        />
                      </div>
                      <span className="text-xs font-mono text-gray-500">{bot.load}</span>
                    </div>
                  </td>
                  <td className="px-6 py-4 font-mono text-gray-400 text-xs">{bot.uptime}</td>
                  <td className="px-6 py-4 text-right">
                    <div className="flex items-center justify-end gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                      <button 
                        onClick={() => toggleBot(bot.id)}
                        className={cn(
                          "p-2 rounded-lg transition-colors",
                          bot.status === 'running' 
                            ? "hover:bg-red-500/20 text-gray-400 hover:text-red-400" 
                            : "hover:bg-emerald-500/20 text-gray-400 hover:text-emerald-400"
                        )}
                        title={bot.status === 'running' ? 'Stop' : 'Start'}
                      >
                        {bot.status === 'running' ? <Square className="w-4 h-4" /> : <Play className="w-4 h-4" />}
                      </button>
                      <button 
                        onClick={() => deleteBot(bot.id)}
                        className="p-2 hover:bg-red-500/20 rounded-lg text-gray-400 hover:text-red-400 transition-colors"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </motion.tr>
              ))}
            </AnimatePresence>
            {bots.length === 0 && (
              <tr>
                <td colSpan={6} className="px-6 py-8 text-center text-gray-500 italic">
                  No active agents. Deploy a new one to get started.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles = {
    running: "bg-emerald-500/10 text-emerald-400 border-emerald-500/20 shadow-[0_0_10px_rgba(16,185,129,0.2)]",
    stopped: "bg-gray-500/10 text-gray-400 border-gray-500/20",
    error: "bg-red-500/10 text-red-400 border-red-500/20 shadow-[0_0_10px_rgba(239,68,68,0.2)]",
  };

  const icons = {
    running: <Play className="w-3 h-3 fill-current" />,
    stopped: <Square className="w-3 h-3 fill-current" />,
    error: <AlertCircle className="w-3 h-3" />,
  };

  return (
    <div className={cn(
      "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-[10px] font-medium uppercase tracking-wider transition-all duration-300",
      styles[status as keyof typeof styles]
    )}>
      {icons[status as keyof typeof icons]}
      {status}
    </div>
  );
}
