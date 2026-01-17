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
        switch (cmd) {
          case 'help':
            output = [
              'Available commands:', 
              '  help    - Show this help', 
              '  clear   - Clear terminal', 
              '  status  - System status', 
              '  ls      - List files',
              '  cd      - Change directory',
              '  tree    - Show file structure',
              '  cat     - Read file content',
              '  rm      - Remove file',
              '  whoami  - Current user'
            ];
            break;
          case 'clear':
            setLines([]);
            setIsProcessing(false);
            return;
          case 'status':
            output = ['System: ONLINE', 'CPU: Nominal', 'Memory: OK', 'Network: Secure'];
            break;
          case 'whoami':
            output = ['root@sovereign-core'];
            break;
          case 'ls':
            const files = await StorageService.getFiles();
            if (cwd === '~') {
                // Show folders and files
                output = [
                    'drwxr-xr-x  src',
                    'drwxr-xr-x  logs',
                    'drwxr-xr-x  wallet',
                    ...files.map(f => `-rw-r--r--  ${f.name}`)
                ];
            } else if (cwd === '~/src') {
                output = ['-rw-r--r--  main.py', '-rw-r--r--  utils.py'];
            } else if (cwd === '~/logs') {
                output = ['-rw-r--r--  system.log', '-rw-r--r--  error.log'];
            } else if (cwd === '~/wallet') {
                output = ['-rw-------  wallet.dat', '-rw-r--r--  transactions.csv'];
            } else {
                output = [];
            }
            break;
          case 'cd':
            if (args.length === 0 || args[0] === '~') {
                setCwd('~');
            } else if (args[0] === '..') {
                setCwd('~'); // Simple mock, always go back to root
            } else if (['src', 'logs', 'wallet'].includes(args[0])) {
                setCwd(`~/${args[0]}`);
            } else {
                output = [`cd: no such file or directory: ${args[0]}`];
            }
            break;
          case 'tree':
            output = [
                '.',
                '├── src',
                '│   ├── main.py',
                '│   └── utils.py',
                '├── logs',
                '│   ├── system.log',
                '│   └── error.log',
                '├── wallet',
                '│   ├── wallet.dat',
                '│   └── transactions.csv',
                '└── (root files)'
            ];
            const rootFiles = await StorageService.getFiles();
            rootFiles.forEach(f => {
                output.push(`    └── ${f.name}`);
            });
            break;
          case 'cat':
            if (args.length === 0) {
                output = ['Usage: cat <filename>'];
            } else {
                const files = await StorageService.getFiles();
                const file = files.find(f => f.name === args[0]);
                if (file) {
                    output = ['--- BEGIN FILE ---', file.content || '(empty)', '--- END FILE ---'];
                } else {
                    // Check virtual files
                    if (args[0] === 'main.py') output = ['print("Sovereign AI initialized")'];
                    else output = [`File not found: ${args[0]}`];
                }
            }
            break;
          case 'rm':
             if (args.length === 0) {
                output = ['Usage: rm <filename>'];
            } else {
                const files = await StorageService.getFiles();
                const newFiles = files.filter(f => f.name !== args[0]);
                if (newFiles.length === files.length) {
                    output = [`File not found: ${args[0]}`];
                } else {
                    await StorageService.saveFiles(newFiles);
                    output = [`Deleted ${args[0]}`];
                }
            }
            break;
          default:
            output = [`Command not found: ${cmd}`];
        }
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
