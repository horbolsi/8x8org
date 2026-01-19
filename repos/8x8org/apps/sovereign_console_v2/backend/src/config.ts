import path from "node:path";

export type Role = "admin" | "user";

export const CONFIG = {
  // If running on Replit you usually want 0.0.0.0
  BIND: process.env.BIND || (process.env.REPLIT ? "0.0.0.0" : "127.0.0.1"),
  PORT: Number(process.env.PORT || "6060"),

  // Workspace root defaults to your repo root from backend folder:
  // apps/sovereign_console_v2/backend -> go up 3 levels to repo root
  WORKSPACE_ROOT: path.resolve(process.env.WORKSPACE_ROOT || path.join(process.cwd(), "..", "..", "..")),

  // Runtime folder for logs/db
  RUNTIME_ROOT: path.resolve(process.env.RUNTIME_ROOT || path.join(process.cwd(), "..", "runtime")),
  DB_DIR: path.resolve(process.env.DB_DIR || path.join(process.cwd(), "..", "runtime", "db")),
  LOG_DIR: path.resolve(process.env.LOG_DIR || path.join(process.cwd(), "..", "runtime", "logs")),

  // Auth
  JWT_SECRET: process.env.JWT_SECRET || "CHANGE_ME_SUPER_SECRET",
  COOKIE_NAME: process.env.COOKIE_NAME || "scv2_token",

  // Security
  CORS_ORIGIN: process.env.CORS_ORIGIN || "", // if empty => allow same-origin only

  // Ollama
  OLLAMA_HOST: process.env.OLLAMA_HOST || "http://127.0.0.1:11434",

  // Limits
  MAX_FILE_BYTES: Number(process.env.MAX_FILE_BYTES || String(2 * 1024 * 1024)), // 2MB per write
  MAX_UPLOAD_BYTES: Number(process.env.MAX_UPLOAD_BYTES || String(50 * 1024 * 1024)), // 50MB upload
  MAX_CMD_OUTPUT: Number(process.env.MAX_CMD_OUTPUT || String(400_000))
};
