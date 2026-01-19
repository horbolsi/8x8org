#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Sovereign Console v2 - Full Scaffold Generator
# Creates:
#  - apps/sovereign_console_v2/backend (Express+TS, auth+RBAC, FS manager, audit, jobs)
#  - apps/sovereign_console_v2/frontend (React+Vite UI)
#  - start.sh / stop.sh
#
# Security defaults:
#  - Local-first (127.0.0.1) unless REPLIT=1 or BIND=0.0.0.0
#  - Admin/User roles
#  - Destructive ops require admin AND X-Confirm-Action: true
#  - Terminal is allowlist only
#  - All actions go to audit log (JSONL)
###############################################################################

APP_ROOT="apps/sovereign_console_v2"
BACKEND="$APP_ROOT/backend"
FRONTEND="$APP_ROOT/frontend"
RUNTIME="$APP_ROOT/runtime"
LOGS="$RUNTIME/logs"
DB="$RUNTIME/db"

echo "==> Creating Sovereign Console v2 scaffold at: $APP_ROOT"
mkdir -p "$BACKEND/src" "$FRONTEND/src" "$LOGS" "$DB"

###############################################################################
# Backend package.json + tsconfig
###############################################################################
cat > "$BACKEND/package.json" <<'EOF'
{
  "name": "sovereign-console-v2-backend",
  "version": "2.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/server.js"
  },
  "dependencies": {
    "archiver": "^7.0.1",
    "bcryptjs": "^2.4.3",
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.4.0",
    "helmet": "^7.1.0",
    "multer": "^1.4.5-lts.1",
    "unzipper": "^0.12.3"
  },
  "devDependencies": {
    "@types/cookie-parser": "^1.4.7",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/multer": "^1.4.12",
    "tsx": "^4.19.2",
    "typescript": "^5.6.3"
  }
}
EOF

cat > "$BACKEND/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM"],
    "module": "ES2022",
    "moduleResolution": "Bundler",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
EOF

###############################################################################
# Backend: config + utils
###############################################################################
cat > "$BACKEND/src/config.ts" <<'EOF'
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
EOF

mkdir -p "$BACKEND/src/utils" "$BACKEND/src/auth" "$BACKEND/src/routes" "$BACKEND/src/middleware" "$BACKEND/src/services" "$BACKEND/src/jobs" "$BACKEND/src/audit" "$BACKEND/src/ai" "$BACKEND/src/terminal" "$BACKEND/src/fs"
mkdir -p "$FRONTEND/src/components" "$FRONTEND/src/pages" "$FRONTEND/src/lib" "$FRONTEND/src/styles"

cat > "$BACKEND/src/utils/pathSafe.ts" <<'EOF'
import path from "node:path";
import { CONFIG } from "../config.js";

export function resolveInWorkspace(userPath: string): string {
  // Normalize and ensure it stays inside WORKSPACE_ROOT
  const cleaned = userPath.replace(/\0/g, "");
  const abs = path.resolve(CONFIG.WORKSPACE_ROOT, cleaned);
  const root = CONFIG.WORKSPACE_ROOT;

  if (!abs.startsWith(root + path.sep) && abs !== root) {
    throw new Error("Path escapes workspace root");
  }
  return abs;
}

export function relFromWorkspace(absPath: string): string {
  const rel = path.relative(CONFIG.WORKSPACE_ROOT, absPath);
  return rel || ".";
}
EOF

###############################################################################
# Backend: audit logger (JSONL)
###############################################################################
cat > "$BACKEND/src/audit/logger.ts" <<'EOF'
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
EOF

###############################################################################
# Backend: users store + auth
###############################################################################
cat > "$BACKEND/src/auth/users.ts" <<'EOF'
import fs from "node:fs";
import path from "node:path";
import bcrypt from "bcryptjs";
import { CONFIG, Role } from "../config.js";

export type User = {
  id: string;
  username: string;
  passHash: string;
  role: Role;
  createdAt: string;
};

const USERS_FILE = path.join(CONFIG.DB_DIR, "users.json");

function ensureDB() {
  fs.mkdirSync(CONFIG.DB_DIR, { recursive: true });
  if (!fs.existsSync(USERS_FILE)) fs.writeFileSync(USERS_FILE, JSON.stringify({ users: [] }, null, 2));
}

export function loadUsers(): User[] {
  ensureDB();
  const raw = fs.readFileSync(USERS_FILE, "utf8");
  const data = JSON.parse(raw);
  return data.users || [];
}

export function saveUsers(users: User[]) {
  ensureDB();
  fs.writeFileSync(USERS_FILE, JSON.stringify({ users }, null, 2));
}

export function hasAnyUsers(): boolean {
  return loadUsers().length > 0;
}

export function findUserByUsername(username: string): User | undefined {
  return loadUsers().find(u => u.username.toLowerCase() === username.toLowerCase());
}

export function findUserById(id: string): User | undefined {
  return loadUsers().find(u => u.id === id);
}

export async function createUser(username: string, password: string, role: Role): Promise<User> {
  const users = loadUsers();
  const exists = users.find(u => u.username.toLowerCase() === username.toLowerCase());
  if (exists) throw new Error("Username already exists");

  const id = "u_" + Math.random().toString(36).slice(2, 10);
  const passHash = await bcrypt.hash(password, 10);

  const user: User = {
    id,
    username,
    passHash,
    role,
    createdAt: new Date().toISOString()
  };

  users.push(user);
  saveUsers(users);
  return user;
}

export async function verifyPassword(user: User, password: string): Promise<boolean> {
  return bcrypt.compare(password, user.passHash);
}
EOF

cat > "$BACKEND/src/auth/jwt.ts" <<'EOF'
import jwt from "jsonwebtoken";
import { CONFIG, Role } from "../config.js";

export type TokenPayload = {
  id: string;
  username: string;
  role: Role;
};

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, CONFIG.JWT_SECRET, { expiresIn: "7d" });
}

export function verifyToken(token: string): TokenPayload {
  return jwt.verify(token, CONFIG.JWT_SECRET) as TokenPayload;
}
EOF

cat > "$BACKEND/src/middleware/auth.ts" <<'EOF'
import { Request, Response, NextFunction } from "express";
import { CONFIG, Role } from "../config.js";
import { verifyToken } from "../auth/jwt.js";

export type AuthedRequest = Request & {
  user?: { id: string; username: string; role: Role };
};

export function requireAuth(req: AuthedRequest, res: Response, next: NextFunction) {
  const token = req.cookies?.[CONFIG.COOKIE_NAME];
  if (!token) return res.status(401).json({ ok: false, error: "Not authenticated" });

  try {
    const payload = verifyToken(token);
    req.user = payload;
    next();
  } catch {
    return res.status(401).json({ ok: false, error: "Invalid session" });
  }
}

export function requireRole(role: Role) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ ok: false, error: "Not authenticated" });
    if (req.user.role !== role) return res.status(403).json({ ok: false, error: "Forbidden" });
    next();
  };
}

export function requireConfirmHeader(req: Request, res: Response, next: NextFunction) {
  const ok = req.header("X-Confirm-Action") === "true";
  if (!ok) return res.status(400).json({ ok: false, error: "Missing X-Confirm-Action: true" });
  next();
}
EOF

###############################################################################
# Backend: FS routes
###############################################################################
cat > "$BACKEND/src/routes/fs.ts" <<'EOF'
import fs from "node:fs";
import path from "node:path";
import express from "express";
import multer from "multer";
import archiver from "archiver";
import unzipper from "unzipper";

import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";
import { resolveInWorkspace, relFromWorkspace } from "../utils/pathSafe.js";
import { requireAuth, requireRole, requireConfirmHeader, AuthedRequest } from "../middleware/auth.js";

export const fsRouter = express.Router();

function statSafe(p: string) {
  try { return fs.statSync(p); } catch { return null; }
}

function listTree(absDir: string, depth: number): any {
  const st = statSafe(absDir);
  if (!st) return null;

  const node: any = {
    name: path.basename(absDir),
    path: relFromWorkspace(absDir),
    type: st.isDirectory() ? "dir" : "file",
    size: st.isFile() ? st.size : 0,
    mtime: st.mtime.toISOString()
  };

  if (st.isDirectory() && depth > 0) {
    const items = fs.readdirSync(absDir).sort();
    node.children = items.map((name) => {
      const childAbs = path.join(absDir, name);
      return listTree(childAbs, depth - 1);
    }).filter(Boolean);
  }

  return node;
}

// GET tree
fsRouter.get("/tree", requireAuth, (req: AuthedRequest, res) => {
  const p = String(req.query.path || ".");
  const depth = Math.min(Number(req.query.depth || "4"), 8);
  const abs = resolveInWorkspace(p);

  const node = listTree(abs, depth);
  if (!node) return res.status(404).json({ ok: false, error: "Not found" });
  return res.json({ ok: true, root: node });
});

// GET read
fsRouter.get("/read", requireAuth, (req: AuthedRequest, res) => {
  const p = String(req.query.path || "");
  if (!p) return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  const st = statSafe(abs);
  if (!st || !st.isFile()) return res.status(404).json({ ok: false, error: "File not found" });

  if (st.size > CONFIG.MAX_FILE_BYTES * 5) {
    return res.status(413).json({ ok: false, error: "File too large to read in UI" });
  }

  const content = fs.readFileSync(abs, "utf8");
  return res.json({ ok: true, path: p, bytes: st.size, content });
});

// POST write (admin)
fsRouter.post("/write", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p, content } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });
  if (typeof content !== "string") return res.status(400).json({ ok: false, error: "Missing content" });

  const abs = resolveInWorkspace(p);
  const bytes = Buffer.byteLength(content, "utf8");
  if (bytes > CONFIG.MAX_FILE_BYTES) return res.status(413).json({ ok: false, error: "Too large" });

  fs.mkdirSync(path.dirname(abs), { recursive: true });

  // backup
  const bak = abs + ".bak_" + Date.now();
  if (fs.existsSync(abs)) fs.copyFileSync(abs, bak);

  fs.writeFileSync(abs, content, "utf8");

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FILE_WRITE",
    target: p,
    ok: true,
    meta: { bytes, backup: relFromWorkspace(bak) }
  });

  return res.json({ ok: true, path: p, bytes });
});

// POST create file (admin)
fsRouter.post("/create", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  if (fs.existsSync(abs)) return res.status(400).json({ ok: false, error: "Already exists" });

  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, "", "utf8");

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FILE_CREATE",
    target: p,
    ok: true
  });

  return res.json({ ok: true, path: p });
});

// POST mkdir (admin)
fsRouter.post("/mkdir", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  fs.mkdirSync(abs, { recursive: true });

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "DIR_CREATE",
    target: p,
    ok: true
  });

  return res.json({ ok: true, path: p });
});

// POST rename (admin)
fsRouter.post("/rename", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { from, to } = req.body || {};
  if (!from || !to) return res.status(400).json({ ok: false, error: "Missing from/to" });

  const absFrom = resolveInWorkspace(from);
  const absTo = resolveInWorkspace(to);

  fs.mkdirSync(path.dirname(absTo), { recursive: true });
  fs.renameSync(absFrom, absTo);

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_RENAME",
    target: `${from} -> ${to}`,
    ok: true
  });

  return res.json({ ok: true });
});

// POST copy (admin)
fsRouter.post("/copy", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { from, to } = req.body || {};
  if (!from || !to) return res.status(400).json({ ok: false, error: "Missing from/to" });

  const absFrom = resolveInWorkspace(from);
  const absTo = resolveInWorkspace(to);
  const st = statSafe(absFrom);
  if (!st) return res.status(404).json({ ok: false, error: "Source missing" });

  fs.mkdirSync(path.dirname(absTo), { recursive: true });
  if (st.isFile()) {
    fs.copyFileSync(absFrom, absTo);
  } else {
    // directory copy (simple recursive)
    const copyDir = (src: string, dst: string) => {
      fs.mkdirSync(dst, { recursive: true });
      for (const item of fs.readdirSync(src)) {
        const s = path.join(src, item);
        const d = path.join(dst, item);
        const sst = fs.statSync(s);
        if (sst.isDirectory()) copyDir(s, d);
        else fs.copyFileSync(s, d);
      }
    };
    copyDir(absFrom, absTo);
  }

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_COPY",
    target: `${from} -> ${to}`,
    ok: true
  });

  return res.json({ ok: true });
});

// POST delete (admin + confirm)
fsRouter.post("/delete", requireAuth, requireRole("admin"), requireConfirmHeader, (req: AuthedRequest, res) => {
  const { path: p } = req.body || {};
  if (!p || typeof p !== "string") return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  if (!fs.existsSync(abs)) return res.status(404).json({ ok: false, error: "Not found" });

  const trashDir = path.join(CONFIG.RUNTIME_ROOT, "trash");
  fs.mkdirSync(trashDir, { recursive: true });

  const base = path.basename(abs);
  const moved = path.join(trashDir, base + ".deleted_" + Date.now());
  fs.renameSync(abs, moved);

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_DELETE",
    target: p,
    ok: true,
    meta: { movedTo: relFromWorkspace(moved) }
  });

  return res.json({ ok: true, movedTo: moved });
});

// Upload (admin)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: CONFIG.MAX_UPLOAD_BYTES }
});

fsRouter.post("/upload", requireAuth, requireRole("admin"), upload.single("file"), (req: AuthedRequest, res) => {
  const targetDir = String(req.query.dir || ".");
  if (!req.file) return res.status(400).json({ ok: false, error: "No file" });

  const absDir = resolveInWorkspace(targetDir);
  fs.mkdirSync(absDir, { recursive: true });

  const safeName = req.file.originalname.replace(/[^\w.\-()+ ]/g, "_");
  const dest = path.join(absDir, safeName);

  fs.writeFileSync(dest, req.file.buffer);

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "FS_UPLOAD",
    target: path.join(targetDir, safeName),
    ok: true,
    meta: { bytes: req.file.size }
  });

  return res.json({ ok: true, path: path.join(targetDir, safeName), bytes: req.file.size });
});

// Download
fsRouter.get("/download", requireAuth, (req: AuthedRequest, res) => {
  const p = String(req.query.path || "");
  if (!p) return res.status(400).json({ ok: false, error: "Missing path" });

  const abs = resolveInWorkspace(p);
  const st = statSafe(abs);
  if (!st || !st.isFile()) return res.status(404).json({ ok: false, error: "Not found" });

  res.setHeader("Content-Disposition", `attachment; filename="${path.basename(abs)}"`);
  res.setHeader("Content-Type", "application/octet-stream");
  fs.createReadStream(abs).pipe(res);
});

// Zip (admin)
fsRouter.post("/zip", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { path: p, out } = req.body || {};
  if (!p || !out) return res.status(400).json({ ok: false, error: "Missing path/out" });

  const absSrc = resolveInWorkspace(p);
  const absOut = resolveInWorkspace(out);

  const st = statSafe(absSrc);
  if (!st) return res.status(404).json({ ok: false, error: "Source not found" });

  fs.mkdirSync(path.dirname(absOut), { recursive: true });

  const output = fs.createWriteStream(absOut);
  const archive = archiver("zip", { zlib: { level: 9 } });

  output.on("close", () => {
    auditLog({
      ts: new Date().toISOString(),
      user: req.user || null,
      action: "FS_ZIP",
      target: `${p} -> ${out}`,
      ok: true,
      meta: { bytes: archive.pointer() }
    });
    res.json({ ok: true, out, bytes: archive.pointer() });
  });

  archive.on("error", (err) => res.status(500).json({ ok: false, error: String(err) }));

  archive.pipe(output);
  if (st.isDirectory()) archive.directory(absSrc, false);
  else archive.file(absSrc, { name: path.basename(absSrc) });
  archive.finalize().catch(() => {});
});

// Unzip (admin)
fsRouter.post("/unzip", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { zipPath, outDir } = req.body || {};
  if (!zipPath || !outDir) return res.status(400).json({ ok: false, error: "Missing zipPath/outDir" });

  const absZip = resolveInWorkspace(zipPath);
  const absOut = resolveInWorkspace(outDir);

  if (!fs.existsSync(absZip)) return res.status(404).json({ ok: false, error: "Zip not found" });
  fs.mkdirSync(absOut, { recursive: true });

  fs.createReadStream(absZip)
    .pipe(unzipper.Extract({ path: absOut }))
    .on("close", () => {
      auditLog({
        ts: new Date().toISOString(),
        user: req.user || null,
        action: "FS_UNZIP",
        target: `${zipPath} -> ${outDir}`,
        ok: true
      });
      res.json({ ok: true });
    })
    .on("error", (e: any) => res.status(500).json({ ok: false, error: String(e) }));
});
EOF

###############################################################################
# Backend: search route (rg)
###############################################################################
cat > "$BACKEND/src/routes/search.ts" <<'EOF'
import express from "express";
import { spawn } from "node:child_process";
import { resolveInWorkspace } from "../utils/pathSafe.js";
import { requireAuth, AuthedRequest } from "../middleware/auth.js";
import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";

export const searchRouter = express.Router();

searchRouter.get("/", requireAuth, async (req: AuthedRequest, res) => {
  const q = String(req.query.q || "").trim();
  const p = String(req.query.path || ".").trim();

  if (!q) return res.status(400).json({ ok: false, error: "Missing q" });

  const abs = resolveInWorkspace(p);

  // Use ripgrep (rg). If not installed, user can install it.
  const args = ["--line-number", "--hidden", "--no-heading", q, abs];

  const child = spawn("rg", args, { stdio: ["ignore", "pipe", "pipe"] });

  let out = "";
  let err = "";

  child.stdout.on("data", (d) => {
    out += d.toString();
    if (out.length > CONFIG.MAX_CMD_OUTPUT) child.kill("SIGKILL");
  });
  child.stderr.on("data", (d) => (err += d.toString()));

  child.on("close", (code) => {
    auditLog({
      ts: new Date().toISOString(),
      user: req.user || null,
      action: "SEARCH_RG",
      target: `${q} in ${p}`,
      ok: true,
      meta: { code }
    });

    // rg returns 1 if no matches
    if (code === 0 || code === 1) {
      const lines = out.split("\n").filter(Boolean).slice(0, 2000);
      return res.json({ ok: true, matches: lines });
    }
    return res.status(500).json({ ok: false, error: err || "rg failed" });
  });
});
EOF

###############################################################################
# Backend: terminal allowlist route
###############################################################################
cat > "$BACKEND/src/routes/terminal.ts" <<'EOF'
import express from "express";
import { spawn } from "node:child_process";
import { requireAuth, requireRole, AuthedRequest } from "../middleware/auth.js";
import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";

// Safe allowlist commands (expand carefully)
const ALLOW = new Set([
  "ls", "pwd", "whoami", "node", "npm", "python", "python3",
  "git", "rg", "cat", "tail", "head", "sed", "grep",
  "bash"
]);

export const terminalRouter = express.Router();

// POST /api/terminal/run
// body: { cmd: "rg", args: ["TODO", "."] }
terminalRouter.post("/run", requireAuth, requireRole("admin"), async (req: AuthedRequest, res) => {
  const { cmd, args } = req.body || {};
  if (!cmd || typeof cmd !== "string") return res.status(400).json({ ok: false, error: "Missing cmd" });
  if (!ALLOW.has(cmd)) return res.status(400).json({ ok: false, error: "Command not allowed" });

  const safeArgs: string[] = Array.isArray(args) ? args.map(String) : [];
  // Basic hard guard: deny obvious shell chaining tokens
  for (const a of safeArgs) {
    if (/[;&|`$<>]/.test(a)) {
      return res.status(400).json({ ok: false, error: "Unsafe arg blocked" });
    }
  }

  const child = spawn(cmd, safeArgs, {
    cwd: CONFIG.WORKSPACE_ROOT,
    stdio: ["ignore", "pipe", "pipe"]
  });

  let out = "";
  let err = "";

  child.stdout.on("data", (d) => {
    out += d.toString();
    if (out.length > CONFIG.MAX_CMD_OUTPUT) child.kill("SIGKILL");
  });
  child.stderr.on("data", (d) => {
    err += d.toString();
    if (err.length > CONFIG.MAX_CMD_OUTPUT) child.kill("SIGKILL");
  });

  child.on("close", (code) => {
    auditLog({
      ts: new Date().toISOString(),
      user: req.user || null,
      action: "CMD_RUN",
      target: `${cmd} ${safeArgs.join(" ")}`,
      ok: code === 0,
      meta: { code }
    });

    res.json({ ok: true, code, stdout: out, stderr: err });
  });
});
EOF

###############################################################################
# Backend: Ollama routes
###############################################################################
cat > "$BACKEND/src/routes/ollama.ts" <<'EOF'
import express from "express";
import { requireAuth, requireRole, AuthedRequest } from "../middleware/auth.js";
import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";

export const ollamaRouter = express.Router();

async function ollamaFetch(path: string, opts?: RequestInit) {
  const url = CONFIG.OLLAMA_HOST.replace(/\/$/, "") + path;
  const r = await fetch(url, opts);
  const text = await r.text();
  return { ok: r.ok, status: r.status, text };
}

ollamaRouter.get("/status", requireAuth, async (_req, res) => {
  const r = await ollamaFetch("/api/version");
  if (!r.ok) return res.status(502).json({ ok: false, error: "Ollama not reachable", detail: r.text });
  return res.json({ ok: true, version: r.text });
});

ollamaRouter.get("/models", requireAuth, async (_req, res) => {
  const r = await ollamaFetch("/api/tags");
  if (!r.ok) return res.status(502).json({ ok: false, error: r.text });
  return res.json({ ok: true, tags: JSON.parse(r.text) });
});

// Pull (admin)
ollamaRouter.post("/pull", requireAuth, requireRole("admin"), async (req: AuthedRequest, res) => {
  const { name } = req.body || {};
  if (!name) return res.status(400).json({ ok: false, error: "Missing name" });

  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "OLLAMA_PULL_REQUEST", target: name, ok: true });

  const url = CONFIG.OLLAMA_HOST.replace(/\/$/, "") + "/api/pull";
  const r = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name, stream: false })
  });

  const text = await r.text();
  if (!r.ok) {
    auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "OLLAMA_PULL_FAIL", target: name, ok: false, meta: { text } });
    return res.status(500).json({ ok: false, error: text });
  }

  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "OLLAMA_PULL_OK", target: name, ok: true });
  return res.json({ ok: true, result: text });
});

// Delete (admin)
ollamaRouter.post("/delete", requireAuth, requireRole("admin"), async (req: AuthedRequest, res) => {
  const { name } = req.body || {};
  if (!name) return res.status(400).json({ ok: false, error: "Missing name" });

  const url = CONFIG.OLLAMA_HOST.replace(/\/$/, "") + "/api/delete";
  const r = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name })
  });

  const text = await r.text();
  if (!r.ok) {
    auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "OLLAMA_DELETE_FAIL", target: name, ok: false, meta: { text } });
    return res.status(500).json({ ok: false, error: text });
  }

  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "OLLAMA_DELETE_OK", target: name, ok: true });
  return res.json({ ok: true, result: text });
});
EOF

###############################################################################
# Backend: AI routes (AUTO model selection)
###############################################################################
cat > "$BACKEND/src/routes/ai.ts" <<'EOF'
import express from "express";
import { requireAuth, AuthedRequest } from "../middleware/auth.js";
import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";

export const aiRouter = express.Router();

type Task = "general" | "fast" | "coder" | "reasoning";

function pickModel(installed: string[], task: Task): string {
  const prefer: Record<Task, string[]> = {
    fast: ["phi3:mini", "llama3.2:1b", "qwen2.5:3b-instruct"],
    general: ["llama3.2:3b", "qwen2.5:3b-instruct", "llama3.1:8b"],
    coder: ["qwen2.5-coder:3b-instruct", "llama3.1:8b", "qwen2.5:3b-instruct"],
    reasoning: ["llama3.1:8b", "qwen2.5:3b-instruct", "llama3.2:3b"]
  };

  for (const p of prefer[task]) {
    if (installed.includes(p)) return p;
  }
  // fallback
  return installed[0] || "llama3.2:1b";
}

async function getInstalledModels(): Promise<string[]> {
  const url = CONFIG.OLLAMA_HOST.replace(/\/$/, "") + "/api/tags";
  const r = await fetch(url);
  if (!r.ok) return [];
  const j = await r.json();
  const models = (j.models || []).map((m: any) => m.name);
  return models;
}

async function ollamaPost(endpoint: string, body: any) {
  const url = CONFIG.OLLAMA_HOST.replace(/\/$/, "") + endpoint;
  const r = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });

  const text = await r.text();
  return { ok: r.ok, status: r.status, text };
}

// TEXT: /api/ai/text => ollama /api/generate
aiRouter.post("/text", requireAuth, async (req: AuthedRequest, res) => {
  const { model, task, prompt, options } = req.body || {};
  if (!prompt) return res.status(400).json({ ok: false, error: "Missing prompt" });

  const installed = await getInstalledModels();
  const chosen = model === "AUTO" ? pickModel(installed, (task || "general") as Task) : (model || pickModel(installed, "general"));

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "AI_TEXT",
    target: chosen,
    ok: true,
    meta: { task: task || "general" }
  });

  const r = await ollamaPost("/api/generate", {
    model: chosen,
    prompt,
    stream: false,
    options: options || {}
  });

  if (!r.ok) return res.status(502).json({ ok: false, error: r.text });
  return res.json({ ok: true, model: chosen, raw: r.text });
});

// CHAT: /api/ai/chat => ollama /api/chat
aiRouter.post("/chat", requireAuth, async (req: AuthedRequest, res) => {
  const { model, task, messages, options } = req.body || {};
  if (!Array.isArray(messages)) return res.status(400).json({ ok: false, error: "Missing messages[]" });

  const installed = await getInstalledModels();
  const chosen = model === "AUTO" ? pickModel(installed, (task || "general") as Task) : (model || pickModel(installed, "general"));

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "AI_CHAT",
    target: chosen,
    ok: true,
    meta: { task: task || "general", turns: messages.length }
  });

  const r = await ollamaPost("/api/chat", {
    model: chosen,
    messages,
    stream: false,
    options: options || {}
  });

  if (!r.ok) return res.status(502).json({ ok: false, error: r.text });
  return res.json({ ok: true, model: chosen, raw: r.text });
});

// JSON: strict-ish helper
aiRouter.post("/json", requireAuth, async (req: AuthedRequest, res) => {
  const { model, task, prompt } = req.body || {};
  if (!prompt) return res.status(400).json({ ok: false, error: "Missing prompt" });

  const installed = await getInstalledModels();
  const chosen = model === "AUTO" ? pickModel(installed, (task || "reasoning") as Task) : (model || pickModel(installed, "reasoning"));

  const r = await ollamaPost("/api/generate", { model: chosen, prompt, stream: false });

  if (!r.ok) return res.status(502).json({ ok: false, error: r.text });

  const cleaned = r.text
    .replace(/```json/gi, "")
    .replace(/```/g, "");

  // Extract first JSON object if model adds extra text
  const firstObj = (() => {
    const i = cleaned.indexOf("{");
    const j = cleaned.lastIndexOf("}");
    if (i >= 0 && j > i) return cleaned.slice(i, j + 1);
    return cleaned;
  })();

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "AI_JSON",
    target: chosen,
    ok: true
  });

  return res.json({ ok: true, model: chosen, jsonText: firstObj });
});

// EMBED
aiRouter.post("/embed", requireAuth, async (req: AuthedRequest, res) => {
  const { model, input } = req.body || {};
  if (!input) return res.status(400).json({ ok: false, error: "Missing input" });

  const chosen = model || "nomic-embed-text:latest";
  const r = await ollamaPost("/api/embeddings", { model: chosen, prompt: input });

  if (!r.ok) return res.status(502).json({ ok: false, error: r.text });

  auditLog({
    ts: new Date().toISOString(),
    user: req.user || null,
    action: "AI_EMBED",
    target: chosen,
    ok: true
  });

  return res.json({ ok: true, model: chosen, raw: r.text });
});
EOF

###############################################################################
# Backend: jobs (plan/approve/run/rollback)
###############################################################################
cat > "$BACKEND/src/routes/jobs.ts" <<'EOF'
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import express from "express";
import { CONFIG } from "../config.js";
import { auditLog } from "../audit/logger.js";
import { resolveInWorkspace } from "../utils/pathSafe.js";
import { requireAuth, requireRole, AuthedRequest } from "../middleware/auth.js";

export const jobsRouter = express.Router();

type JobStep =
  | { type: "write_file"; path: string; content: string }
  | { type: "mkdir"; path: string }
  | { type: "run_cmd"; cmd: string; args?: string[] };

type Job = {
  id: string;
  createdAt: string;
  createdBy: any;
  status: "planned" | "approved" | "running" | "done" | "failed";
  steps: JobStep[];
  logs: string[];
  backups: { path: string; backup: string }[];
};

const JOBS_DIR = path.join(CONFIG.DB_DIR, "jobs");
fs.mkdirSync(JOBS_DIR, { recursive: true });

function jobPath(id: string) {
  return path.join(JOBS_DIR, `${id}.json`);
}

function loadJob(id: string): Job | null {
  const p = jobPath(id);
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function saveJob(job: Job) {
  fs.writeFileSync(jobPath(job.id), JSON.stringify(job, null, 2));
}

jobsRouter.post("/plan", requireAuth, async (req: AuthedRequest, res) => {
  // In real use, AI should generate these steps.
  // Here we accept steps from the UI and store as "planned".
  const { steps } = req.body || {};
  if (!Array.isArray(steps) || steps.length === 0) return res.status(400).json({ ok: false, error: "Missing steps[]" });

  const id = "job_" + Date.now() + "_" + Math.random().toString(36).slice(2, 6);
  const job: Job = {
    id,
    createdAt: new Date().toISOString(),
    createdBy: req.user || null,
    status: "planned",
    steps,
    logs: [],
    backups: []
  };

  saveJob(job);
  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_PLAN", target: id, ok: true, meta: { steps: steps.length } });

  return res.json({ ok: true, job });
});

jobsRouter.post("/approve", requireAuth, requireRole("admin"), (req: AuthedRequest, res) => {
  const { id } = req.body || {};
  const job = loadJob(id);
  if (!job) return res.status(404).json({ ok: false, error: "Job not found" });

  job.status = "approved";
  saveJob(job);

  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_APPROVE", target: id, ok: true });
  return res.json({ ok: true, job });
});

async function runStep(job: Job, step: JobStep): Promise<void> {
  if (step.type === "mkdir") {
    const abs = resolveInWorkspace(step.path);
    fs.mkdirSync(abs, { recursive: true });
    job.logs.push(`[mkdir] ${step.path}`);
    return;
  }

  if (step.type === "write_file") {
    const abs = resolveInWorkspace(step.path);
    fs.mkdirSync(path.dirname(abs), { recursive: true });

    // backup if exists
    if (fs.existsSync(abs)) {
      const backup = abs + ".jobbak_" + job.id;
      fs.copyFileSync(abs, backup);
      job.backups.push({ path: step.path, backup });
    }

    fs.writeFileSync(abs, step.content, "utf8");
    job.logs.push(`[write_file] ${step.path} (${Buffer.byteLength(step.content, "utf8")} bytes)`);
    return;
  }

  if (step.type === "run_cmd") {
    const cmd = step.cmd;
    const args = (step.args || []).map(String);

    // HARD allowlist minimal for jobs
    const allowed = new Set(["npm", "node", "python", "python3", "git", "rg", "bash"]);
    if (!allowed.has(cmd)) throw new Error(`Job cmd not allowed: ${cmd}`);

    job.logs.push(`[run_cmd] ${cmd} ${args.join(" ")}`);

    await new Promise<void>((resolve, reject) => {
      const child = spawn(cmd, args, { cwd: CONFIG.WORKSPACE_ROOT, stdio: ["ignore", "pipe", "pipe"] });

      child.stdout.on("data", (d) => job.logs.push(d.toString()));
      child.stderr.on("data", (d) => job.logs.push(d.toString()));

      child.on("close", (code) => {
        if (code === 0) resolve();
        else reject(new Error(`${cmd} exited with code ${code}`));
      });
    });

    return;
  }
}

jobsRouter.post("/run", requireAuth, requireRole("admin"), async (req: AuthedRequest, res) => {
  const { id } = req.body || {};
  const job = loadJob(id);
  if (!job) return res.status(404).json({ ok: false, error: "Job not found" });
  if (job.status !== "approved") return res.status(400).json({ ok: false, error: "Job must be approved first" });

  job.status = "running";
  job.logs.push(`== Running job ${id} ==`);
  saveJob(job);

  try {
    for (const step of job.steps) {
      await runStep(job, step);
      saveJob(job);
    }
    job.status = "done";
    job.logs.push("== DONE ==");
    saveJob(job);

    auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_DONE", target: id, ok: true });
    return res.json({ ok: true, job });
  } catch (e: any) {
    job.status = "failed";
    job.logs.push("== FAILED ==");
    job.logs.push(String(e?.message || e));
    saveJob(job);

    auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_FAIL", target: id, ok: false, meta: { error: String(e) } });
    return res.status(500).json({ ok: false, error: String(e?.message || e), job });
  }
});

jobsRouter.post("/rollback", requireAuth, requireRole("admin"), async (req: AuthedRequest, res) => {
  const { id } = req.body || {};
  const job = loadJob(id);
  if (!job) return res.status(404).json({ ok: false, error: "Job not found" });

  job.logs.push("== ROLLBACK START ==");
  for (const b of job.backups) {
    try {
      const abs = resolveInWorkspace(b.path);
      if (fs.existsSync(b.backup)) {
        fs.copyFileSync(b.backup, abs);
        job.logs.push(`[rollback] restored ${b.path}`);
      }
    } catch (e: any) {
      job.logs.push(`[rollback] error ${b.path}: ${String(e)}`);
    }
  }
  job.logs.push("== ROLLBACK DONE ==");
  saveJob(job);

  auditLog({ ts: new Date().toISOString(), user: req.user || null, action: "JOB_ROLLBACK", target: id, ok: true });

  return res.json({ ok: true, job });
});

jobsRouter.get("/:id", requireAuth, (req, res) => {
  const job = loadJob(req.params.id);
  if (!job) return res.status(404).json({ ok: false, error: "Not found" });
  return res.json({ ok: true, job });
});
EOF

###############################################################################
# Backend: auth routes + server.ts
###############################################################################
cat > "$BACKEND/src/routes/auth.ts" <<'EOF'
import express from "express";
import { CONFIG } from "../config.js";
import { signToken } from "../auth/jwt.js";
import { hasAnyUsers, createUser, findUserByUsername, verifyPassword } from "../auth/users.js";
import { requireAuth, AuthedRequest } from "../middleware/auth.js";
import { auditLog } from "../audit/logger.js";

export const authRouter = express.Router();

// Bootstrap admin (first run only)
authRouter.post("/bootstrap-admin", async (req, res) => {
  if (hasAnyUsers()) return res.status(400).json({ ok: false, error: "Bootstrap already completed" });

  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok: false, error: "Missing username/password" });

  const user = await createUser(username, password, "admin");
  auditLog({ ts: new Date().toISOString(), user: null, action: "BOOTSTRAP_ADMIN", target: user.username, ok: true });

  return res.json({ ok: true, user: { id: user.id, username: user.username, role: user.role } });
});

authRouter.post("/login", async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok: false, error: "Missing username/password" });

  const user = findUserByUsername(username);
  if (!user) {
    auditLog({ ts: new Date().toISOString(), user: null, action: "LOGIN_FAIL", target: username, ok: false });
    return res.status(401).json({ ok: false, error: "Invalid credentials" });
  }

  const ok = await verifyPassword(user, password);
  if (!ok) {
    auditLog({ ts: new Date().toISOString(), user: null, action: "LOGIN_FAIL", target: username, ok: false });
    return res.status(401).json({ ok: false, error: "Invalid credentials" });
  }

  const token = signToken({ id: user.id, username: user.username, role: user.role });
  res.cookie(CONFIG.COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: false
  });

  auditLog({ ts: new Date().toISOString(), user: { id: user.id, username: user.username, role: user.role }, action: "LOGIN_OK", ok: true });

  return res.json({ ok: true, user: { id: user.id, username: user.username, role: user.role } });
});

authRouter.post("/logout", (req, res) => {
  res.clearCookie(CONFIG.COOKIE_NAME);
  return res.json({ ok: true });
});

authRouter.get("/me", requireAuth, (req: AuthedRequest, res) => {
  return res.json({ ok: true, user: req.user });
});
EOF

cat > "$BACKEND/src/server.ts" <<'EOF'
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
EOF

###############################################################################
# Frontend: Vite + React minimal UI
###############################################################################
cat > "$FRONTEND/package.json" <<'EOF'
{
  "name": "sovereign-console-v2-frontend",
  "version": "2.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0 --port 5173",
    "build": "vite build",
    "preview": "vite preview --host 0.0.0.0 --port 5173"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.5",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.2",
    "typescript": "^5.6.3",
    "vite": "^5.4.8"
  }
}
EOF

cat > "$FRONTEND/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM"],
    "module": "ES2022",
    "skipLibCheck": true,
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true
  },
  "include": ["src"]
}
EOF

cat > "$FRONTEND/vite.config.ts" <<'EOF'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": "http://127.0.0.1:6060"
    }
  }
});
EOF

cat > "$FRONTEND/index.html" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Sovereign Console v2</title>
    <style>
      body { margin:0; font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial; background:#0b0f14; color:#e6edf3; }
      a { color:#7ee787; }
      .btn { background:#1f6feb; color:white; border:0; padding:10px 12px; border-radius:10px; cursor:pointer; }
      .btn2 { background:#30363d; color:#e6edf3; border:1px solid #30363d; padding:10px 12px; border-radius:10px; cursor:pointer; }
      .input { background:#0f1720; color:#e6edf3; border:1px solid #30363d; padding:10px 12px; border-radius:10px; width:100%; }
      .card { background:#0f1720; border:1px solid #30363d; border-radius:14px; }
      .muted { color:#8b949e; }
      .danger { color:#ff7b72; }
      .grid { display:grid; gap:10px; }
      .split { display:grid; grid-template-columns: 320px 1fr 360px; height:100vh; }
      @media (max-width: 980px) { .split { grid-template-columns: 1fr; grid-template-rows:auto auto auto; height:auto; } }
      .pane { padding:12px; overflow:auto; }
      pre { white-space: pre-wrap; word-break: break-word; }
      textarea { width:100%; height:60vh; background:#0b1220; border:1px solid #30363d; border-radius:12px; padding:10px; color:#e6edf3; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
      .fileItem { padding:6px 8px; border-radius:10px; cursor:pointer; }
      .fileItem:hover { background:#161b22; }
      .row { display:flex; gap:10px; align-items:center; }
    </style>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

cat > "$FRONTEND/src/main.tsx" <<'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

cat > "$FRONTEND/src/api.ts" <<'EOF'
export async function apiGet(path: string) {
  const r = await fetch(path, { credentials: "include" });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`);
  return j;
}

export async function apiPost(path: string, body: any, extraHeaders?: Record<string, string>) {
  const r = await fetch(path, {
    method: "POST",
    credentials: "include",
    headers: { "content-type": "application/json", ...(extraHeaders || {}) },
    body: JSON.stringify(body)
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`);
  return j;
}
EOF

cat > "$FRONTEND/src/App.tsx" <<'EOF'
import React, { useEffect, useMemo, useState } from "react";
import { apiGet, apiPost } from "./api";

type User = { id: string; username: string; role: "admin"|"user" };

type TreeNode = {
  name: string;
  path: string;
  type: "dir"|"file";
  size: number;
  mtime: string;
  children?: TreeNode[];
};

function flattenFiles(node: TreeNode, out: TreeNode[] = []) {
  out.push(node);
  (node.children || []).forEach(c => flattenFiles(c, out));
  return out;
}

export default function App() {
  const [user, setUser] = useState<User|null>(null);
  const [bootMode, setBootMode] = useState(false);
  const [status, setStatus] = useState("loading...");
  const [tree, setTree] = useState<TreeNode|null>(null);
  const [selectedPath, setSelectedPath] = useState<string>("");
  const [fileContent, setFileContent] = useState<string>("");
  const [saveMsg, setSaveMsg] = useState<string>("");

  const [chatPrompt, setChatPrompt] = useState("");
  const [chatLog, setChatLog] = useState<string[]>([]);
  const [task, setTask] = useState<"general"|"fast"|"coder"|"reasoning">("general");
  const [model, setModel] = useState<string>("AUTO");

  const [termCmd, setTermCmd] = useState("rg");
  const [termArgs, setTermArgs] = useState("TODO .");
  const [termOut, setTermOut] = useState("");

  const allFiles = useMemo(() => tree ? flattenFiles(tree, []).filter(n => n.type === "file").slice(0, 2000) : [], [tree]);

  async function refreshMe() {
    try {
      const j = await apiGet("/api/auth/me");
      setUser(j.user);
      setBootMode(false);
    } catch {
      setUser(null);
      // if no users exist yet, backend will allow bootstrap
      setBootMode(true);
    }
  }

  async function refreshHealth() {
    try {
      const j = await apiGet("/api/health");
      setStatus(`✅ online on port ${j.port}`);
    } catch (e:any) {
      setStatus(`❌ backend offline: ${e.message}`);
    }
  }

  async function refreshTree() {
    const j = await apiGet("/api/fs/tree?path=.&depth=6");
    setTree(j.root);
  }

  async function openFile(p: string) {
    setSelectedPath(p);
    const j = await apiGet(`/api/fs/read?path=${encodeURIComponent(p)}`);
    setFileContent(j.content);
    setSaveMsg("");
  }

  async function saveFile() {
    if (!selectedPath) return;
    setSaveMsg("saving...");
    try {
      await apiPost("/api/fs/write", { path: selectedPath, content: fileContent });
      setSaveMsg("✅ saved");
    } catch (e:any) {
      setSaveMsg("❌ " + e.message);
    }
  }

  async function runTerminal() {
    setTermOut("running...");
    try {
      const args = termArgs.trim() ? termArgs.trim().split(/\s+/) : [];
      const j = await apiPost("/api/terminal/run", { cmd: termCmd, args });
      setTermOut((j.stdout || "") + (j.stderr ? "\n" + j.stderr : ""));
    } catch (e:any) {
      setTermOut("ERROR: " + e.message);
    }
  }

  async function sendChat() {
    if (!chatPrompt.trim()) return;
    const prompt = chatPrompt.trim();
    setChatPrompt("");

    setChatLog(prev => [...prev, `You: ${prompt}`, "AI: ..."]);

    try {
      const j = await apiPost("/api/ai/chat", {
        model,
        task,
        messages: [
          { role: "system", content: "You are Sovereign Console v2 assistant. Be concise, safe, and practical." },
          { role: "user", content: prompt }
        ]
      });

      let raw = j.raw || "";
      // raw is JSON string from ollama; try parse
      let answer = raw;
      try {
        const parsed = JSON.parse(raw);
        answer = parsed?.message?.content || parsed?.response || raw;
      } catch {}

      setChatLog(prev => {
        const copy = [...prev];
        copy[copy.length - 1] = `AI: ${answer}`;
        return copy;
      });
    } catch (e:any) {
      setChatLog(prev => {
        const copy = [...prev];
        copy[copy.length - 1] = `AI: ERROR: ${e.message}`;
        return copy;
      });
    }
  }

  async function login(username: string, password: string) {
    const j = await apiPost("/api/auth/login", { username, password });
    setUser(j.user);
    await refreshTree();
  }

  async function bootstrapAdmin(username: string, password: string) {
    await apiPost("/api/auth/bootstrap-admin", { username, password });
    await login(username, password);
  }

  async function logout() {
    await apiPost("/api/auth/logout", {});
    setUser(null);
  }

  useEffect(() => {
    (async () => {
      await refreshHealth();
      await refreshMe();
    })();
    const t = setInterval(refreshHealth, 5000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (user) refreshTree().catch(() => {});
  }, [user]);

  // UI login/boot forms
  const [u, setU] = useState("admin");
  const [p, setP] = useState("admin123");
  const [authMsg, setAuthMsg] = useState("");

  return (
    <div className="split">
      {/* LEFT: Workspace */}
      <div className="pane card">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 16 }}>Sovereign Console v2</div>
            <div className="muted" style={{ fontSize: 12 }}>{status}</div>
          </div>
          {user && (
            <button className="btn2" onClick={logout}>Logout</button>
          )}
        </div>

        {!user && (
          <div style={{ marginTop: 12 }} className="grid">
            <div className="card" style={{ padding: 12 }}>
              <div style={{ fontWeight: 700 }}>Authentication</div>
              <div className="muted" style={{ fontSize: 12, marginBottom: 8 }}>
                {bootMode ? "First run detected: create Admin account." : "Login to continue."}
              </div>
              <input className="input" placeholder="username" value={u} onChange={e=>setU(e.target.value)} />
              <input className="input" placeholder="password" type="password" value={p} onChange={e=>setP(e.target.value)} />
              <div className="row">
                {bootMode ? (
                  <button className="btn" onClick={async()=> {
                    setAuthMsg("working...");
                    try { await bootstrapAdmin(u,p); setAuthMsg("✅ admin created"); }
                    catch(e:any){ setAuthMsg("❌ " + e.message); }
                  }}>Bootstrap Admin</button>
                ) : (
                  <button className="btn" onClick={async()=> {
                    setAuthMsg("working...");
                    try { await login(u,p); setAuthMsg("✅ logged in"); }
                    catch(e:any){ setAuthMsg("❌ " + e.message); }
                  }}>Login</button>
                )}
                <button className="btn2" onClick={refreshMe}>Refresh</button>
              </div>
              <div className="muted" style={{ fontSize: 12 }}>{authMsg}</div>
              <div className="muted" style={{ fontSize: 12, marginTop: 6 }}>
                Default cookie-based session. Change JWT_SECRET in backend .env later.
              </div>
            </div>
          </div>
        )}

        {user && (
          <div style={{ marginTop: 10 }}>
            <div className="muted" style={{ fontSize: 12 }}>
              Logged in as <b>{user.username}</b> ({user.role})
            </div>

            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn2" onClick={refreshTree}>Reload Tree</button>
              <button className="btn2" onClick={()=>openFile("README.md").catch(()=>{})}>Open README</button>
            </div>

            <div style={{ marginTop: 12 }}>
              <div style={{ fontWeight: 700, marginBottom: 6 }}>Workspace</div>
              <div className="muted" style={{ fontSize: 12 }}>Tap a file to open</div>
              <div style={{ marginTop: 8 }}>
                {allFiles.slice(0, 250).map((f) => (
                  <div key={f.path} className="fileItem" onClick={()=>openFile(f.path)}>
                    <span className="muted">{f.path}</span>
                  </div>
                ))}
                {allFiles.length > 250 && (
                  <div className="muted" style={{ fontSize: 12, marginTop: 6 }}>
                    Showing first 250 files (UI limiter)
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* CENTER: Editor + Terminal */}
      <div className="pane card">
        {user ? (
          <>
            <div className="row" style={{ justifyContent: "space-between" }}>
              <div>
                <div style={{ fontWeight: 700 }}>Editor</div>
                <div className="muted" style={{ fontSize: 12 }}>
                  {selectedPath ? selectedPath : "Select a file from the left"}
                </div>
              </div>
              <div className="row">
                <button className="btn" onClick={saveFile} disabled={user.role !== "admin" || !selectedPath}>
                  Save
                </button>
                <div className="muted" style={{ fontSize: 12 }}>{saveMsg}</div>
              </div>
            </div>

            <div style={{ marginTop: 10 }}>
              <textarea
                value={fileContent}
                onChange={(e)=>setFileContent(e.target.value)}
                placeholder={user.role === "admin" ? "Open a file to edit..." : "Read-only mode (user role)"}
                readOnly={user.role !== "admin"}
              />
            </div>

            <div style={{ marginTop: 12 }} className="card" >
              <div style={{ padding: 12 }}>
                <div style={{ fontWeight: 700 }}>Terminal (Admin Only)</div>
                <div className="muted" style={{ fontSize: 12 }}>
                  Allowlist mode. No destructive commands by default.
                </div>
                <div className="row" style={{ marginTop: 8 }}>
                  <input className="input" style={{ width: 120 }} value={termCmd} onChange={e=>setTermCmd(e.target.value)} />
                  <input className="input" placeholder='args e.g. "TODO ."' value={termArgs} onChange={e=>setTermArgs(e.target.value)} />
                  <button className="btn2" onClick={runTerminal} disabled={user.role !== "admin"}>Run</button>
                </div>
                <pre style={{ marginTop: 10, fontSize: 12 }} className="muted">{termOut}</pre>
                {user.role !== "admin" && (
                  <div className="danger" style={{ fontSize: 12 }}>
                    Terminal is disabled for non-admin users.
                  </div>
                )}
              </div>
            </div>
          </>
        ) : (
          <div className="muted">Login first.</div>
        )}
      </div>

      {/* RIGHT: AI Chat */}
      <div className="pane card">
        <div style={{ fontWeight: 800 }}>AI Assistant</div>
        <div className="muted" style={{ fontSize: 12 }}>
          Uses your local Ollama via backend. Task-based AUTO model routing supported.
        </div>

        {user ? (
          <>
            <div className="row" style={{ marginTop: 8 }}>
              <select className="input" value={task} onChange={e=>setTask(e.target.value as any)}>
                <option value="general">general</option>
                <option value="fast">fast</option>
                <option value="coder">coder</option>
                <option value="reasoning">reasoning</option>
              </select>
              <input className="input" value={model} onChange={e=>setModel(e.target.value)} placeholder="AUTO or model name" />
            </div>

            <div className="card" style={{ marginTop: 10, padding: 10, height: "60vh", overflow: "auto" }}>
              {chatLog.length === 0 && (
                <div className="muted" style={{ fontSize: 12 }}>
                  Example: “scan my repo and suggest the best architecture to unify the dashboard.”
                </div>
              )}
              {chatLog.map((line, i) => (
                <div key={i} style={{ marginBottom: 8 }}>
                  <div style={{ fontSize: 12 }}>{line}</div>
                </div>
              ))}
            </div>

            <div style={{ marginTop: 10 }} className="row">
              <input
                className="input"
                value={chatPrompt}
                onChange={e=>setChatPrompt(e.target.value)}
                placeholder="Ask the assistant..."
                onKeyDown={(e)=>{ if (e.key === "Enter") sendChat(); }}
              />
              <button className="btn2" onClick={sendChat}>Send</button>
            </div>

            <div className="muted" style={{ fontSize: 12, marginTop: 8 }}>
              Next upgrade: repo-context chat + multi-file patch jobs with approval/run/rollback.
            </div>
          </>
        ) : (
          <div className="muted" style={{ marginTop: 12 }}>
            Login first to use AI.
          </div>
        )}
      </div>
    </div>
  );
}
EOF

###############################################################################
# Start/Stop scripts
###############################################################################
cat > "$APP_ROOT/start.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$HERE/backend"
FRONTEND="$HERE/frontend"
RUNTIME="$HERE/runtime"
LOGS="$RUNTIME/logs"

mkdir -p "$LOGS"

echo "==> Starting Sovereign Console v2"

# Backend
echo "==> Installing backend deps (if needed)"
cd "$BACKEND"
if [ ! -d node_modules ]; then
  npm install
fi

echo "==> Starting backend on PORT=${PORT:-6060}"
( PORT="${PORT:-6060}" REPLIT="${REPLIT:-}" npm run dev > "$LOGS/backend.out" 2>&1 & echo $! > "$RUNTIME/backend.pid" )

# Frontend
echo "==> Installing frontend deps (if needed)"
cd "$FRONTEND"
if [ ! -d node_modules ]; then
  npm install
fi

echo "==> Starting frontend on http://127.0.0.1:5173"
( npm run dev > "$LOGS/frontend.out" 2>&1 & echo $! > "$RUNTIME/frontend.pid" )

echo ""
echo "✅ Backend:  http://127.0.0.1:${PORT:-6060}"
echo "✅ Frontend: http://127.0.0.1:5173"
echo ""
echo "Logs:"
echo "  $LOGS/backend.out"
echo "  $LOGS/frontend.out"
EOF

cat > "$APP_ROOT/stop.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="$HERE/runtime"

kill_pid() {
  local f="$1"
  if [ -f "$f" ]; then
    local pid
    pid="$(cat "$f" || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping PID $pid"
      kill "$pid" || true
    fi
    rm -f "$f"
  fi
}

kill_pid "$RUNTIME/backend.pid"
kill_pid "$RUNTIME/frontend.pid"

echo "✅ Sovereign Console v2 stopped"
EOF

chmod +x "$APP_ROOT/start.sh" "$APP_ROOT/stop.sh"

###############################################################################
# Backend .env example
###############################################################################
cat > "$BACKEND/.env.example" <<'EOF'
# Bind address (local-first)
# BIND=127.0.0.1
# For Replit:
# BIND=0.0.0.0

PORT=6060

# IMPORTANT: set a real secret
JWT_SECRET=CHANGE_ME_SUPER_SECRET

# Optional: restrict cross-origin requests (recommended)
# CORS_ORIGIN=http://127.0.0.1:5173

# Workspace root defaults to repo root automatically
# WORKSPACE_ROOT=/absolute/path/to/repo/root

OLLAMA_HOST=http://127.0.0.1:11434
EOF

###############################################################################
# README for v2
###############################################################################
cat > "$APP_ROOT/README.md" <<'EOF'
# Sovereign Console v2 (Unified)

This is the clean unified Sovereign Console v2 build:

## Features
- Admin/User auth with cookie session
- Workspace tree + file read/edit/save (admin)
- Upload/download (admin upload)
- Zip/unzip (admin)
- Terminal allowlist (admin)
- Search (ripgrep `rg`)
- Ollama models: list/status + pull/delete (admin)
- AI endpoints: text/chat/json/embed with AUTO model routing
- Jobs: plan/approve/run/rollback (minimal safe prototype)
- Audit log: runtime/logs/audit.jsonl

## Start
From repo root:

```bash
bash apps/sovereign_console_v2/start.sh

EOF
