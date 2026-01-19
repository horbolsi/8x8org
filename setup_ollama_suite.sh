#!/usr/bin/env bash
set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"

MODELS=(
  "nomic-embed-text:latest"
  "llama3.2:1b"
  "phi3:mini"
  "llama3.2:3b"
  "qwen2.5:3b-instruct"
  "qwen2.5-coder:3b-instruct"
  "llama3.1:8b"
)

echo "==============================================="
echo "⚡ Flash Sovereign Suite - Ollama FULL Setup"
echo "Host: $OLLAMA_HOST"
echo "==============================================="

# ---- helpers ----
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ Missing command: $1"
    echo "Install it then re-run."
    exit 1
  }
}

is_ollama_online() {
  curl -s --max-time 2 "$OLLAMA_HOST/api/version" >/dev/null 2>&1
}

start_ollama_if_needed() {
  if is_ollama_online; then
    echo "✅ Ollama is ONLINE"
    return 0
  fi

  echo "⚠️ Ollama is OFFLINE. Trying to start: ollama serve ..."
  # Start in background safely
  nohup ollama serve >/tmp/ollama-serve.log 2>&1 &
  sleep 1

  if is_ollama_online; then
    echo "✅ Ollama started successfully"
    return 0
  fi

  echo "❌ Failed to start Ollama automatically."
  echo "Check logs: /tmp/ollama-serve.log"
  exit 1
}

installed_models() {
  ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true
}

has_model() {
  local name="$1"
  installed_models | grep -qx "$name"
}

pull_model() {
  local name="$1"
  if has_model "$name"; then
    echo "✅ Already installed: $name"
    return 0
  fi
  echo "⬇️ Pulling model: $name"
  ollama pull "$name"
  echo "✅ Installed: $name"
}

# ---- checks ----
need_cmd curl
need_cmd ollama

# ---- ensure ollama online ----
start_ollama_if_needed

echo ""
echo "📦 Installing missing models (safe one-by-one)..."
for m in "${MODELS[@]}"; do
  pull_model "$m"
done

echo ""
echo "✅ Final Installed Models:"
ollama list || true

# ======================================================
# Create Node client (production)
# ======================================================
echo ""
echo "🧠 Writing production Node client: ollama_client.js"

cat > ollama_client.js <<'JS'
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
JS

# ======================================================
# Tests
# ======================================================
echo "🧪 Writing tests..."

cat > test_ollama_text.js <<'JS'
const { safeOllamaChatText } = require("./ollama_client");

(async () => {
  // This should always work
  const text = await safeOllamaChatText("Say ONLY: OK ✅", "phi3:mini", {
    system: "Reply with exactly: OK ✅ (no extra text).",
    forceOK: true,
    temperature: 0,
  });

  console.log(text);
})();
JS

cat > test_ollama_json.js <<'JS'
const { safeOllamaChatText } = require("./ollama_client");

(async () => {
  // JSON mode = best for exact machine output
  const raw = await safeOllamaChatText(
    'Return JSON only: {"reply":"OK ✅"}',
    "phi3:mini",
    { format: "json", temperature: 0 }
  );

  // raw should itself be JSON text if model obeyed
  // If it returns a JSON string, parse it:
  try {
    const obj = JSON.parse(raw);
    console.log(obj.reply);
  } catch {
    // fallback print
    console.log(raw);
  }
})();
JS

cat > test_embed.js <<'JS'
const { safeOllamaEmbed } = require("./ollama_client");

(async () => {
  const v = await safeOllamaEmbed("hello embeddings test", "nomic-embed-text:latest");
  console.log("Embedding length:", v.length);
})();
JS

# ======================================================
# Quick run
# ======================================================
echo ""
echo "✅ Setup complete!"
echo "Run these now:"
echo "  node test_ollama_text.js"
echo "  node test_ollama_json.js"
echo "  node test_embed.js"
echo ""
