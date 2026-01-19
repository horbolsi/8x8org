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
