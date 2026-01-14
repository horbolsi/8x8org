import { client } from "./client";

export interface Bot {
  id: string;
  name: string;
  type: string;
  status: 'running' | 'stopped' | 'error';
  uptime: string;
  load: string;
}

export interface FileItem {
  id: string;
  name: string;
  type: string;
  size: string;
  date: string;
  author: string;
  content?: string;
}

export interface Log {
  id?: number; // Optional because backend generates it
  timestamp: string;
  level: 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';
  message: string;
}

export const StorageService = {
  // Bots
  getBots: async (): Promise<Bot[]> => {
    try {
      const res = await client.api.fetch('/api/bots');
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      const data = await res.json();
      
      if (Array.isArray(data) && data.length === 0) {
        // Check if we have local data to migrate
        const localData = localStorage.getItem('sovereign_bots');
        if (localData) {
            try {
                const parsed = JSON.parse(localData);
                if (Array.isArray(parsed) && parsed.length > 0) {
                    await StorageService.saveBots(parsed);
                    return parsed;
                }
            } catch (e) {
                console.error("Migration failed", e);
            }
        }

        const initial: Bot[] = [
          { id: 'bot_01', name: 'Telegram Alpha', type: 'Telegram', status: 'running', uptime: '4d 12h', load: '24%' },
          { id: 'bot_02', name: 'Discord Mod', type: 'Discord', status: 'running', uptime: '2d 5h', load: '12%' },
          { id: 'bot_03', name: 'Crypto Sniper', type: 'Trading', status: 'stopped', uptime: '-', load: '0%' },
        ];
        await StorageService.saveBots(initial);
        return initial;
      }
      return data;
    } catch (error) {
      console.error("Failed to fetch bots:", error);
      return [];
    }
  },

  saveBots: async (bots: Bot[]) => {
    try {
      await client.api.fetch('/api/bots', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(bots)
      });
    } catch (error) {
      console.error("Failed to save bots:", error);
    }
  },

  // Files
  getFiles: async (): Promise<FileItem[]> => {
    try {
      const res = await fetch('/api/files');
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      return await res.json();
    } catch (error) {
      console.error("Failed to fetch files:", error);
      return [];
    }
  },

  saveFiles: async (files: FileItem[]) => {
    // This is now handled by the backend /api/files/write for individual files
    console.warn("saveFiles (bulk) is deprecated in favor of individual write");
  },

  writeFile: async (path: string, content: string) => {
    try {
      await fetch('/api/files/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path, content })
      });
    } catch (error) {
      console.error("Failed to write file:", error);
    }
  },

  addFile: async (file: FileItem) => {
    try {
      await client.api.fetch('/api/files', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(file)
      });
    } catch (error) {
      console.error("Failed to add file:", error);
    }
  },

  // Logs
  getLogs: async (): Promise<Log[]> => {
    try {
      const res = await client.api.fetch('/api/logs');
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      return await res.json();
    } catch (error) {
      console.error("Failed to fetch logs:", error);
      return [];
    }
  },

  addLog: async (log: Log) => {
    try {
      await client.api.fetch('/api/logs', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(log)
      });
    } catch (error) {
      console.error("Failed to add log:", error);
    }
  },
  
  clearLogs: async () => {
    console.warn("clearLogs not implemented in backend");
  }
};
