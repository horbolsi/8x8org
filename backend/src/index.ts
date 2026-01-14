import { Hono } from "hono";
import type { Client } from "@sdk/server-types";
import { tables } from "@generated";
import { desc } from "drizzle-orm";

export async function createApp(
  edgespark: Client<typeof tables>
): Promise<Hono> {
  const app = new Hono();

  // --- Bots ---
  app.get('/api/bots', async (c) => {
    const allBots = await edgespark.db.select().from(tables.bots);
    return c.json(allBots);
  });

  app.post('/api/bots', async (c) => {
    const body = await c.req.json();
    
    if (Array.isArray(body)) {
      for (const bot of body) {
        // Ensure we don't try to insert unknown fields if the frontend sends extra data
        const { id, name, type, status, uptime, load } = bot;
        await edgespark.db.insert(tables.bots).values({
            id, name, type, status, uptime, load
        }).onConflictDoUpdate({
          target: tables.bots.id,
          set: { name, type, status, uptime, load }
        });
      }
    } else {
       const { id, name, type, status, uptime, load } = body;
       await edgespark.db.insert(tables.bots).values({
           id, name, type, status, uptime, load
       }).onConflictDoUpdate({
          target: tables.bots.id,
          set: { name, type, status, uptime, load }
        });
    }
    return c.json({ success: true });
  });

  // --- Files ---
  app.get('/api/files', async (c) => {
    try {
      const { readdir, stat, readFile } = await import('node:fs/promises');
      const { join, relative } = await import('node:path');
      
      const rootDir = process.cwd();
      const files: any[] = [];
      
      async function scanDir(dir: string) {
        const entries = await readdir(dir, { withFileTypes: true });
        for (const entry of entries) {
          const fullPath = join(dir, entry.name);
          const relPath = relative(rootDir, fullPath);
          
          if (entry.name === 'node_modules' || entry.name === '.git' || entry.name === 'dist') continue;
          
          if (entry.isDirectory()) {
            await scanDir(fullPath);
          } else {
            const stats = await stat(fullPath);
            let content = '';
            if (stats.size < 1024 * 50) { // Limit context to files < 50KB
               try { content = await readFile(fullPath, 'utf-8'); } catch(e) {}
            }
            files.push({
              id: relPath,
              name: entry.name,
              path: relPath,
              type: entry.name.split('.').pop() || 'file',
              size: (stats.size / 1024).toFixed(1) + ' KB',
              date: stats.mtime.toISOString().split('T')[0],
              author: 'System',
              content: content
            });
          }
        }
      }
      
      await scanDir(rootDir);
      return c.json(files);
    } catch (error) {
      return c.json({ error: 'Failed to read workspace' }, 500);
    }
  });

  app.post('/api/files/write', async (c) => {
    const { path, content } = await c.req.json();
    const { writeFile, mkdir } = await import('node:fs/promises');
    const { dirname, join } = await import('node:path');
    const fullPath = join(process.cwd(), path);
    try {
      await mkdir(dirname(fullPath), { recursive: true });
      await writeFile(fullPath, content, 'utf-8');
      return c.json({ success: true });
    } catch (e: any) {
      return c.json({ error: e.message }, 500);
    }
  });

  // --- Logs ---
  app.get('/api/logs', async (c) => {
    const allLogs = await edgespark.db.select().from(tables.logs).orderBy(desc(tables.logs.id)).limit(100);
    return c.json(allLogs);
  });

  app.post('/api/logs', async (c) => {
    const body = await c.req.json();
    // Logs might come without ID (auto-increment)
    // If frontend sends ID, we might ignore it or use it.
    // Frontend Log interface has ID.
    // But usually logs are new events.
    
    if (Array.isArray(body)) {
        for (const log of body) {
            const { timestamp, level, message } = log;
            await edgespark.db.insert(tables.logs).values({ timestamp, level, message });
        }
    } else {
        const { timestamp, level, message } = body;
        await edgespark.db.insert(tables.logs).values({ timestamp, level, message });
    }
    return c.json({ success: true });
  });

  // --- Shell Proxy ---
  app.post('/api/terminal', async (c) => {
    const { command } = await c.req.json();
    const { exec } = await import('node:child_process');
    const { promisify } = await import('node:util');
    const execPromise = promisify(exec);
    
    try {
      const { stdout, stderr } = await execPromise(command, { cwd: process.cwd() });
      return c.json({ output: stdout || stderr });
    } catch (error: any) {
      return c.json({ output: error.message }, 500);
    }
  });

  return app;
}
