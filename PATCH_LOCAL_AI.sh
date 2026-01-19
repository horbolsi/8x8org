#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

say(){ printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }

ROOT="$(pwd)"
test -f "$ROOT/package.json" || { echo "Run this from the project root (where package.json is)."; exit 1; }

say "1) Backup files"
mkdir -p .backup_local_ai
cp -f vite.config.ts .backup_local_ai/vite.config.ts.bak 2>/dev/null || true
cp -f src/components/dashboard/AIConsole.tsx .backup_local_ai/AIConsole.tsx.bak 2>/dev/null || true
cp -f src/components/dashboard/Settings.tsx .backup_local_ai/Settings.tsx.bak 2>/dev/null || true
cp -f src/store/config.ts .backup_local_ai/config.ts.bak 2>/dev/null || true

say "2) Patch vite.config.ts (add proxy to Ollama on 127.0.0.1:11434)"
cat > vite.config.ts <<'VITE'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { youwareVitePlugin } from "@youware/vite-plugin-react";

// https://vite.dev/config/
export default defineConfig({
  plugins: [youwareVitePlugin(), react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    proxy: {
      // Browser hits /ollama/* (same origin), Vite forwards to local Ollama
      "/ollama": {
        target: "http://127.0.0.1:11434",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/ollama/, ""),
      },
    },
  },
  build: {
    sourcemap: true,
  },
});
VITE

say "3) Patch src/store/config.ts (replace openaiKey with localModel)"
cat > src/store/config.ts <<'CONF'
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface ConfigState {
  localModel: string;
  rpcUrl: string;
  theme: 'matrix' | 'cyber' | 'dark';
  username: string;

  setLocalModel: (model: string) => void;
  setRpcUrl: (url: string) => void;
  setTheme: (theme: 'matrix' | 'cyber' | 'dark') => void;
  setUsername: (name: string) => void;
}

export const useConfig = create<ConfigState>()(
  persist(
    (set) => ({
      localModel: 'llama3.2:3b',
      rpcUrl: 'https://cloudflare-eth.com',
      theme: 'matrix',
      username: 'Admin',

      setLocalModel: (model) => set({ localModel: model }),
      setRpcUrl: (url) => set({ rpcUrl: url }),
      setTheme: (theme) => set({ theme }),
      setUsername: (name) => set({ username: name }),
    }),
    { name: 'sovereign-config' }
  )
);
CONF

say "4) Patch Settings UI to show Local Model instead of OpenAI key"
cat > src/components/dashboard/Settings.tsx <<'SET'
import React from 'react';
import { Save, RotateCcw, Shield, Database, User, Cpu, Palette, Monitor, Moon, Zap } from 'lucide-react';
import { useConfig } from '../../store/config';
import { motion } from 'framer-motion';
import { cn } from '../../lib/utils';

export function Settings() {
  const { localModel, rpcUrl, username, theme, setLocalModel, setRpcUrl, setUsername, setTheme } = useConfig();
  const [localM, setLocalM] = React.useState(localModel);
  const [localRpc, setLocalRpc] = React.useState(rpcUrl);
  const [localName, setLocalName] = React.useState(username);
  const [saved, setSaved] = React.useState(false);

  const handleSave = () => {
    setLocalModel(localM.trim() || 'llama3.2:3b');
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
        <p className="text-gray-400 text-sm">Local-first configuration (Ollama on-device).</p>
      </div>

      <div className="space-y-8 relative z-10">
        {/* Theme */}
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

        {/* User */}
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

        {/* Local AI */}
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm font-medium text-indigo-300 uppercase tracking-wider">
            <Cpu size={14} /> Local AI (Ollama)
          </div>
          <div className="bg-slate-900/50 p-6 rounded-xl border border-white/5 hover:border-indigo-500/30 transition-colors">
            <label className="text-xs text-gray-500 mb-2 block">Local Model Name</label>
            <input
              type="text"
              value={localM}
              onChange={(e) => setLocalM(e.target.value)}
              placeholder="llama3.2:3b"
              className="w-full bg-black/40 border border-white/10 rounded-lg px-4 py-3 text-white focus:border-indigo-500/50 outline-none transition-all focus:ring-1 focus:ring-indigo-500/20 font-mono"
            />
            <p className="text-xs text-gray-500 mt-2">
              Uses local Ollama via Vite proxy: <span className="font-mono">/ollama</span> → <span className="font-mono">127.0.0.1:11434</span>
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
              setLocalM(localModel);
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
      {active && <div className={`absolute inset-0 opacity-10 ${bg}`} />}
      <div className={cn("p-2 rounded-lg transition-colors", active ? bg : "bg-white/5", color)}>{icon}</div>
      <span className={cn("text-xs font-medium", active ? "text-white" : "text-gray-400 group-hover:text-gray-300")}>
        {label}
      </span>
    </button>
  );
}
SET

say "5) Patch AIConsole.tsx to call local Ollama (/ollama/api/chat)"
cat > src/components/dashboard/AIConsole.tsx <<'AI'
import React, { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Cpu, Copy } from 'lucide-react';
import { cn } from '../../lib/utils';
import { useConfig } from '../../store/config';
import { useTerminalStore } from '../../store/terminal';
import { motion, AnimatePresence } from 'framer-motion';

interface Message {
  id: string;
  role: 'user' | 'ai';
  content: string;
  timestamp: Date;
}

export function AIConsole() {
  const { localModel } = useConfig();
  const { setInput: setTerminalInput } = useTerminalStore();
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>([
    {
      id: '1',
      role: 'ai',
      content: 'Sovereign AI Core v3.0 initialized (Local Mode). Ollama link ready. How can I assist you today?',
      timestamp: new Date()
    }
  ]);
  const [isTyping, setIsTyping] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  useEffect(() => { scrollToBottom(); }, [messages]);

  async function callLocalAI(prompt: string): Promise<string> {
    // Ollama chat API via Vite proxy:
    // browser -> http://127.0.0.1:5173/ollama/api/chat -> http://127.0.0.1:11434/api/chat
    const resp = await fetch('/ollama/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: localModel || 'llama3.2:3b',
        stream: false,
        messages: [{ role: 'user', content: prompt }]
      })
    });

    if (!resp.ok) {
      const t = await resp.text().catch(() => '');
      throw new Error(`Local AI error (${resp.status}): ${t || resp.statusText}`);
    }

    const data: any = await resp.json();
    const content = data?.message?.content || data?.response || '';
    if (!content) throw new Error('Local AI returned empty response');
    return content;
  }

  const handleSend = async () => {
    if (!input.trim()) return;

    const userMsg: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: input,
      timestamp: new Date()
    };

    setMessages(prev => [...prev, userMsg]);
    const userText = input;
    setInput('');
    setIsTyping(true);

    try {
      const aiContent = await callLocalAI(userText);

      const aiMsg: Message = {
        id: (Date.now() + 1).toString(),
        role: 'ai',
        content: aiContent,
        timestamp: new Date()
      };
      setMessages(prev => [...prev, aiMsg]);
    } catch (error) {
      const errorMsg: Message = {
        id: (Date.now() + 1).toString(),
        role: 'ai',
        content: `Error: ${error instanceof Error ? error.message : 'Unknown error occurred'}\n\nTip: make sure Ollama is running:\n  ollama serve &\nAnd the model exists:\n  ollama pull ${localModel || 'llama3.2:3b'}`,
        timestamp: new Date()
      };
      setMessages(prev => [...prev, errorMsg]);
    } finally {
      setIsTyping(false);
    }
  };

  return (
    <div className="glass-panel rounded-xl flex flex-col h-[600px] relative overflow-hidden border border-white/10 shadow-2xl">
      {/* Header */}
      <div className="p-4 border-b border-white/5 bg-slate-900/50 backdrop-blur-md flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2 rounded-lg bg-indigo-500/10 border border-indigo-500/20">
            <Bot className="w-5 h-5 text-indigo-400" />
          </div>
          <div>
            <h3 className="font-bold text-white flex items-center gap-2">
              AI Command Center
              <span className="px-1.5 py-0.5 rounded text-[10px] bg-indigo-500/20 text-indigo-300 border border-indigo-500/20">Local</span>
            </h3>
            <div className="flex items-center gap-2">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
              <p className="text-xs text-emerald-400 font-mono">Model: {localModel || 'llama3.2:3b'}</p>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <div className="px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-mono text-gray-400">
            Local Ollama
          </div>
        </div>
      </div>

      {/* Chat Area */}
      <div className="flex-1 overflow-y-auto p-6 space-y-6 custom-scrollbar bg-slate-950/30">
        <AnimatePresence initial={false}>
          {messages.map((msg) => (
            <motion.div
              key={msg.id}
              initial={{ opacity: 0, y: 20, scale: 0.95 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              transition={{ duration: 0.3 }}
              className={cn("flex gap-4 max-w-[80%]", msg.role === 'user' ? "ml-auto flex-row-reverse" : "")}
            >
              <div className={cn(
                "w-8 h-8 rounded-lg flex items-center justify-center shrink-0 border",
                msg.role === 'ai'
                  ? "bg-indigo-500/10 border-indigo-500/20 text-indigo-400"
                  : "bg-emerald-500/10 border-emerald-500/20 text-emerald-400"
              )}>
                {msg.role === 'ai' ? <Bot size={18} /> : <User size={18} />}
              </div>

              <div className="flex flex-col gap-2">
                <div className={cn(
                  "p-4 rounded-2xl text-sm leading-relaxed shadow-lg backdrop-blur-sm border whitespace-pre-wrap",
                  msg.role === 'ai'
                    ? "bg-slate-900/80 border-white/10 text-gray-300 rounded-tl-none"
                    : "bg-indigo-600/20 border-indigo-500/20 text-white rounded-tr-none"
                )}>
                  {msg.content}
                </div>
                {msg.role === 'ai' && (
                  <button
                    onClick={() => setTerminalInput(msg.content)}
                    className="self-start text-[10px] flex items-center gap-1 text-indigo-400 hover:text-indigo-300 transition-colors opacity-50 hover:opacity-100"
                  >
                    <Copy size={10} /> Copy to Terminal
                  </button>
                )}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
        <div ref={messagesEndRef} />
      </div>

      {/* Input Area */}
      <div className="p-4 border-t border-white/5 bg-slate-900/50 backdrop-blur-md">
        <div className="relative">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSend()}
            placeholder="Enter command or query..."
            className="w-full bg-black/20 border border-white/10 rounded-xl pl-4 pr-12 py-3 text-sm text-white focus:outline-none focus:border-indigo-500/50 transition-all placeholder:text-gray-600 font-mono"
          />
          <button
            onClick={handleSend}
            disabled={!input.trim() || isTyping}
            className="absolute right-2 top-1/2 -translate-y-1/2 p-2 bg-indigo-500 hover:bg-indigo-600 text-white rounded-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isTyping ? <Cpu className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
          </button>
        </div>
      </div>
    </div>
  );
}
AI

say "Done. Your AIConsole now uses local Ollama via /ollama proxy."
say "Backups saved in: .backup_local_ai/"
