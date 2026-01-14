import express from 'express';
import { exec } from 'child_process';
import { promisify } from 'util';
import cron from 'node-cron';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const execAsync = promisify(exec);

const app = express();
const PORT = 3001;

app.use(express.json());

// Simple backup endpoint
app.post('/backup', async (req, res) => {
  console.log('📦 Backup requested at', new Date().toISOString());
  
  try {
    const { stdout, stderr } = await execAsync('./github-backup.sh');
    console.log('✅ Backup completed successfully');
    
    res.json({ 
      status: 'success',
      message: 'Backup completed',
      output: stdout,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Backup error:', error);
    res.status(500).json({ 
      status: 'error',
      message: 'Backup failed',
      error: error.stderr || error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    project: '8x8org AI Dashboard',
    repository: 'https://github.com/horbolsi/8x8org',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// Get repository info
app.get('/info', async (req, res) => {
  try {
    const { stdout } = await execAsync('git log --oneline -5');
    const { stdout: remoteInfo } = await execAsync('git remote -v');
    
    res.json({
      repository: 'horbolsi/8x8org',
      last_commits: stdout.trim().split('\n'),
      remotes: remoteInfo.trim().split('\n'),
      last_backup: new Date().toISOString(),
      branch: 'main'
    });
  } catch (error) {
    res.status(500).json({ 
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Simple status endpoint
app.get('/', (req, res) => {
  res.json({
    service: '8x8org Backup Server',
    endpoints: {
      backup: 'POST /backup',
      health: 'GET /health',
      info: 'GET /info'
    },
    github: 'https://github.com/horbolsi/8x8org',
    schedule: 'Auto-backup every hour'
  });
});

// Schedule automatic backups (every hour)
cron.schedule('0 * * * *', async () => {
  console.log('⏰ Running scheduled backup...');
  try {
    const { stdout } = await execAsync('./github-backup.sh');
    console.log('✅ Scheduled backup completed');
    console.log(stdout);
  } catch (error) {
    console.error('❌ Scheduled backup failed:', error.message);
  }
});

// Start server
app.listen(PORT, () => {
  console.log(`
  🚀 8x8org Backup Server Started!
  =================================
  📡 Port: ${PORT}
  🌐 Repository: 8x8org
  📍 Local URL: http://localhost:${PORT}
  
  Endpoints:
  - POST /backup    → Trigger manual backup
  - GET  /health    → Server status
  - GET  /info      → Git repository info
  - GET  /          → API documentation
  
  Auto-backup: Every hour at minute 0
  =================================
  `);
});

// Handle shutdown gracefully
process.on('SIGTERM', () => {
  console.log('🛑 Shutting down backup server...');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('🛑 Server interrupted, shutting down...');
  process.exit(0);
});
