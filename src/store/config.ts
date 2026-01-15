import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface ConfigState {
  apiKeys: {
    openai: string;
    anthropic: string;
    gemini: string;
    deepseek: string;
    ollama: string;
    claude: string;
    xai: string;
  };
  activeProvider: 'openai' | 'anthropic' | 'gemini' | 'deepseek' | 'ollama' | 'simulation' | 'aggregator' | 'claude' | 'xai';
  rpcUrl: string;
  theme: 'matrix' | 'cyber' | 'dark';
  username: string;
  setApiKey: (provider: 'openai' | 'anthropic' | 'gemini' | 'deepseek' | 'ollama' | 'claude' | 'xai', key: string) => void;
  setActiveProvider: (provider: 'openai' | 'anthropic' | 'gemini' | 'deepseek' | 'ollama' | 'simulation' | 'aggregator' | 'claude' | 'xai') => void;
  setRpcUrl: (url: string) => void;
  setTheme: (theme: 'matrix' | 'cyber' | 'dark') => void;
  setUsername: (name: string) => void;
}

export const useConfig = create<ConfigState>()(
  persist(
    (set) => ({
      apiKeys: {
        openai: '',
        anthropic: '',
        gemini: '',
        deepseek: '',
        ollama: 'http://localhost:11434',
        claude: '',
        xai: '',
      },
      activeProvider: 'simulation',
      rpcUrl: 'https://cloudflare-eth.com',
      theme: 'matrix',
      username: 'Admin',
      setApiKey: (provider, key) => set((state) => ({
        apiKeys: { ...state.apiKeys, [provider]: key }
      })),
      setActiveProvider: (provider) => set({ activeProvider: provider }),
      setRpcUrl: (url) => set({ rpcUrl: url }),
      setTheme: (theme) => set({ theme }),
      setUsername: (name) => set({ username: name }),
    }),
    {
      name: 'sovereign-config',
    }
  )
);
