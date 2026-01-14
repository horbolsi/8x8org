import { create } from 'zustand';

interface ConfigState {
  theme: string;
  setTheme: (theme: string) => void;
}

export const useConfig = create<ConfigState>((set) => ({
  theme: 'dark',
  setTheme: (theme) => set({ theme }),
}));
