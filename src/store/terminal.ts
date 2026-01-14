import { create } from 'zustand';

interface TerminalState {
  input: string;
  setInput: (input: string) => void;
  executeCommand: (cmd: string) => void; // Signal to execute
  commandHistory: string[];
  addToHistory: (cmd: string) => void;
}

export const useTerminalStore = create<TerminalState>((set) => ({
  input: '',
  setInput: (input) => set({ input }),
  executeCommand: (cmd) => set({ input: cmd }), // Just sets input for now, Terminal component will detect enter? 
  // Better: Terminal component subscribes to this.
  commandHistory: [],
  addToHistory: (cmd) => set((state) => ({ commandHistory: [...state.commandHistory, cmd] })),
}));
