import express from 'express';
import { exec } from 'child_process';
import { promisify } from 'util';
import cron from 'node-cron';

const execAsync = promisify(exec);
const app = express();
const PORT = 3001;

app.use(express.json());

// Backup endpoint
app.post('/backup', async (req, res) => {
  try {
    const { stdout, stderr } = await execAsync('./github-backup.sh');
    res.json({ 
      success: true, 
      message: 'Backup completed',
      output: stdout,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ 
      success: false, 
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    project: '8x8org Dashboard',
    repository: 'https://github.com/horbolsi/8x8org',
    timestamp: new Date().toISOString()
  });
});

// Schedule auto-backup every hour
cron.schedule('0 * * * *', async () => {
  console.log('⏰ Running scheduled backup...');
  try {
    const { stdout } = await execAsync('./github-backup.sh');
    console.log('✅ Scheduled backup complete:', stdout);
  } catch (error) {
    console.error('❌ Scheduled backup failed:', error.message);
  }
});

app.listen(PORT, () => {
  console.log(`
  🚀 Backup Server Started
  ========================
  Port: ${PORT}
  Repository: 8x8org
  Auto-backup: Every hour
  
  Endpoints:
  - POST /backup  → Trigger backup
  - GET  /health  → Check status
  ========================
  `);
});
