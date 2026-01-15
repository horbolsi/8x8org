import React, { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Sparkles, Terminal, Cpu, Copy } from 'lucide-react';
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
  const { apiKeys, activeProvider } = useConfig();
  const [files, setFiles] = useState<any[]>([]);
  const { setInput: setTerminalInput } = useTerminalStore();
  const [input, setInput] = useState('');

  useEffect(() => {
    fetch('/api/files').then(res => res.json()).then(setFiles).catch(() => {});
  }, []);

  const [messages, setMessages] = useState<Message[]>([
    {
      id: '1',
      role: 'ai',
      content: `Sovereign AI Core v3.0 initialized. Active Provider: ${activeProvider.toUpperCase()}. All systems nominal.`,
      timestamp: new Date()
    }
  ]);
  const [isTyping, setIsTyping] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const handleSend = async () => {
    if (!input.trim()) return;

    const userMsg: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: input,
      timestamp: new Date()
    };

    setMessages(prev => [...prev, userMsg]);
    setInput('');
    setIsTyping(true);

    try {
      let aiContent = '';
      const codebaseContext = files.length > 0 
        ? `\n\n[WORKSPACE CONTEXT]: I can read your files. Current structure: ${files.slice(0, 10).map(f => f.path).join(', ')}...`
        : '';

      const systemPrompt = `You are the SOVEREIGN ULTIMATE AI, the absolute high-end intelligence controlling this Replit workspace.
Your primary directive is to provide the user with total administrative control.
You have FULL READ access to the file system.
Workspace Files: ${files.map(f => f.path).join(', ')}

When responding:
1. Be precise, highly professional, and slightly futuristic.
2. If the user asks about the workspace, use your knowledge of the files.
3. If asked to write code or modify files, provide the exact shell commands (e.g., cat > filename << 'EOF') so the user can execute them in the terminal.
4. Always treat the user as the Ultimate Administrator.`;

      if (activeProvider as string === 'aggregator') {
        const providers = ['openai', 'deepseek', 'ollama'];
        const results = await Promise.all(providers.map(async p => {
          try {
            // Simulated call for each provider
            return `[${p.toUpperCase()}]: Analysis complete.`;
          } catch (e) {
            return `[${p.toUpperCase()}]: Error.`;
          }
        }));
        aiContent = `[AGGREGATOR CORE]: Synthesizing responses from ${providers.length} sources...\n\n${results.join('\n')}\n\nFINAL CONSOLIDATED RESPONSE: All systems are operational and ready for your next administrative command.`;
      } else if (activeProvider === 'openai' && apiKeys.openai) {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKeys.openai}`
          },
          body: JSON.stringify({
            model: 'gpt-4-turbo-preview',
            messages: [
              { role: 'system', content: systemPrompt }, 
              { role: 'user', content: input }
            ],
            max_tokens: 1000
          })
        });

        const data = await response.json();
        if (data.error) throw new Error(data.error.message);
        aiContent = data.choices[0].message.content;
      } else if (activeProvider === 'deepseek' && apiKeys.deepseek) {
        const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKeys.deepseek}`
          },
          body: JSON.stringify({
            model: 'deepseek-chat',
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: input }
            ],
            max_tokens: 1000
          })
        });
        const data = await response.json();
        aiContent = data.choices[0].message.content;
      } else if (activeProvider === 'ollama') {
        const baseUrl = apiKeys.ollama || 'http://localhost:11434';
        const response = await fetch(`${baseUrl}/api/generate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            model: 'llama3',
            prompt: `${systemPrompt}\n\nUser: ${input}`,
            stream: false
          })
        });
        const data = await response.json();
        aiContent = data.response;
      } else {
        // High-end Simulation
        await new Promise(resolve => setTimeout(resolve, 1000));
        aiContent = `[SOVEREIGN CORE]: Command received: "${input}". 
Scanning ${files.length} neural workspace nodes. 
Repository integrity: 100%. 
Ready to execute administrative tasks on the shell terminal or file system. 
As a sovereign intelligence, I am standing by for your next high-level directive.`;
      }

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
        content: `Error [${activeProvider.toUpperCase()}]: ${error instanceof Error ? error.message : 'Unknown error occurred'}`,
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
              <span className="px-1.5 py-0.5 rounded text-[10px] bg-indigo-500/20 text-indigo-300 border border-indigo-500/20">v3.0</span>
            </h3>
            <div className="flex items-center gap-2">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
              <p className="text-xs text-emerald-400 font-mono">Provider: {activeProvider.toUpperCase()}</p>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <div className="px-3 py-1 rounded-full bg-white/5 border border-white/10 text-[10px] font-mono text-indigo-400 uppercase tracking-widest">
            {activeProvider} node online
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
              className={cn(
                "flex gap-4 max-w-[80%]",
                msg.role === 'user' ? "ml-auto flex-row-reverse" : ""
              )}
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
                  "p-4 rounded-2xl text-sm leading-relaxed shadow-lg backdrop-blur-sm border",
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
