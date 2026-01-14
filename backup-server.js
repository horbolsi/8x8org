const express = require('express');
const { exec } = require('child_process');
const cron = require('node-cron');
const app = express();
const PORT = 3001;

app.use(express.json());

// Simple backup endpoint
app.post('/backup', (req, res) => {
  console.log('📦 Backup requested at', new Date().toISOString());
  
  exec('./github-backup.sh', (error, stdout, stderr) => {
    if (error) {
      console.error('❌ Backup error:', error);
      return res.status(500).json({ 
        status: 'error',
        message: 'Backup failed',
        error: stderr || error.message
      });
    }
    
    console.log('✅ Backup completed successfully');
    res.json({ 
      status: 'success',
      message: 'Backup completed',
      output: stdout,
      timestamp: new Date().toISOString()
    });
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    project: '8x8org AI Dashboard',
    repository: 'https://github.com/horbolsi/8x8org',
    timestamp: new Date().toISOString()
  });
});

// Get repository info
app.get('/info', async (req, res) => {
  const { exec } = require('child_process');
  const util = require('util');
  const execAsync = util.promisify(exec);
  
  try {
    const { stdout } = await execAsync('git log --oneline -3 && echo "---" && git remote -v');
    res.json({
      last_commits: stdout.split('\n'),
      repository: 'horbolsi/8x8org',
      last_backup: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Backup every hour
cron.schedule('0 * * * *', () => {
  console.log('⏰ Running scheduled backup...');
  exec('./github-backup.sh', (error, stdout) => {
    if (error) {
      console.error('Scheduled backup failed:', error);
    } else {
      console.log('✅ Scheduled backup completed');
    }
  });
});

app.listen(PORT, () => {
  console.log(`
  🚀 Backup Server Started!
  =========================
  📡 Port: ${PORT}
  🌐 Repository: 8x8org
  📍 Local URL: http://localhost:${PORT}
  
  Endpoints:
  - POST /backup    → Trigger backup
  - GET  /health    → Server status
  - GET  /info      → Repository info
  
  Auto-backup: Every 1 hour
  =========================
  `);
});
