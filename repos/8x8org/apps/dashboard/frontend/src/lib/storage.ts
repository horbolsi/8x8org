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
  id?: number;
  timestamp: string;
  level: 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';
  message: string;
}

export interface Message {
  id?: number;
  user_id: string;
  username: string;
  content: string;
  created_at?: number;
}

export interface Task {
  id: string;
  user_id?: string;
  title: string;
  description?: string;
  reward_amount?: string;
  status: 'pending' | 'in_progress' | 'completed';
}

export interface Profile {
  userId: string;
  aiId?: string;
  telegramId?: string;
  walletAddress?: string;
}

export const StorageService = {
  // Bots
  getBots: async (): Promise<Bot[]> => {
    try {
      const res = await client.api.fetch('/api/bots');
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      const data = await res.json();
      
      if (Array.isArray(data) && data.length === 0) {
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
      const res = await client.api.fetch('/api/files');
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      const data = await res.json();
      
      if (Array.isArray(data) && data.length === 0) {
        const localData = localStorage.getItem('sovereign_files');
        if (localData) {
            try {
                const parsed = JSON.parse(localData);
                if (Array.isArray(parsed) && parsed.length > 0) {
                    await StorageService.saveFiles(parsed);
                    return parsed;
                }
            } catch (e) {
                console.error("Migration failed", e);
            }
        }

        const initial: FileItem[] = [
          { id: '1', name: 'sovereign_ai.py', type: 'code', size: '12 KB', date: '2024-03-15', author: 'System' },
          { id: '2', name: 'config.json', type: 'json', size: '2 KB', date: '2024-03-14', author: 'Admin' },
        ];
        await StorageService.saveFiles(initial);
        return initial;
      }
      return data;
    } catch (error) {
      console.error("Failed to fetch files:", error);
      return [];
    }
  },

  saveFiles: async (files: FileItem[]) => {
    try {
      await client.api.fetch('/api/files', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(files)
      });
    } catch (error) {
      console.error("Failed to save files:", error);
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
  },

  // Messages
  getMessages: async (): Promise<Message[]> => {
    try {
      const res = await client.api.fetch('/api/messages');
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      return await res.json();
    } catch (error) {
      console.error("Failed to fetch messages:", error);
      return [];
    }
  },

  sendMessage: async (msg: Message) => {
    try {
      await client.api.fetch('/api/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(msg)
      });
    } catch (error) {
      console.error("Failed to send message:", error);
    }
  },

  // Tasks
  getTasks: async (): Promise<Task[]> => {
    try {
      const res = await client.api.fetch('/api/tasks');
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      return await res.json();
    } catch (error) {
      console.error("Failed to fetch tasks:", error);
      return [];
    }
  },

  saveTasks: async (tasks: Task[]) => {
    try {
      await client.api.fetch('/api/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(tasks)
      });
    } catch (error) {
      console.error("Failed to save tasks:", error);
    }
  },

  // Profile
  getProfile: async (userId: string): Promise<Profile> => {
    try {
      const res = await client.api.fetch(`/api/profile/${userId}`);
      if (!res.ok) throw new Error(`Status: ${res.status}`);
      return await res.json();
    } catch (error) {
      console.error("Failed to fetch profile:", error);
      return { userId };
    }
  },

  saveProfile: async (profile: Profile) => {
    try {
      await client.api.fetch('/api/profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            user_id: profile.userId,
            ai_id: profile.aiId,
            telegram_id: profile.telegramId,
            wallet_address: profile.walletAddress
        })
      });
    } catch (error) {
      console.error("Failed to save profile:", error);
    }
  }
};
