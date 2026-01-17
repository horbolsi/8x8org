import React, { useState, useEffect, useRef } from 'react';
import { Send, MessageSquare } from 'lucide-react';
import { StorageService, type Message } from '../../lib/storage';
import { useConfig } from '../../store/config';
import { client } from '../../lib/client';

export function GlobalChat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const { username } = useConfig();
  const bottomRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const [userId, setUserId] = useState<string>('');
  const [shouldScroll, setShouldScroll] = useState(true);

  useEffect(() => {
    client.auth.getSession().then(({ data }) => {
        if (data.session?.user) {
            setUserId(data.session.user.id);
        }
    });
  }, []);

  const fetchMessages = async () => {
    const msgs = await StorageService.getMessages();
    setMessages(prev => {
        // Simple check to avoid re-renders if data is same
        // Note: This is expensive for large arrays, but fine for 50 msgs
        if (prev.length !== msgs.length || prev[prev.length-1]?.id !== msgs[msgs.length-1]?.id) {
            return msgs;
        }
        return prev;
    });
  };

  useEffect(() => {
    fetchMessages();
    const interval = setInterval(fetchMessages, 3000); // Poll every 3s
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (shouldScroll) {
        bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages, shouldScroll]);

  const handleScroll = () => {
    if (scrollContainerRef.current) {
        const { scrollTop, scrollHeight, clientHeight } = scrollContainerRef.current;
        const isNearBottom = scrollHeight - scrollTop - clientHeight < 100;
        setShouldScroll(isNearBottom);
    }
  };

  const handleSend = async () => {
    if (!input.trim() || !userId) return;
    
    const msg: Message = {
        user_id: userId,
        username: username || 'Anonymous',
        content: input
    };
    
    // Optimistic update
    setMessages(prev => [...prev, { ...msg, id: Date.now() }]); 
    setInput('');
    setShouldScroll(true); // Force scroll on send
    
    await StorageService.sendMessage(msg);
    fetchMessages();
  };

  return (
    <div className="glass-panel rounded-xl flex flex-col h-[400px] border border-white/10 shadow-2xl relative overflow-hidden">
        {/* Header */}
        <div className="p-4 border-b border-white/5 bg-slate-900/50 backdrop-blur-md flex items-center gap-3">
            <MessageSquare className="w-5 h-5 text-indigo-400" />
            <h3 className="font-bold text-white">Global Chat</h3>
        </div>

        {/* Messages */}
        <div 
            ref={scrollContainerRef}
            onScroll={handleScroll}
            className="flex-1 overflow-y-auto p-4 space-y-4 custom-scrollbar bg-slate-950/30"
        >
            {messages.map((msg, i) => (
                <div key={i} className={`flex flex-col ${msg.user_id === userId ? 'items-end' : 'items-start'}`}>
                    <div className="flex items-center gap-2 mb-1">
                        <span className="text-xs text-indigo-400 font-bold">{msg.username}</span>
                        <span className="text-[10px] text-gray-500">{msg.created_at ? new Date(msg.created_at).toLocaleTimeString() : 'Just now'}</span>
                    </div>
                    <div className={`p-3 rounded-xl text-sm max-w-[80%] ${
                        msg.user_id === userId 
                        ? 'bg-indigo-600/20 border border-indigo-500/20 text-white rounded-tr-none' 
                        : 'bg-slate-800/50 border border-white/10 text-gray-300 rounded-tl-none'
                    }`}>
                        {msg.content}
                    </div>
                </div>
            ))}
            <div ref={bottomRef} />
        </div>

        {/* Input */}
        <div className="p-4 border-t border-white/5 bg-slate-900/50 backdrop-blur-md flex gap-2">
            <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleSend()}
                placeholder="Type a message..."
                className="flex-1 bg-black/20 border border-white/10 rounded-lg px-4 py-2 text-sm text-white focus:outline-none focus:border-indigo-500/50"
            />
            <button 
                onClick={handleSend}
                className="p-2 bg-indigo-500 hover:bg-indigo-600 text-white rounded-lg transition-colors"
            >
                <Send className="w-4 h-4" />
            </button>
        </div>
    </div>
  );
}
