#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
ENVFILE="$APP/.env"

echo "✅ Repo: $REPO"
mkdir -p "$BACK"

# -----------------------------
# 1) Fix .env quoting (spaces safe)
# -----------------------------
if [ -f "$ENVFILE" ]; then
  python - <<'PY'
from pathlib import Path
p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/.env")
lines = p.read_text(errors="ignore").splitlines()
out=[]
for line in lines:
    s=line.strip()
    if not s or s.startswith("#") or "=" not in s:
        out.append(line)
        continue
    k,v=line.split("=",1)
    k=k.strip()
    v=v.strip()

    # quote anything with spaces (prevents "No command aldl found")
    if " " in v and not ((v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'"))):
        v = '"' + v.replace('"','\\"') + '"'
    out.append(f"{k}={v}")

# ensure AUTO mode + fallback chain
kv = {l.split("=",1)[0].strip(): l.split("=",1)[1].strip() for l in out if "=" in l and not l.strip().startswith("#")}
def upsert(key,val):
    nonlocal_out=[]
    found=False
    for l in out:
        if l.strip().startswith(key+"="):
            nonlocal_out.append(f"{key}={val}")
            found=True
        else:
            nonlocal_out.append(l)
    if not found:
        nonlocal_out.append(f"{key}={val}")
    return nonlocal_out

out2 = out
out2 = upsert("AI_PROVIDER", "auto")
out = out2
out2 = out
out2 = upsert("AI_PROVIDER_CHAIN", '"openai,gemini,deepseek,ollama,offline"')
out = out2
out2 = out
out2 = upsert("FLASH_MODEL", '"FlashTM8"')
out = out2

p.write_text("\n".join(out) + "\n")
print("✅ .env fixed + AUTO chain enabled")
PY
else
  echo "⚠️ Missing $ENVFILE"
  echo "Create it first: $ENVFILE"
  exit 1
fi

# -----------------------------
# 2) Patch ai_providers.py with AUTO-FALLBACK + OFFLINE MODE
# -----------------------------
cat <<'PY' > "$BACK/ai_providers.py"
import os, json, time, traceback
import requests

# -----------------------------
# Provider Utils
# -----------------------------
def _env(name, default=""):
    v = os.getenv(name, default)
    if isinstance(v, str):
        v = v.strip().strip('"').strip("'")
    return v

def _safe_err(e: Exception) -> str:
    return f"{type(e).__name__}: {str(e)}"

def _timeout():
    try:
        return int(_env("AI_TIMEOUT", "35"))
    except:
        return 35

# -----------------------------
# OFFLINE MODE (no API needed)
# Uses workspace index if present; otherwise does a simple scan
# -----------------------------
def offline_answer(user_text: str) -> str:
    try:
        from .workspace_index import search_index, load_index_stats
        hits = search_index(user_text, top_k=6)
        stats = load_index_stats()
        msg = []
        msg.append("⚡ FlashTM8 (OFFLINE MODE)")
        msg.append(f"✅ Indexed files: {stats.get('files', 'unknown')}")
        msg.append("")
        msg.append("I cannot reach any external AI provider right now, but I *can still answer* using your real repo index.")
        msg.append("")
        msg.append("Top relevant files/snippets:")
        for h in hits:
            fp = h.get("path","?")
            snippet = (h.get("snippet","") or "").strip().replace("\n"," ")
            if len(snippet) > 200:
                snippet = snippet[:200] + "..."
            msg.append(f"- {fp} :: {snippet}")
        msg.append("")
        msg.append("Ask me things like:")
        msg.append("- How do I run FlashTM8?")
        msg.append("- Where is the bot entry file?")
        msg.append("- Find the PORT logic / start scripts")
        return "\n".join(msg)
    except Exception:
        # ultra-fallback: just respond politely
        return (
            "⚡ FlashTM8 (OFFLINE MODE)\n"
            "I can’t reach any AI provider right now, but indexing/search is still available.\n"
            "Use the 'Search workspace index' tool in the UI and I will answer from those results."
        )

# -----------------------------
# Providers
# -----------------------------
def call_openai(prompt: str) -> str:
    key = _env("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("OPENAI_API_KEY missing")
    model = _env("OPENAI_MODEL", "gpt-4o-mini")
    url = _env("OPENAI_BASE_URL", "https://api.openai.com/v1/chat/completions")
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are FlashTM8 ⚡, a workspace-aware assistant for this repo."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
    }
    r = requests.post(url, headers=headers, json=payload, timeout=_timeout())
    if r.status_code >= 400:
        raise RuntimeError(f"OpenAI error {r.status_code}: {r.text}")
    return r.json()["choices"][0]["message"]["content"]

def call_gemini(prompt: str) -> str:
    key = _env("GEMINI_API_KEY") or _env("GOOGLE_API_KEY")
    if not key:
        raise RuntimeError("GEMINI_API_KEY missing")
    model = _env("GEMINI_MODEL", "gemini-1.5-flash")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    payload = {"contents": [{"parts": [{"text": "You are FlashTM8 ⚡.\n\n" + prompt}]}]}
    r = requests.post(url, json=payload, timeout=_timeout())
    if r.status_code >= 400:
        raise RuntimeError(f"Gemini error {r.status_code}: {r.text}")
    data = r.json()
    return data["candidates"][0]["content"]["parts"][0]["text"]

def call_deepseek(prompt: str) -> str:
    key = _env("DEEPSEEK_API_KEY")
    if not key:
        raise RuntimeError("DEEPSEEK_API_KEY missing")
    model = _env("DEEPSEEK_MODEL", "deepseek-chat")
    url = _env("DEEPSEEK_BASE_URL", "https://api.deepseek.com/chat/completions")
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are FlashTM8 ⚡, a workspace-aware assistant."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
    }
    r = requests.post(url, headers=headers, json=payload, timeout=_timeout())
    if r.status_code >= 400:
        raise RuntimeError(f"DeepSeek error {r.status_code}: {r.text}")
    return r.json()["choices"][0]["message"]["content"]

def call_ollama(prompt: str) -> str:
    base = _env("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    model = _env("OLLAMA_MODEL", "llama3.1")
    url = base.rstrip("/") + "/api/generate"
    payload = {"model": model, "prompt": prompt, "stream": False}
    r = requests.post(url, json=payload, timeout=_timeout())
    if r.status_code >= 400:
        raise RuntimeError(f"Ollama error {r.status_code}: {r.text}")
    return r.json().get("response","").strip()

# -----------------------------
# AUTO ROUTER
# -----------------------------
PROVIDER_MAP = {
    "openai": call_openai,
    "gemini": call_gemini,
    "deepseek": call_deepseek,
    "ollama": call_ollama,
    "offline": lambda prompt: offline_answer(prompt),
}

def generate_reply(prompt: str) -> tuple[str, str]:
    """
    Returns (provider_used, text)
    """
    provider = _env("AI_PROVIDER", "auto").lower()
    chain = _env("AI_PROVIDER_CHAIN", "openai,gemini,deepseek,ollama,offline")
    chain_list = [x.strip().lower() for x in chain.split(",") if x.strip()]

    # if user forced a provider, only use that
    if provider != "auto":
        fn = PROVIDER_MAP.get(provider)
        if not fn:
            return ("offline", offline_answer(prompt))
        return (provider, fn(prompt))

    # AUTO: try chain until something works
    last_err = None
    for p in chain_list:
        fn = PROVIDER_MAP.get(p)
        if not fn:
            continue
        try:
            text = fn(prompt)
            if text and text.strip():
                return (p, text)
        except Exception as e:
            last_err = f"{p}: {_safe_err(e)}"
            continue

    # if everything failed
    out = offline_answer(prompt)
    if last_err:
        out = out + "\n\n(Last provider error: " + last_err + ")"
    return ("offline", out)
PY

# -----------------------------
# 3) Patch app.py to show provider used in responses (small addition)
# -----------------------------
APP_PY="$BACK/app.py"
if [ -f "$APP_PY" ]; then
  # only patch if not already present
  if ! grep -q "provider_used" "$APP_PY"; then
    python - <<'PY'
from pathlib import Path
p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/app.py")
txt = p.read_text(errors="ignore")

# Try to upgrade import + response
if "from .ai_providers import" in txt and "generate_reply" not in txt:
    txt = txt.replace("from .ai_providers import", "from .ai_providers import generate_reply,")
elif "import ai_providers" in txt and "generate_reply" not in txt:
    pass

# Replace any call like: reply = generate_ai(...)
# with: provider_used, reply = generate_reply(...)
txt = txt.replace("reply = generate_ai(", "provider_used, reply = generate_reply(")
txt = txt.replace("reply = ai_generate(", "provider_used, reply = generate_reply(")
txt = txt.replace("reply = generate_reply(", "provider_used, reply = generate_reply(")

# Add provider to JSON response if flask returns dict
if "return jsonify({" in txt and '"provider"' not in txt:
    txt = txt.replace("return jsonify({", "return jsonify({\n            \"provider\": provider_used,")
p.write_text(txt)
print("✅ Patched app.py to include provider info (best-effort).")
PY
  else
    echo "✅ app.py already patched for provider info."
  fi
else
  echo "⚠️ app.py not found at: $APP_PY (skipping patch)"
fi

# -----------------------------
# 4) Ensure start script uses bash (Termux safe)
# -----------------------------
chmod +x "$REPO/start_flashtm8.sh" 2>/dev/null || true
chmod +x "$APP/run_flashtm8.sh" 2>/dev/null || true

echo ""
echo "✅ FlashTM8 AUTO-HEAL READY!"
echo "Now run:"
echo "  cd $REPO"
echo "  set -a; source $ENVFILE; set +a"
echo "  PORT=5000 bash start_flashtm8.sh"
echo ""
