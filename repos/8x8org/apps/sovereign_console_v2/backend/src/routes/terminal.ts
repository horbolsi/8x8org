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
