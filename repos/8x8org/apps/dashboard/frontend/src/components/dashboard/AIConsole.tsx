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
  const { openaiKey } = useConfig();
  const { setInput: setTerminalInput } = useTerminalStore();
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>([
    {
      id: '1',
      role: 'ai',
      content: 'Sovereign AI Core v3.0 initialized. All systems nominal. How can I assist you today?',
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

      if (openaiKey) {
        // Real API Call
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openaiKey}`
          },
          body: JSON.stringify({
            model: 'gpt-3.5-turbo',
            messages: [{ role: 'user', content: input }],
            max_tokens: 150
          })
        });

        const data = await response.json();
        if (data.error) throw new Error(data.error.message);
        aiContent = data.choices[0].message.content;
      } else {
        // Simulated Response
        await new Promise(resolve => setTimeout(resolve, 1500));
        const responses = [
          "Analyzing request parameters...",
          "Accessing neural pathways...",
          "Executing autonomous protocols...",
          "I've processed that data. The system indicates optimal performance.",
          "Deploying requested modules to the active cluster.",
          "Security scan complete. No threats detected.",
          "Blockchain synchronization in progress. Current block height verified."
        ];
        aiContent = responses[Math.floor(Math.random() * responses.length)];
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
        content: `Error: ${error instanceof Error ? error.message : 'Unknown error occurred'}`,
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
              <p className="text-xs text-emerald-400 font-mono">Neural Link Active</p>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <div className="px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-mono text-gray-400">
            Latency: 12ms
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
