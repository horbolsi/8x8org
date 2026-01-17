import { Hono } from "hono";
import type { Client } from "@sdk/server-types";
import { tables } from "@generated";
import { desc, eq } from "drizzle-orm";

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
    const allFiles = await edgespark.db.select().from(tables.files).orderBy(desc(tables.files.createdAt));
    return c.json(allFiles);
  });

  app.post('/api/files', async (c) => {
    const body = await c.req.json();
    if (Array.isArray(body)) {
       for (const file of body) {
        const { id, name, type, size, date, author, content } = file;
        await edgespark.db.insert(tables.files).values({
            id, name, type, size, date, author, content
        }).onConflictDoUpdate({
          target: tables.files.id,
          set: { name, type, size, date, author, content }
        });
      }
    } else {
        const { id, name, type, size, date, author, content } = body;
        await edgespark.db.insert(tables.files).values({
            id, name, type, size, date, author, content
        }).onConflictDoUpdate({
          target: tables.files.id,
          set: { name, type, size, date, author, content }
        });
    }
    return c.json({ success: true });
  });

  // --- Logs ---
  app.get('/api/logs', async (c) => {
    const allLogs = await edgespark.db.select().from(tables.logs).orderBy(desc(tables.logs.id)).limit(100);
    return c.json(allLogs);
  });

  app.post('/api/logs', async (c) => {
    const body = await c.req.json();
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

  // --- Messages (Global Chat) ---
  app.get('/api/messages', async (c) => {
    const msgs = await edgespark.db.select().from(tables.messages).orderBy(desc(tables.messages.createdAt)).limit(50);
    return c.json(msgs.reverse());
  });

  app.post('/api/messages', async (c) => {
    const body = await c.req.json();
    const { user_id, username, content } = body;
    await edgespark.db.insert(tables.messages).values({ userId: user_id, username, content });
    return c.json({ success: true });
  });

  // --- Tasks ---
  app.get('/api/tasks', async (c) => {
    const allTasks = await edgespark.db.select().from(tables.tasks);
    return c.json(allTasks);
  });

  app.post('/api/tasks', async (c) => {
    const body = await c.req.json();
    if (Array.isArray(body)) {
        for (const task of body) {
            const { id, user_id, title, description, reward_amount, status } = task;
            await edgespark.db.insert(tables.tasks).values({
                id, userId: user_id, title, description, rewardAmount: reward_amount, status
            }).onConflictDoUpdate({
                target: tables.tasks.id,
                set: { userId: user_id, title, description, rewardAmount: reward_amount, status }
            });
        }
    } else {
        const { id, user_id, title, description, reward_amount, status } = body;
        await edgespark.db.insert(tables.tasks).values({
            id, userId: user_id, title, description, rewardAmount: reward_amount, status
        }).onConflictDoUpdate({
            target: tables.tasks.id,
            set: { userId: user_id, title, description, rewardAmount: reward_amount, status }
        });
    }
    return c.json({ success: true });
  });

  // --- Profile ---
  app.get('/api/profile/:userId', async (c) => {
    const userId = c.req.param('userId');
    const profile = await edgespark.db.select().from(tables.profiles).where(eq(tables.profiles.userId, userId)).get();
    return c.json(profile || {});
  });

  app.post('/api/profile', async (c) => {
    const body = await c.req.json();
    const { user_id, ai_id, telegram_id, wallet_address } = body;
    await edgespark.db.insert(tables.profiles).values({
        userId: user_id,
        aiId: ai_id,
        telegramId: telegram_id,
        walletAddress: wallet_address
    }).onConflictDoUpdate({
        target: tables.profiles.userId,
        set: { aiId: ai_id, telegramId: telegram_id, walletAddress: wallet_address }
    });
    return c.json({ success: true });
  });

  return app;
}
