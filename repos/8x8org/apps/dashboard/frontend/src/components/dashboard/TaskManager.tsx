import React, { useState, useEffect } from 'react';
import { CheckCircle, Circle, Clock, Award } from 'lucide-react';
import { StorageService, type Task } from '../../lib/storage';
import { client } from '../../lib/client';

export function TaskManager() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [userId, setUserId] = useState<string>('');

  useEffect(() => {
    client.auth.getSession().then(({ data }) => {
        if (data.session?.user) {
            setUserId(data.session.user.id);
        }
    });
    fetchTasks();
  }, []);

  const fetchTasks = async () => {
    const data = await StorageService.getTasks();
    setTasks(data);
  };

  const toggleTask = async (task: Task) => {
    const newStatus = task.status === 'completed' ? 'pending' : 'completed';
    const updatedTask = { ...task, status: newStatus };
    
    // Optimistic
    setTasks(prev => prev.map(t => t.id === task.id ? updatedTask : t));
    
    await StorageService.saveTasks([updatedTask]);
  };

  return (
    <div className="glass-panel rounded-xl p-6 border border-white/10 relative overflow-hidden">
      <div className="flex items-center justify-between mb-6">
        <h3 className="font-bold text-white flex items-center gap-2">
            <Award className="w-5 h-5 text-indigo-400" />
            Mission Control
        </h3>
        <span className="text-xs text-gray-500 font-mono">Active Tasks: {tasks.filter(t => t.status !== 'completed').length}</span>
      </div>

      <div className="space-y-3">
        {tasks.length === 0 ? (
            <div className="text-center py-8 text-gray-500 text-sm">
                No missions assigned yet. Check back later.
            </div>
        ) : (
            tasks.map(task => (
                <div key={task.id} className="p-4 rounded-xl bg-slate-900/50 border border-white/5 flex items-center justify-between group hover:border-indigo-500/30 transition-all">
                    <div className="flex items-center gap-4">
                        <button onClick={() => toggleTask(task)} className="text-gray-500 hover:text-indigo-400 transition-colors">
                            {task.status === 'completed' ? <CheckCircle className="w-5 h-5 text-emerald-500" /> : <Circle className="w-5 h-5" />}
                        </button>
                        <div>
                            <h4 className={`font-medium ${task.status === 'completed' ? 'text-gray-500 line-through' : 'text-white'}`}>{task.title}</h4>
                            {task.description && <p className="text-xs text-gray-500 mt-1">{task.description}</p>}
                        </div>
                    </div>
                    {task.reward_amount && (
                        <div className="px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-xs font-mono text-emerald-400">
                            +{task.reward_amount} ETH
                        </div>
                    )}
                </div>
            ))
        )}
      </div>
    </div>
  );
}
