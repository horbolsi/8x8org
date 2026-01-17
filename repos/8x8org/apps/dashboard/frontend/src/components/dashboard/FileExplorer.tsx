import React, { useState, useEffect } from 'react';
import { Folder, FileText, FileCode, FileJson, MoreVertical, Download, Search, Filter, Plus, Upload, Trash2 } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { StorageService, type FileItem } from '../../lib/storage';

export function FileExplorer() {
  const [files, setFiles] = useState<FileItem[]>([]);
  const [search, setSearch] = useState('');
  const [isUploading, setIsUploading] = useState(false);

  useEffect(() => {
    const loadFiles = async () => {
      const data = await StorageService.getFiles();
      setFiles(data);
    };
    loadFiles();
  }, []);

  const handleUpload = () => {
    setIsUploading(true);
    setTimeout(async () => {
      const newFile: FileItem = {
        id: `file_${Date.now()}`,
        name: `upload_${Date.now()}.dat`,
        type: 'file',
        size: '1.2 MB',
        date: new Date().toISOString().split('T')[0],
        author: 'User'
      };
      await StorageService.addFile(newFile);
      const updatedFiles = await StorageService.getFiles();
      setFiles(updatedFiles);
      setIsUploading(false);
    }, 1000);
  };

  const filteredFiles = files.filter(f => f.name.toLowerCase().includes(search.toLowerCase()));

  return (
    <div className="glass-panel rounded-xl p-6 border border-white/10 relative overflow-hidden h-full flex flex-col">
      <div className="absolute top-0 right-0 p-4 opacity-5 pointer-events-none">
        <Folder className="w-64 h-64 text-indigo-500" />
      </div>

      <div className="flex items-center justify-between mb-8 relative z-10 shrink-0">
        <div>
          <h3 className="font-bold text-white flex items-center gap-2 text-lg">
            <Folder className="w-5 h-5 text-indigo-400" />
            System Files
          </h3>
          <p className="text-xs text-gray-500 mt-1 font-mono">Encrypted storage & logs</p>
        </div>
        <div className="flex gap-3">
          <div className="relative hidden sm:block">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
            <input 
              type="text" 
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search files..." 
              className="bg-black/20 border border-white/10 rounded-lg pl-9 pr-4 py-1.5 text-sm text-white focus:outline-none focus:border-indigo-500/50 w-48 transition-all focus:w-64"
            />
          </div>
          <button 
            onClick={handleUpload}
            disabled={isUploading}
            className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-medium rounded-lg transition-colors flex items-center gap-2 shadow-lg shadow-indigo-500/20 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isUploading ? <Upload className="w-3 h-3 animate-bounce" /> : <Plus className="w-3 h-3" />}
            {isUploading ? 'Uploading...' : 'Upload'}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 relative z-10 overflow-y-auto custom-scrollbar pr-2 pb-2">
        <AnimatePresence mode="popLayout">
          {filteredFiles.map((file, i) => (
            <motion.div 
              key={file.id} 
              layout
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.9 }}
              transition={{ duration: 0.2 }}
              className="group p-4 rounded-xl bg-slate-900/40 hover:bg-slate-900/60 border border-white/5 hover:border-indigo-500/30 transition-all cursor-pointer relative overflow-hidden"
            >
              <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
              
              <div className="flex items-start justify-between mb-4 relative z-10">
                <div className="p-3 rounded-lg bg-white/5 group-hover:bg-white/10 transition-colors ring-1 ring-white/5">
                  <FileIcon type={file.type} />
                </div>
                <button className="opacity-0 group-hover:opacity-100 p-1.5 hover:bg-white/10 rounded-lg transition-all text-gray-400 hover:text-white">
                  <MoreVertical className="w-4 h-4" />
                </button>
              </div>
              
              <div className="relative z-10">
                <h4 className="text-sm font-medium text-gray-200 truncate mb-1 group-hover:text-indigo-300 transition-colors" title={file.name}>{file.name}</h4>
                <div className="flex items-center justify-between text-xs text-gray-500 font-mono mt-2">
                  <span>{file.size}</span>
                  <span>{file.date}</span>
                </div>
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
        
        <motion.div 
          layout
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          onClick={handleUpload}
          className="p-4 rounded-xl border border-dashed border-white/10 hover:border-indigo-500/30 hover:bg-indigo-500/5 transition-all cursor-pointer flex flex-col items-center justify-center gap-2 text-gray-500 hover:text-indigo-400 min-h-[140px]"
        >
          <Plus className="w-8 h-8 opacity-50" />
          <span className="text-xs font-medium">Add New File</span>
        </motion.div>
      </div>
    </div>
  );
}

function FileIcon({ type }: { type: string }) {
  switch (type) {
    case 'code': return <FileCode className="w-6 h-6 text-blue-400" />;
    case 'json': return <FileJson className="w-6 h-6 text-yellow-400" />;
    case 'doc': return <FileText className="w-6 h-6 text-red-400" />;
    case 'file': return <FileText className="w-6 h-6 text-emerald-400" />;
    default: return <FileText className="w-6 h-6 text-gray-400" />;
  }
}
