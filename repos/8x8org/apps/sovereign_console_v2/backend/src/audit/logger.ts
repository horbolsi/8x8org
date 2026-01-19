import fs from "node:fs";
import path from "node:path";
import { CONFIG } from "../config.js";

export type AuditEvent = {
  ts: string;
  user?: { id: string; username: string; role: string } | null;
  action: string;
  target?: string;
  ok: boolean;
  meta?: Record<string, any>;
};

function ensureDir(p: string) {
  fs.mkdirSync(p, { recursive: true });
}

export function auditLog(ev: AuditEvent) {
  ensureDir(CONFIG.LOG_DIR);
  const file = path.join(CONFIG.LOG_DIR, "audit.jsonl");
  fs.appendFileSync(file, JSON.stringify(ev) + "\n");
}
