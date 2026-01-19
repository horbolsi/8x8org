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
