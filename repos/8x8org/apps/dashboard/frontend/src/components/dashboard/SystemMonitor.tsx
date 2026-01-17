import React, { useState, useEffect } from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { Activity, HardDrive, Cpu, Zap, Wifi } from 'lucide-react';
import { motion } from 'framer-motion';

export function SystemMonitor() {
  const [data, setData] = useState<any[]>([]);

  useEffect(() => {
    const interval = setInterval(() => {
      setData(prev => {
        const newPoint = {
          time: new Date().toLocaleTimeString(),
          cpu: Math.floor(Math.random() * 30) + 10,
          memory: Math.floor(Math.random() * 20) + 40,
          network: Math.floor(Math.random() * 50) + 20,
        };
        const newData = [...prev, newPoint];
        if (newData.length > 20) newData.shift();
        return newData;
      });
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="glass-panel rounded-xl p-6 space-y-6 border border-white/10 relative overflow-hidden">
      <div className="absolute top-0 right-0 p-4 opacity-20 pointer-events-none">
        <Activity className="w-32 h-32 text-indigo-500" />
      </div>

      <div className="flex items-center justify-between relative z-10">
        <div>
          <h3 className="font-bold text-white flex items-center gap-2 text-lg">
            <Activity className="w-5 h-5 text-indigo-400" />
            System Resources
          </h3>
          <p className="text-xs text-gray-500 mt-1 font-mono">Real-time performance metrics</p>
        </div>
        <div className="flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20">
          <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
          <span className="text-xs font-mono text-emerald-400 font-bold tracking-wider">LIVE MONITORING</span>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4 relative z-10">
        <MetricCard 
          icon={<Cpu />} 
          label="CPU Usage" 
          value={`${data[data.length - 1]?.cpu || 0}%`} 
          color="text-indigo-400" 
          bg="bg-indigo-500/10"
          border="border-indigo-500/20"
        />
        <MetricCard 
          icon={<HardDrive />} 
          label="Memory" 
          value={`${data[data.length - 1]?.memory || 0}%`} 
          color="text-purple-400" 
          bg="bg-purple-500/10"
          border="border-purple-500/20"
        />
        <MetricCard 
          icon={<Wifi />} 
          label="Network" 
          value={`${data[data.length - 1]?.network || 0} MB/s`} 
          color="text-emerald-400" 
          bg="bg-emerald-500/10"
          border="border-emerald-500/20"
        />
      </div>

      <div className="h-72 w-full bg-slate-950/50 rounded-xl p-4 border border-white/5 relative z-10 backdrop-blur-sm">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data}>
            <defs>
              <linearGradient id="colorCpu" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#6366f1" stopOpacity={0.3}/>
                <stop offset="95%" stopColor="#6366f1" stopOpacity={0}/>
              </linearGradient>
              <linearGradient id="colorMem" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#8b5cf6" stopOpacity={0.3}/>
                <stop offset="95%" stopColor="#8b5cf6" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
            <XAxis 
              dataKey="time" 
              stroke="#64748b" 
              fontSize={10} 
              tickLine={false}
              axisLine={false}
              tick={{ fill: '#64748b' }}
            />
            <YAxis 
              stroke="#64748b" 
              fontSize={10} 
              tickLine={false}
              axisLine={false}
              tick={{ fill: '#64748b' }}
            />
            <Tooltip 
              contentStyle={{ 
                backgroundColor: 'rgba(15, 23, 42, 0.9)', 
                borderColor: 'rgba(255,255,255,0.1)', 
                color: '#fff',
                borderRadius: '8px',
                backdropFilter: 'blur(8px)',
                boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1)'
              }}
              itemStyle={{ fontSize: '12px', fontWeight: 500 }}
              labelStyle={{ color: '#94a3b8', marginBottom: '4px', fontSize: '10px', fontFamily: 'monospace' }}
            />
            <Area 
              type="monotone" 
              dataKey="cpu" 
              stroke="#6366f1" 
              strokeWidth={2}
              fillOpacity={1} 
              fill="url(#colorCpu)" 
              animationDuration={1000}
            />
            <Area 
              type="monotone" 
              dataKey="memory" 
              stroke="#8b5cf6" 
              strokeWidth={2}
              fillOpacity={1} 
              fill="url(#colorMem)" 
              animationDuration={1000}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

function MetricCard({ icon, label, value, color, bg, border }: { icon: React.ReactNode, label: string, value: string, color: string, bg: string, border: string }) {
  return (
    <motion.div 
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ scale: 1.02, transition: { duration: 0.2 } }}
      className={`bg-slate-900/50 border ${border} rounded-xl p-4 flex items-center gap-4 backdrop-blur-sm transition-colors hover:bg-slate-900/80`}
    >
      <div className={`p-3 rounded-lg ${bg} ${color} ring-1 ring-inset ring-white/5`}>
        {React.cloneElement(icon as React.ReactElement, { size: 20 })}
      </div>
      <div>
        <p className="text-xs text-gray-400 font-mono uppercase tracking-wider mb-1">{label}</p>
        <p className={`text-xl font-bold font-mono ${color} tracking-tight`}>{value}</p>
      </div>
    </motion.div>
  );
}
