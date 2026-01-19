/**
 * Flash Sovereign Ollama Client (Production)
 * - Auto chooses a model that exists
 * - Retries 500 errors
 * - Can return TEXT or JSON
 * - Works with /api/chat and /api/embeddings
 *
 * Node 18+ recommended (global fetch)
 */

const OLLAMA_HOST = process.env.OLLAMA_HOST || "http://127.0.0.1:11434";

/** Fetch installed Ollama tags/models */
async function getInstalledModels() {
  const r = await fetch(`${OLLAMA_HOST}/api/tags`);
  if (!r.ok) throw new Error(`Failed tags: ${r.status} ${await r.text()}`);
  const json = await r.json();
  return (json.models || []).map((m) => m.name);
}

/** Choose safest available model */
async function pickModel(wanted = "phi3:mini") {
  const installed = await getInstalledModels();
  if (installed.includes(wanted)) return wanted;
  if (installed.includes("llama3.2:1b")) return "llama3.2:1b";
  if (installed.length > 0) return installed[0];
  throw new Error("No Ollama models installed.");
}

/** Sleep helper */
function sleep(ms) {
  return new Promise((res) => setTimeout(res, ms));
}

/**
 * Safe chat (returns full JSON response)
 * - retries on 500
 */
async function safeOllamaChat(userText, wantedModel = "phi3:mini", opts = {}) {
  const model = await pickModel(wantedModel);

  const system = opts.system || null;
  const temperature = typeof opts.temperature === "number" ? opts.temperature : 0.2;

  const messages = [];
  if (system) messages.push({ role: "system", content: system });
  messages.push({ role: "user", content: userText });

  const payload = {
    model,
    messages,
    stream: false,
    temperature,
  };

  // Optional forced JSON output (Ollama supports format="json" on /api/chat)
  if (opts.format === "json") payload.format = "json";

  for (let attempt = 1; attempt <= 3; attempt++) {
    const r = await fetch(`${OLLAMA_HOST}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (r.ok) return await r.json();

    // Retry only 500
    const txt = await r.text();
    if (r.status !== 500) {
      throw new Error(`Ollama chat failed (${r.status}): ${txt}`);
    }

    // backoff
    await sleep(300 * attempt);
  }

  throw new Error("Ollama chat failed after retries (500).");
}

/**
 * Safe chat text (returns assistant text)
 * - retries on 500
 * - can hard-force output rules
 */
async function safeOllamaChatText(userText, wantedModel = "phi3:mini", opts = {}) {
  // If you want exact output, pass:
  // opts.system = "Reply EXACTLY: OK ✅"
  const json = await safeOllamaChat(userText, wantedModel, opts);
  const out = (json?.message?.content || "").trim();

  // Optional "hard fix" (example)
  if (opts.forceOK && out === "OK") return "OK ✅";

  return out;
}

/**
 * Embeddings helper
 * Works best with: nomic-embed-text:latest
 */
async function safeOllamaEmbed(text, embeddingModel = "nomic-embed-text:latest") {
  const installed = await getInstalledModels();
  const model = installed.includes(embeddingModel)
    ? embeddingModel
    : (installed[0] || embeddingModel);

  const r = await fetch(`${OLLAMA_HOST}/api/embeddings`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model, prompt: text }),
  });

  if (!r.ok) {
    throw new Error(`Embeddings failed (${r.status}): ${await r.text()}`);
  }

  const json = await r.json();
  return json.embedding;
}

module.exports = {
  OLLAMA_HOST,
  getInstalledModels,
  pickModel,
  safeOllamaChat,
  safeOllamaChatText,
  safeOllamaEmbed,
};
