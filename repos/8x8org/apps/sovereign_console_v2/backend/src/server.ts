import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import cookieParser from "cookie-parser";
import fs from "node:fs";

import { CONFIG } from "./config.js";
import { auditLog } from "./audit/logger.js";
import { authRouter } from "./routes/auth.js";
import { fsRouter } from "./routes/fs.js";
import { terminalRouter } from "./routes/terminal.js";
import { ollamaRouter } from "./routes/ollama.js";
import { aiRouter } from "./routes/ai.js";
import { searchRouter } from "./routes/search.js";
import { jobsRouter } from "./routes/jobs.js";

fs.mkdirSync(CONFIG.DB_DIR, { recursive: true });
fs.mkdirSync(CONFIG.LOG_DIR, { recursive: true });

const app = express();

app.use(helmet());
app.use(cookieParser());
app.use(express.json({ limit: "5mb" }));

// Rate limit
app.use(rateLimit({
  windowMs: 60_000,
  limit: 120,
  standardHeaders: true,
  legacyHeaders: false
}));

// CORS (keep strict by default)
if (CONFIG.CORS_ORIGIN) {
  app.use(cors({ origin: CONFIG.CORS_ORIGIN, credentials: true }));
} else {
  // same-origin only by default
  app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Credentials", "true");
    next();
  });
}

app.get("/api/health", (_req, res) => res.json({ ok: true, name: "Sovereign Console v2", port: CONFIG.PORT }));

// Auth
app.use("/api/auth", authRouter);

// Core modules
app.use("/api/fs", fsRouter);
app.use("/api/search", searchRouter);
app.use("/api/terminal", terminalRouter);
app.use("/api/ollama", ollamaRouter);
app.use("/api/ai", aiRouter);
app.use("/api/jobs", jobsRouter);

// Error handler
app.use((err: any, _req: any, res: any, _next: any) => {
  auditLog({ ts: new Date().toISOString(), user: null, action: "SERVER_ERROR", ok: false, meta: { error: String(err?.message || err) } });
  res.status(500).json({ ok: false, error: String(err?.message || err) });
});

app.listen(CONFIG.PORT, CONFIG.BIND, () => {
  console.log(`✅ Sovereign Console v2 backend running at http://${CONFIG.BIND}:${CONFIG.PORT}`);
  console.log(`✅ WORKSPACE_ROOT = ${CONFIG.WORKSPACE_ROOT}`);
});
