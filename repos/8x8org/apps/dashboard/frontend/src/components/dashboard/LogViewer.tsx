import React, { useEffect, useState, useRef } from 'react';
import { ScrollText, Terminal, AlertTriangle, Info, CheckCircle, Bug } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

interface Log {
  id: number;
  timestamp: string;
  level: 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';
  message: string;
}

export function LogViewer() {
  const [logs, setLogs] = useState<Log[]>([]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [filter, setFilter] = useState<'ALL' | 'INFO' | 'WARN' | 'ERROR'>('ALL');

  useEffect(() => {
    // Initial logs
    setLogs([
      { id: 1, timestamp: new Date().toISOString(), level: 'INFO', message: 'System initialized' },
      { id: 2, timestamp: new Date().toISOString(), level: 'INFO', message: 'AI Core loaded' },
      { id: 3, timestamp: new Date().toISOString(), level: 'DEBUG', message: 'Connecting to blockchain nodes...' },
    ]);

    const interval = setInterval(() => {
      const actions = [
        'Processing neural block',
        'Syncing ledger state',
        'Bot heartbeat received',
        'Optimizing memory usage',
        'Network packet analyzed',
        'Updating crypto rates',
        'Garbage collection started',
        'Cache invalidated'
      ];
      const levels: ('INFO' | 'DEBUG')[] = ['INFO', 'DEBUG', 'INFO', 'INFO'];
      
      const newLog: Log = {
        id: Date.now(),
        timestamp: new Date().toISOString(),
        level: Math.random() > 0.9 ? 'WARN' : (Math.random() > 0.95 ? 'ERROR' : levels[Math.floor(Math.random() * levels.length)]),
        message: actions[Math.floor(Math.random() * actions.length)]
      };

      setLogs(prev => [...prev.slice(-99), newLog]);
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs]);

  const filteredLogs = filter === 'ALL' ? logs : logs.filter(l => l.level === filter);

  return (
    <div className="glass-panel rounded-xl p-6 h-[400px] flex flex-col border border-white/10 relative overflow-hidden">
      <div className="absolute top-0 right-0 p-4 opacity-5 pointer-events-none">
        <ScrollText className="w-32 h-32 text-indigo-500" />
      </div>

      <div className="flex items-center justify-between mb-4 relative z-10">
        <h3 className="font-bold text-white flex items-center gap-2">
          <ScrollText className="w-5 h-5 text-indigo-400" />
          System Logs
        </h3>
        <div className="flex gap-1 bg-black/20 p-1 rounded-lg border border-white/5">
          {(['ALL', 'INFO', 'WARN', 'ERROR'] as const).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1 rounded-md text-[10px] font-mono transition-all ${
                filter === f 
                  ? 'bg-indigo-500 text-white shadow-lg shadow-indigo-500/20' 
                  : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
              }`}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      <div 
        ref={scrollRef}
        className="flex-1 overflow-y-auto font-mono text-xs space-y-1 pr-2 custom-scrollbar bg-black/40 rounded-lg p-4 border border-white/5 relative z-10"
      >
        <AnimatePresence initial={false}>
          {filteredLogs.map((log) => (
            <motion.div 
              key={log.id} 
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              className="flex gap-3 hover:bg-white/5 p-1.5 rounded transition-colors group"
            >
              <span className="text-gray-600 shrink-0 select-none">
                {log.timestamp.split('T')[1].split('.')[0]}
              </span>
              <span className={`shrink-0 w-14 font-bold flex items-center gap-1.5 ${
                log.level === 'INFO' ? 'text-blue-400' :
                log.level === 'WARN' ? 'text-yellow-400' :
                log.level === 'ERROR' ? 'text-red-400' : 'text-gray-400'
              }`}>
                {log.level === 'INFO' && <Info size={10} />}
                {log.level === 'WARN' && <AlertTriangle size={10} />}
                {log.level === 'ERROR' && <Bug size={10} />}
                {log.level === 'DEBUG' && <Terminal size={10} />}
                {log.level}
              </span>
              <span className="text-gray-300 group-hover:text-white transition-colors break-all">
                {log.message}
              </span>
            </motion.div>
          ))}
        </AnimatePresence>
        {filteredLogs.length === 0 && (
          <div className="text-center text-gray-600 py-8 italic">No logs found for this filter</div>
        )}
      </div>
    </div>
  );
}
