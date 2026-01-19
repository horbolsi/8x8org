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
