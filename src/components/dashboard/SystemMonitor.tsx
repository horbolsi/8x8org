import React, { useState, useEffect } from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { Activity, HardDrive, Cpu, Zap, Wifi } from 'lucide-react';
import { motion } from 'framer-motion';
import { useConfig } from '../../store/config';

export function SystemMonitor() {
  const [data, setData] = useState<any[]>([]);
  const { rpcUrl } = useConfig();

  useEffect(() => {
    const interval = setInterval(() => {
      setData(prev => {
        const cpuBase = Math.floor(Math.random() * 20);
        const memBase = Math.floor(Math.random() * 15);
        
        const newPoint = {
          time: new Date().toLocaleTimeString(),
          cpu: cpuBase + 15,
          memory: memBase + 45,
          network: Math.floor(Math.random() * 40) + 10,
          latency: Math.floor(Math.random() * 50) + 10,
        };
        const newData = [...prev, newPoint];
        if (newData.length > 25) newData.shift();
        return newData;
      });
    }, 1500);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="glass-panel rounded-xl p-6 space-y-6 border border-white/10 relative overflow-hidden">
      <div className="absolute top-0 right-0 p-4 opacity-10 pointer-events-none">
        <Activity className="w-48 h-48 text-indigo-500/30" />
      </div>

      <div className="flex items-center justify-between relative z-10">
        <div>
          <h3 className="font-bold text-white flex items-center gap-2 text-lg">
            <Activity className="w-5 h-5 text-indigo-400" />
            Core System Vitals
          </h3>
          <p className="text-xs text-gray-500 mt-1 font-mono uppercase tracking-tighter">Node: {rpcUrl.split('//')[1]?.split('/')[0] || 'Local'}</p>
        </div>
        <div className="flex flex-col items-end gap-1">
          <div className="flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            <span className="text-[10px] font-mono text-emerald-400 font-bold tracking-widest">ENCRYPTED LINK</span>
          </div>
          <span className="text-[9px] text-gray-600 font-mono uppercase">Uptime: 1,242:12:04</span>
        </div>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 relative z-10">
        <MetricCard 
          icon={<Cpu />} 
          label="CPU Load" 
          value={`${data[data.length - 1]?.cpu || 0}%`} 
          color="text-indigo-400" 
          bg="bg-indigo-500/10"
          border="border-indigo-500/20"
        />
        <MetricCard 
          icon={<HardDrive />} 
          label="Mem Usage" 
          value={`${data[data.length - 1]?.memory || 0}%`} 
          color="text-purple-400" 
          bg="bg-purple-500/10"
          border="border-purple-500/20"
        />
        <MetricCard 
          icon={<Wifi />} 
          label="Net Flow" 
          value={`${data[data.length - 1]?.network || 0} MB/s`} 
          color="text-emerald-400" 
          bg="bg-emerald-500/10"
          border="border-emerald-500/20"
        />
        <MetricCard 
          icon={<Zap />} 
          label="Latency" 
          value={`${data[data.length - 1]?.latency || 0} ms`} 
          color="text-amber-400" 
          bg="bg-amber-500/10"
          border="border-amber-500/20"
        />
      </div>

      <div className="h-72 w-full bg-slate-950/50 rounded-xl p-4 border border-white/5 relative z-10 backdrop-blur-sm shadow-inner">
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
              <linearGradient id="colorNet" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#10b981" stopOpacity={0.2}/>
                <stop offset="95%" stopColor="#10b981" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.03)" vertical={false} />
            <XAxis 
              dataKey="time" 
              stroke="#475569" 
              fontSize={9} 
              tickLine={false}
              axisLine={false}
              tick={{ fill: '#475569' }}
              hide={data.length < 5}
            />
            <YAxis 
              stroke="#475569" 
              fontSize={9} 
              tickLine={false}
              axisLine={false}
              tick={{ fill: '#475569' }}
              domain={[0, 100]}
            />
            <Tooltip 
              contentStyle={{ 
                backgroundColor: 'rgba(2, 6, 23, 0.95)', 
                borderColor: 'rgba(255,255,255,0.05)', 
                color: '#fff',
                borderRadius: '12px',
                backdropFilter: 'blur(12px)',
                boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.5)',
                border: '1px solid rgba(255,255,255,0.1)'
              }}
              itemStyle={{ fontSize: '11px', fontWeight: 600, padding: '2px 0' }}
              labelStyle={{ color: '#64748b', marginBottom: '8px', fontSize: '10px', fontFamily: 'monospace', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '4px' }}
            />
            <Area 
              type="monotone" 
              dataKey="cpu" 
              name="CPU"
              stroke="#6366f1" 
              strokeWidth={2}
              fillOpacity={1} 
              fill="url(#colorCpu)" 
              animationDuration={500}
              isAnimationActive={false}
            />
            <Area 
              type="monotone" 
              dataKey="memory" 
              name="MEM"
              stroke="#8b5cf6" 
              strokeWidth={2}
              fillOpacity={1} 
              fill="url(#colorMem)" 
              animationDuration={500}
              isAnimationActive={false}
            />
            <Area 
              type="monotone" 
              dataKey="network" 
              name="NET"
              stroke="#10b981" 
              strokeWidth={1.5}
              fillOpacity={1} 
              fill="url(#colorNet)" 
              animationDuration={500}
              isAnimationActive={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 relative z-10">
        <div className="p-4 rounded-xl bg-white/5 border border-white/5 flex flex-col justify-between">
           <div className="flex items-center justify-between mb-2">
             <span className="text-[10px] text-gray-500 font-mono uppercase tracking-widest">Neural Load</span>
             <span className="text-[10px] text-indigo-400 font-mono">OPTIMAL</span>
           </div>
           <div className="h-1 w-full bg-slate-800 rounded-full overflow-hidden">
             <motion.div 
               className="h-full bg-indigo-500"
               animate={{ width: ['20%', '45%', '30%', '60%', '40%'] }}
               transition={{ duration: 10, repeat: Infinity }}
             />
           </div>
        </div>
        <div className="p-4 rounded-xl bg-white/5 border border-white/5 flex flex-col justify-between">
           <div className="flex items-center justify-between mb-2">
             <span className="text-[10px] text-gray-500 font-mono uppercase tracking-widest">Storage Array</span>
             <span className="text-[10px] text-purple-400 font-mono">82% FULL</span>
           </div>
           <div className="h-1 w-full bg-slate-800 rounded-full overflow-hidden">
             <div className="h-full bg-purple-500 w-[82%]" />
           </div>
        </div>
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
