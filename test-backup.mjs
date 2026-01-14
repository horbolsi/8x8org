import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

async function testSystem() {
  console.log('🧪 Testing 8x8org Backup System...');
  console.log('=' .repeat(50));
  
  try {
    // Test git status
    console.log('1. Checking git status...');
    const gitStatus = await execAsync('git status --short');
    console.log(gitStatus.stdout || '✅ No changes');
    
    // Test backup script
    console.log('\n2. Testing backup script...');
    const backupResult = await execAsync('./github-backup.sh');
    console.log('✅ Backup script works!');
    console.log(backupResult.stdout);
    
    // Check recent commits
    console.log('3. Recent commits:');
    const commits = await execAsync('git log --oneline -3');
    console.log(commits.stdout);
    
    console.log('=' .repeat(50));
    console.log('🎉 All tests passed!');
    console.log('🌐 Repository: https://github.com/horbolsi/8x8org');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    if (error.stderr) console.error('Error details:', error.stderr);
  }
}

testSystem();
