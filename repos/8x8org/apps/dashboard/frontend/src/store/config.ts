import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface ConfigState {
  openaiKey: string;
  rpcUrl: string;
  theme: 'matrix' | 'cyber' | 'dark';
  username: string;
  setOpenaiKey: (key: string) => void;
  setRpcUrl: (url: string) => void;
  setTheme: (theme: 'matrix' | 'cyber' | 'dark') => void;
  setUsername: (name: string) => void;
}

export const useConfig = create<ConfigState>()(
  persist(
    (set) => ({
      openaiKey: '',
      rpcUrl: 'https://cloudflare-eth.com',
      theme: 'matrix',
      username: 'Admin',
      setOpenaiKey: (key) => set({ openaiKey: key }),
      setRpcUrl: (url) => set({ rpcUrl: url }),
      setTheme: (theme) => set({ theme }),
      setUsername: (name) => set({ username: name }),
    }),
    {
      name: 'sovereign-config',
    }
  )
);
