import React, { useState, useEffect } from 'react';
import { Github, RefreshCw, CheckCircle, Clock, Server, Activity } from 'lucide-react';

interface BackupStatus {
  status: 'idle' | 'loading' | 'success' | 'error';
  lastBackup: string;
  serverOnline: boolean;
  commitCount: number;
}

export const GitHubBackup: React.FC = () => {
  const [backupStatus, setBackupStatus] = useState<BackupStatus>({
    status: 'idle',
    lastBackup: '',
    serverOnline: false,
    commitCount: 0
  });
  const [isLoading, setIsLoading] = useState(true);

  const checkServerHealth = async () => {
    try {
      const response = await fetch('http://localhost:3001/health');
      if (response.ok) {
        const data = await response.json();
        setBackupStatus(prev => ({
          ...prev,
          serverOnline: true,
          lastBackup: data.timestamp
        }));
      }
    } catch (error) {
      setBackupStatus(prev => ({ ...prev, serverOnline: false }));
    }
  };

  const getRepoInfo = async () => {
    try {
      const response = await fetch('http://localhost:3001/info');
      if (response.ok) {
        const data = await response.json();
        setBackupStatus(prev => ({
          ...prev,
          commitCount: data.last_commits?.length || 0
        }));
      }
    } catch (error) {
      console.error('Failed to fetch repo info:', error);
    }
  };

  const triggerBackup = async () => {
    setBackupStatus(prev => ({ ...prev, status: 'loading' }));
    
    try {
      const response = await fetch('http://localhost:3001/backup', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        }
      });
      
      const data = await response.json();
      
      if (data.status === 'success') {
        setBackupStatus(prev => ({
          ...prev,
          status: 'success',
          lastBackup: data.timestamp
        }));
        
        // Refresh info
        setTimeout(() => {
          getRepoInfo();
        }, 1000);
        
        alert('✅ Backup successful! Changes pushed to GitHub.');
      } else {
        setBackupStatus(prev => ({ ...prev, status: 'error' }));
        alert('❌ Backup failed: ' + (data.error || 'Unknown error'));
      }
    } catch (error) {
      setBackupStatus(prev => ({ ...prev, status: 'error' }));
      alert('❌ Could not connect to backup server');
    }
  };

  useEffect(() => {
    const initialize = async () => {
      await checkServerHealth();
      await getRepoInfo();
      setIsLoading(false);
    };
    
    initialize();
    
    // Check server health every 30 seconds
    const interval = setInterval(checkServerHealth, 30000);
    return () => clearInterval(interval);
  }, []);

  if (isLoading) {
    return (
      <div className="glass-panel p-6 rounded-xl border border-white/10">
        <div className="flex items-center justify-center gap-3">
          <RefreshCw className="w-5 h-5 text-blue-500 animate-spin" />
          <span className="text-gray-400">Loading backup status...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="glass-panel p-6 rounded-xl border border-white/10">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-blue-500/20 rounded-lg">
            <Github className="w-6 h-6 text-blue-400" />
          </div>
          <div>
            <h3 className="font-bold text-white text-lg">GitHub Backup</h3>
            <p className="text-sm text-gray-400">8x8org Repository</p>
          </div>
        </div>
        
        <div className={`px-3 py-1 rounded-full text-sm ${backupStatus.serverOnline ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
          {backupStatus.serverOnline ? 'Online' : 'Offline'}
        </div>
      </div>

      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div className="p-3 bg-blue-500/10 rounded-lg">
            <div className="flex items-center gap-2 mb-1">
              <Clock className="w-4 h-4 text-blue-400" />
              <span className="text-sm text-gray-400">Last Backup</span>
            </div>
            <div className="text-white font-medium">
              {backupStatus.lastBackup ? new Date(backupStatus.lastBackup).toLocaleTimeString() : 'Never'}
            </div>
          </div>
          
          <div className="p-3 bg-purple-500/10 rounded-lg">
            <div className="flex items-center gap-2 mb-1">
              <Activity className="w-4 h-4 text-purple-400" />
              <span className="text-sm text-gray-400">Commits</span>
            </div>
            <div className="text-white font-medium">
              {backupStatus.commitCount}
            </div>
          </div>
        </div>

        <button
          onClick={triggerBackup}
          disabled={backupStatus.status === 'loading' || !backupStatus.serverOnline}
          className={`w-full flex items-center justify-center gap-2 p-3 rounded-lg transition-all ${
            backupStatus.status === 'loading'
              ? 'bg-blue-600 cursor-wait'
              : backupStatus.serverOnline
              ? 'bg-blue-600 hover:bg-blue-700 hover:scale-[1.02] active:scale-95'
              : 'bg-gray-600 cursor-not-allowed opacity-50'
          }`}
        >
          {backupStatus.status === 'loading' ? (
            <>
              <RefreshCw className="w-4 h-4 animate-spin" />
              <span>Backing up...</span>
            </>
          ) : (
            <>
              <CheckCircle className="w-4 h-4" />
              <span>Backup Now</span>
            </>
          )}
        </button>

        <div className="pt-4 border-t border-white/10">
          <div className="flex items-center gap-2 text-sm text-gray-400 mb-2">
            <Server className="w-4 h-4" />
            <span>Backup Server Status</span>
          </div>
          <div className="text-xs space-y-1">
            <p>• Auto-backup runs every hour</p>
            <p>• Manual trigger via button or API</p>
            <p>• Real-time sync with GitHub</p>
            <a 
              href="https://github.com/horbolsi/8x8org" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-blue-400 hover:text-blue-300 inline-flex items-center gap-1"
            >
              ↗ View on GitHub
            </a>
          </div>
        </div>
      </div>
    </div>
  );
};
