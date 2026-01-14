import React, { useState, useEffect } from 'react';
import { Folder, FileText, FileCode, FileJson, Search, FolderOpen } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { useTerminalStore } from '../../store/terminal';

export interface FileItem {
  id: string;
  name: string;
  path: string;
  type: string;
  size: string;
  date: string;
  author: string;
  content?: string;
}

export function FileExplorer() {
  const [files, setFiles] = useState<FileItem[]>([]);
  const [search, setSearch] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const { setInput: setTerminalInput } = useTerminalStore();

  useEffect(() => {
    const loadFiles = async () => {
      try {
        const response = await fetch('/api/files');
        const data = await response.json();
        setFiles(data);
      } catch (error) {
        console.error('Failed to load workspace files');
      } finally {
        setIsLoading(false);
      }
    };
    loadFiles();
  }, []);

  const filteredFiles = files.filter(f => f.name.toLowerCase().includes(search.toLowerCase()));

  return (
    <div className="glass-panel rounded-xl p-6 border border-white/10 relative overflow-hidden h-full flex flex-col min-h-[400px]">
      <div className="absolute top-0 right-0 p-4 opacity-5 pointer-events-none">
        <FolderOpen className="w-64 h-64 text-indigo-500" />
      </div>

      <div className="flex items-center justify-between mb-8 relative z-10 shrink-0">
        <div>
          <h3 className="font-bold text-white flex items-center gap-2 text-lg">
            <Folder className="w-5 h-5 text-indigo-400" />
            Workspace Repository
          </h3>
          <p className="text-[10px] text-indigo-400 font-mono uppercase tracking-widest mt-1">Direct Node Access</p>
        </div>
        <div className="flex gap-3 relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
            <input 
              type="text" 
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Filter repository..." 
              className="bg-black/40 border border-white/10 rounded-xl pl-9 pr-4 py-2 text-sm text-white focus:outline-none focus:border-indigo-500/50 w-48 transition-all font-mono"
            />
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 relative z-10 overflow-y-auto custom-scrollbar pr-2 pb-2">
        <AnimatePresence mode="popLayout">
          {isLoading ? (
            <div className="col-span-full py-20 flex flex-col items-center justify-center gap-4">
              <div className="w-8 h-8 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
              <span className="text-[10px] font-mono text-gray-500 uppercase tracking-widest">Scanning Workspace...</span>
            </div>
          ) : filteredFiles.map((file) => (
            <motion.div 
              key={file.id} 
              layout
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.9 }}
              transition={{ duration: 0.2 }}
              onClick={() => setTerminalInput(`cat ${file.path}`)}
              className="group p-4 rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-white/5 hover:border-indigo-500/30 transition-all cursor-pointer relative overflow-hidden"
            >
              <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
              
              <div className="flex items-start justify-between mb-4 relative z-10">
                <div className="p-3 rounded-lg bg-white/5 group-hover:bg-white/10 transition-colors ring-1 ring-white/5">
                  <FileIcon type={file.type} />
                </div>
              </div>
              
              <div className="relative z-10">
                <h4 className="text-sm font-medium text-gray-200 truncate mb-1 group-hover:text-indigo-300 transition-colors" title={file.name}>{file.name}</h4>
                <p className="text-[10px] text-gray-600 truncate font-mono mb-2">{file.path}</p>
                <div className="flex items-center justify-between text-[10px] text-gray-500 font-mono mt-2 pt-2 border-t border-white/5">
                  <span>{file.size}</span>
                  <span>{file.date}</span>
                </div>
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </div>
  );
}

function FileIcon({ type }: { type: string }) {
  const t = type.toLowerCase();
  if (['ts', 'tsx', 'js', 'jsx'].includes(t)) return <FileCode className="w-6 h-6 text-blue-400" />;
  if (['json'].includes(t)) return <FileJson className="w-6 h-6 text-yellow-400" />;
  if (['md'].includes(t)) return <FileText className="w-6 h-6 text-emerald-400" />;
  return <FileText className="w-6 h-6 text-gray-400" />;
}
