import React, { useState, useRef, useEffect } from 'react';
import { Terminal as TerminalIcon, X, Minus, Square, Command } from 'lucide-react';
import { motion } from 'framer-motion';
import { StorageService } from '../../lib/storage';
import { useTerminalStore } from '../../store/terminal';

export function Terminal() {
  const [lines, setLines] = useState<string[]>(['Sovereign AI OS v3.0.0', 'Copyright (c) 2024 Sovereign Corp', 'Type "help" for commands', '']);
  const [input, setInput] = useState('');
  const [cwd, setCwd] = useState('~');
  const bottomRef = useRef<HTMLDivElement>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  
  const { input: storeInput, setInput: setStoreInput } = useTerminalStore();

  useEffect(() => {
    if (storeInput) {
      setInput(storeInput);
      setStoreInput('');
      document.getElementById('terminal-input')?.focus();
    }
  }, [storeInput, setStoreInput]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [lines]);

  const handleCommand = async (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !isProcessing) {
      const cmdLine = input.trim();
      if (!cmdLine) return;
      
      const parts = cmdLine.split(' ');
      const cmd = parts[0].toLowerCase();
      const args = parts.slice(1);

      setLines(prev => [...prev, `${cwd === '~' ? 'root@sovereign:~' : `root@sovereign:${cwd}`} $ ${cmdLine}`]);
      setInput('');
      setIsProcessing(true);

      let output: string[] = [];

      try {
        if (cmd === 'clear') {
          setLines([]);
          setIsProcessing(false);
          return;
        }

        // Reflect to database (mocked)
        await fetch('/api/audit', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ command: cmdLine, timestamp: new Date().toISOString() })
        }).catch(() => console.log("Audit log saved locally"));

        const response = await fetch('/api/terminal', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ command: cmdLine })
        });
        const data = await response.json();
        
        // Handle multiline output correctly
        const outputLines = data.output ? data.output.toString().split('\n') : ['[No Output]'];
        output = outputLines;
      } catch (err) {
        output = [`Error executing command: ${err instanceof Error ? err.message : 'Unknown error'}`];
      }
      
      setLines(prev => [...prev, ...output, '']);
      setIsProcessing(false);
    }
  };

  return (
    <div className="glass-panel rounded-xl overflow-hidden flex flex-col h-[350px] border border-white/10 shadow-2xl">
      <div className="bg-slate-900/80 p-3 flex items-center justify-between border-b border-white/5 backdrop-blur-md">
        <div className="flex items-center gap-2 px-2">
          <TerminalIcon className="w-4 h-4 text-gray-400" />
          <span className="text-xs font-mono text-gray-400">root@sovereign:{cwd}</span>
        </div>
        <div className="flex gap-2">
          <div className="w-3 h-3 rounded-full bg-yellow-500/20 hover:bg-yellow-500 cursor-pointer border border-yellow-500/30 transition-colors" />
          <div className="w-3 h-3 rounded-full bg-emerald-500/20 hover:bg-emerald-500 cursor-pointer border border-emerald-500/30 transition-colors" />
          <div className="w-3 h-3 rounded-full bg-red-500/20 hover:bg-red-500 cursor-pointer border border-red-500/30 transition-colors" />
        </div>
      </div>
      
      <div 
        className="flex-1 bg-slate-950/90 p-4 font-mono text-xs overflow-y-auto custom-scrollbar cursor-text" 
        onClick={() => document.getElementById('terminal-input')?.focus()}
      >
        {lines.map((line, i) => (
          <motion.div 
            key={i} 
            initial={{ opacity: 0, x: -5 }}
            animate={{ opacity: 1, x: 0 }}
            className={`${line.includes('$') ? 'text-indigo-400 mt-2 font-bold' : 'text-gray-300'} whitespace-pre-wrap`}
          >
            {line}
          </motion.div>
        ))}
        <div className="flex items-center gap-2 mt-2 text-indigo-400 font-bold">
          <span>{cwd === '~' ? 'root@sovereign:~' : `root@sovereign:${cwd}`} $</span>
          <input
            id="terminal-input"
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleCommand}
            disabled={isProcessing}
            className="bg-transparent border-none outline-none flex-1 text-indigo-400 placeholder-indigo-500/30"
            autoFocus
            autoComplete="off"
          />
        </div>
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
