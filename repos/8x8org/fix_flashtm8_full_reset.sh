#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO="${1:-/home/runner/workspace/repos/8x8org}"
APP="$REPO/apps/flashtm8"
BE="$APP/backend"
RT="$APP/runtime"

echo "✅ Repo: $REPO"
mkdir -p "$BE" "$RT" "$BE/templates" "$BE/static"

# ------------------------------------------------------------
# 1) Create a SAFE .env (NO secrets inside by default)
#    - You can edit keys later from dashboard UI
# ------------------------------------------------------------
ENVFILE="$APP/.env"
cat > "$ENVFILE" <<EOF
# FlashTM8 runtime env
AI_PROVIDER=auto
PORT=5000
HOST=0.0.0.0
WORKSPACE_ROOT="$REPO"

# Optional defaults (you can also set in dashboard UI)
OLLAMA_BASE_URL="http://127.0.0.1:11434"
OLLAMA_MODEL="llama3.2:3b"

# If you want API keys via ENV you can add later:
# OPENAI_API_KEY=""
# GEMINI_API_KEY=""
# DEEPSEEK_API_KEY=""
EOF

echo "✅ Wrote: $ENVFILE"

# ------------------------------------------------------------
# 2) Backend package init (fix import issues)
# ------------------------------------------------------------
touch "$BE/__init__.py"
echo "✅ backend/__init__.py ok"

# ------------------------------------------------------------
# 3) Workspace index (simple + fast + Termux safe)
# ------------------------------------------------------------
cat > "$BE/workspace_index.py" <<'PY'
import os, json, time
from pathlib import Path

INDEX_FILE = Path(__file__).resolve().parent.parent / "runtime" / "index.json"

SKIP_DIRS = {
    ".git", ".venv", "node_modules", "__pycache__", "dist", "build",
    ".cache", ".pytest_cache", ".mypy_cache", ".idea", ".vscode"
}

TEXT_EXT = {
    ".py",".js",".ts",".tsx",".json",".md",".txt",".sh",".yaml",".yml",
    ".toml",".env",".html",".css",".sql"
}

def _should_skip_dir(name: str) -> bool:
    return name in SKIP_DIRS

def index_workspace(root: str, max_files: int = 3000):
    root = str(Path(root).resolve())
    files = []
    t0 = time.time()

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not _should_skip_dir(d)]

        for fn in filenames:
            p = Path(dirpath) / fn
            rel = str(p.relative_to(root))

            try:
                st = p.stat()
            except Exception:
                continue

            ext = p.suffix.lower()
            files.append({
                "path": rel,
                "size": int(st.st_size),
                "mtime": int(st.st_mtime),
                "ext": ext,
                "is_text": ext in TEXT_EXT
            })

            if len(files) >= max_files:
                break
        if len(files) >= max_files:
            break

    data = {
        "ok": True,
        "root": root,
        "indexed_at": int(time.time()),
        "count": len(files),
        "files": files,
        "seconds": round(time.time() - t0, 2),
    }

    INDEX_FILE.parent.mkdir(parents=True, exist_ok=True)
    INDEX_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return data

def load_index():
    if INDEX_FILE.exists():
        try:
            return json.loads(INDEX_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {"ok": False, "count": 0, "files": []}
    return {"ok": False, "count": 0, "files": []}

def search_index(query: str, limit: int = 30):
    idx = load_index()
    q = (query or "").strip().lower()
    if not q:
        return {"ok": True, "query": query, "results": []}

    results = []
    for f in idx.get("files", []):
        path = f.get("path","")
        if q in path.lower():
            results.append({"path": path, "type": "path"})
            if len(results) >= limit:
                break
    return {"ok": True, "query": query, "results": results, "count": len(results)}

def read_file(root: str, rel_path: str, max_chars: int = 8000):
    p = Path(root) / rel_path
    try:
        txt = p.read_text(encoding="utf-8", errors="ignore")
        return {"ok": True, "path": rel_path, "content": txt[:max_chars]}
    except Exception as e:
        return {"ok": False, "error": str(e), "path": rel_path}
PY
echo "✅ Wrote workspace_index.py"

# ------------------------------------------------------------
# 4) Provider config store (editable from dashboard UI)
# ------------------------------------------------------------
cat > "$BE/provider_store.py" <<'PY'
import json
from pathlib import Path

PROVIDERS_FILE = Path(__file__).resolve().parent.parent / "runtime" / "providers.json"

DEFAULTS = {
    "AI_PROVIDER": "auto",
    "OLLAMA_BASE_URL": "http://127.0.0.1:11434",
    "OLLAMA_MODEL": "llama3.2:3b",

    "OPENAI_API_KEY": "",
    "OPENAI_BASE_URL": "https://api.openai.com/v1",

    "DEEPSEEK_API_KEY": "",
    "DEEPSEEK_BASE_URL": "https://api.deepseek.com/v1",

    "GEMINI_API_KEY": "",
}

def load():
    if PROVIDERS_FILE.exists():
        try:
            data = json.loads(PROVIDERS_FILE.read_text(encoding="utf-8"))
            out = DEFAULTS.copy()
            out.update(data or {})
            return out
        except Exception:
            return DEFAULTS.copy()
    return DEFAULTS.copy()

def save(new_data: dict):
    out = load()
    out.update(new_data or {})
    PROVIDERS_FILE.parent.mkdir(parents=True, exist_ok=True)
    PROVIDERS_FILE.write_text(json.dumps(out, indent=2), encoding="utf-8")
    return out
PY
echo "✅ Wrote provider_store.py"

# ------------------------------------------------------------
# 5) AI Providers: AUTO chain + self-healing fallback
# ------------------------------------------------------------
cat > "$BE/ai_providers.py" <<'PY'
import os, json, time
import requests
from .provider_store import load as load_provider_store

def _timeout():
    return float(os.getenv("AI_TIMEOUT", "12"))

def _sys_prompt(workspace_hint: str):
    return (
        "You are FlashTM8 ⚡, a workspace-aware AI assistant.\n"
        "You help the user understand and develop the repo safely.\n"
        "Use short answers + include actionable commands.\n\n"
        f"WORKSPACE CONTEXT:\n{workspace_hint}\n"
    )

def _ollama_chat(prompt: str, cfg: dict):
    base = cfg.get("OLLAMA_BASE_URL") or os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    model = cfg.get("OLLAMA_MODEL") or os.getenv("OLLAMA_MODEL", "llama3.2:3b")
    url = base.rstrip("/") + "/api/generate"

    r = requests.post(url, json={
        "model": model,
        "prompt": prompt,
        "stream": False
    }, timeout=_timeout())
    r.raise_for_status()
    data = r.json()
    text = data.get("response") or ""
    return text.strip()

def _openai_like(prompt: str, api_key: str, base_url: str, model: str):
    url = base_url.rstrip("/") + "/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are FlashTM8 ⚡. Answer with repo-aware actions."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
    }
    r = requests.post(url, headers=headers, json=payload, timeout=_timeout())
    if r.status_code == 429:
        raise RuntimeError("rate_limit_or_quota")
    r.raise_for_status()
    j = r.json()
    return j["choices"][0]["message"]["content"].strip()

def _gemini(prompt: str, api_key: str):
    # Minimal Gemini REST (works if key valid)
    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    params = {"key": api_key}
    payload = {"contents": [{"parts": [{"text": prompt}]}]}
    r = requests.post(url, params=params, json=payload, timeout=_timeout())
    if r.status_code == 429:
        raise RuntimeError("rate_limit_or_quota")
    r.raise_for_status()
    j = r.json()
    cand = (j.get("candidates") or [{}])[0]
    parts = (((cand.get("content") or {}).get("parts")) or [{}])
    return (parts[0].get("text") or "").strip()

def generate_reply(user_message: str, workspace_hint: str = ""):
    """
    Always returns JSON dict:
      { ok: bool, provider: str, reply: str }
    """
    cfg = load_provider_store()

    provider = (os.getenv("AI_PROVIDER") or cfg.get("AI_PROVIDER") or "auto").lower().strip()
    prompt = _sys_prompt(workspace_hint) + "\nUSER:\n" + (user_message or "")

    chain = []
    if provider == "auto":
        chain = ["ollama", "deepseek", "openai", "gemini", "fallback"]
    else:
        chain = [provider, "fallback"]

    last_err = None

    for p in chain:
        try:
            if p == "ollama":
                text = _ollama_chat(prompt, cfg)
                if text:
                    return {"ok": True, "provider": "ollama", "reply": text}

            if p == "deepseek":
                key = cfg.get("DEEPSEEK_API_KEY") or os.getenv("DEEPSEEK_API_KEY", "")
                base = cfg.get("DEEPSEEK_BASE_URL") or "https://api.deepseek.com/v1"
                if key:
                    text = _openai_like(prompt, key, base, "deepseek-chat")
                    return {"ok": True, "provider": "deepseek", "reply": text}

            if p == "openai":
                key = cfg.get("OPENAI_API_KEY") or os.getenv("OPENAI_API_KEY", "")
                base = cfg.get("OPENAI_BASE_URL") or "https://api.openai.com/v1"
                if key:
                    text = _openai_like(prompt, key, base, "gpt-4o-mini")
                    return {"ok": True, "provider": "openai", "reply": text}

            if p == "gemini":
                key = cfg.get("GEMINI_API_KEY") or os.getenv("GEMINI_API_KEY", "")
                if key:
                    text = _gemini(prompt, key)
                    if text:
                        return {"ok": True, "provider": "gemini", "reply": text}

            if p == "fallback":
                # offline + safe fallback
                return {
                    "ok": True,
                    "provider": "fallback",
                    "reply": (
                        "FlashTM8 is running ✅\n"
                        "AI provider not reachable now, but workspace tools + indexing still work.\n\n"
                        "Try:\n"
                        "- Click 'Index Workspace'\n"
                        "- Search: 'run.sh', 'bot token', 'port'\n"
                        "- Ask: 'How do I run the bot?'"
                    )
                }

        except Exception as e:
            last_err = str(e)

    return {"ok": False, "provider": "none", "reply": f"Provider chain failed: {last_err}"}
PY
echo "✅ Wrote ai_providers.py"

# ------------------------------------------------------------
# 6) Flask backend app (clean routes, no broken patches)
# ------------------------------------------------------------
cat > "$BE/app.py" <<'PY'
import os
from flask import Flask, request, jsonify, render_template
from .ai_providers import generate_reply
from .workspace_index import index_workspace, load_index, search_index, read_file
from .provider_store import load as load_cfg, save as save_cfg

def create_app():
    app = Flask(__name__, template_folder="templates", static_folder="static")

    @app.get("/")
    def home():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        cfg = load_cfg()
        idx = load_index()
        return jsonify({
            "ok": True,
            "provider_mode": (os.getenv("AI_PROVIDER") or cfg.get("AI_PROVIDER") or "auto"),
            "workspace_root": os.getenv("WORKSPACE_ROOT", ""),
            "indexed_files": int(idx.get("count", 0)),
        })

    @app.post("/api/index")
    def do_index():
        root = os.getenv("WORKSPACE_ROOT") or request.json.get("root") if request.is_json else None
        if not root:
            root = os.getcwd()
        data = index_workspace(root)
        return jsonify(data)

    @app.get("/api/index")
    def get_index():
        return jsonify(load_index())

    @app.get("/api/search")
    def do_search():
        q = request.args.get("q", "")
        return jsonify(search_index(q))

    @app.get("/api/file")
    def api_file():
        root = os.getenv("WORKSPACE_ROOT") or os.getcwd()
        path = request.args.get("path", "")
        return jsonify(read_file(root, path))

    @app.get("/api/providers")
    def get_providers():
        cfg = load_cfg()
        safe = dict(cfg)
        # never leak full keys in UI
        for k in list(safe.keys()):
            if "KEY" in k or "TOKEN" in k or "PASS" in k:
                v = safe.get(k, "")
                safe[k] = (v[:6] + "..." + v[-4:]) if v else ""
        return jsonify({"ok": True, "providers": safe})

    @app.post("/api/providers")
    def set_providers():
        if not request.is_json:
            return jsonify({"ok": False, "error": "JSON required"}), 400
        new_cfg = save_cfg(request.json)
        return jsonify({"ok": True, "saved": True, "keys": list(new_cfg.keys())})

    @app.post("/api/chat")
    def chat():
        payload = request.get_json(silent=True) or {}
        msg = payload.get("message", "") or ""
        idx = load_index()
        hint = f"Indexed files: {idx.get('count',0)}"

        res = generate_reply(msg, workspace_hint=hint)
        return jsonify({
            "ok": bool(res.get("ok")),
            "provider": res.get("provider"),
            "reply": res.get("reply", "")
        })

    return app

if __name__ == "__main__":
    app = create_app()
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "5000"))
    app.run(host=host, port=port, debug=False)
PY
echo "✅ Wrote backend/app.py"

# ------------------------------------------------------------
# 7) Dashboard UI (HTML + JS)
# ------------------------------------------------------------
cat > "$BE/templates/index.html" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>FlashTM8 ⚡ AI Sovereign Console</title>
  <link rel="stylesheet" href="/static/style.css" />
</head>
<body>
  <div class="wrap">
    <div class="top">
      <div class="brand">
        <div class="logo">⚡</div>
        <div>
          <div class="title">FlashTM8</div>
          <div class="subtitle">AI Sovereign Console • Workspace-Aware Assistant</div>
        </div>
      </div>

      <div class="status">
        <div id="healthBadge" class="badge">Loading…</div>
        <div class="pill">Tools</div>
      </div>
    </div>

    <div class="grid">
      <div class="card">
        <h3>Health</h3>
        <div class="muted" id="healthInfo">Checking…</div>
        <div class="row">
          <button id="btnHealth">Refresh</button>
        </div>
      </div>

      <div class="card">
        <h3>Index Workspace</h3>
        <div class="muted" id="indexInfo">Not indexed yet.</div>
        <div class="row">
          <button id="btnIndex">Index Now</button>
          <input id="searchBox" placeholder="Search: run.sh, bot token, port..." />
          <button id="btnSearch">Search</button>
        </div>
        <div class="results" id="searchResults"></div>
      </div>

      <div class="card">
        <h3>Providers</h3>
        <div class="muted">Set keys here. FlashTM8 uses auto chain (ollama → deepseek → openai → gemini → fallback).</div>

        <div class="form">
          <label>AI_PROVIDER</label>
          <input id="AI_PROVIDER" placeholder="auto / ollama / openai / deepseek / gemini" />

          <label>OLLAMA_BASE_URL</label>
          <input id="OLLAMA_BASE_URL" placeholder="http://127.0.0.1:11434" />

          <label>OLLAMA_MODEL</label>
          <input id="OLLAMA_MODEL" placeholder="llama3.2:3b" />

          <label>OPENAI_API_KEY</label>
          <input id="OPENAI_API_KEY" placeholder="sk-..." />

          <label>DEEPSEEK_API_KEY</label>
          <input id="DEEPSEEK_API_KEY" placeholder="sk-..." />

          <label>GEMINI_API_KEY</label>
          <input id="GEMINI_API_KEY" placeholder="AIza..." />

          <div class="row">
            <button id="btnLoadProviders">Load</button>
            <button id="btnSaveProviders">Save</button>
          </div>
          <div class="muted" id="provStatus"></div>
        </div>
      </div>

      <div class="card chat">
        <h3>Chat</h3>
        <div class="muted">Ask about files, bugs, features, next steps.</div>
        <div class="chatbox" id="chatbox"></div>

        <div class="row">
          <input id="chatInput" placeholder="Type: Explain the repo structure / How do I run the bot?" />
          <button id="btnSend">Send</button>
        </div>

        <div class="muted small" id="providerUsed"></div>
      </div>
    </div>

    <div class="footer muted">
      FlashTM8 • Built for 8x8org • Self-healing • Workspace-aware
    </div>
  </div>

  <script src="/static/app.js"></script>
</body>
</html>
HTML

cat > "$BE/static/style.css" <<'CSS'
:root { --bg:#0b0f17; --card:#101828; --txt:#e8eefc; --muted:#9fb0d0; --accent:#7c3aed; --ok:#22c55e; --bad:#ef4444; }
*{box-sizing:border-box;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Arial;}
body{margin:0;background:var(--bg);color:var(--txt);}
.wrap{max-width:1200px;margin:0 auto;padding:22px;}
.top{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px;}
.brand{display:flex;gap:12px;align-items:center;}
.logo{width:44px;height:44px;border-radius:14px;background:var(--accent);display:flex;align-items:center;justify-content:center;font-size:20px;}
.title{font-weight:800;font-size:20px;}
.subtitle{color:var(--muted);font-size:12px;}
.status{display:flex;gap:10px;align-items:center;}
.badge{padding:8px 10px;border-radius:12px;background:#1f2937;color:var(--muted);font-size:12px;}
.pill{padding:8px 10px;border-radius:12px;background:#111827;color:var(--muted);font-size:12px;border:1px solid #1f2a44;}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;}
.card{background:var(--card);border:1px solid #1f2a44;border-radius:16px;padding:14px;}
.card h3{margin:0 0 8px 0;}
.muted{color:var(--muted);font-size:12px;line-height:1.4}
.row{display:flex;gap:8px;align-items:center;margin-top:10px;}
input{flex:1;background:#0b1220;border:1px solid #1f2a44;color:var(--txt);padding:10px;border-radius:12px;outline:none;}
button{background:var(--accent);border:0;color:white;padding:10px 12px;border-radius:12px;font-weight:700;cursor:pointer;}
.results{margin-top:10px;display:flex;flex-direction:column;gap:6px;max-height:180px;overflow:auto;}
.resultItem{padding:8px;border:1px solid #1f2a44;border-radius:12px;background:#0b1220;font-size:12px;}
.form label{display:block;margin-top:10px;color:var(--muted);font-size:12px;}
.chat{grid-column:1 / -1;}
.chatbox{margin-top:10px;background:#0b1220;border:1px solid #1f2a44;border-radius:16px;padding:12px;height:260px;overflow:auto;}
.msg{margin:0 0 10px 0;font-size:13px;white-space:pre-wrap;}
.me{color:#dbeafe;}
.ai{color:#bbf7d0;}
.small{font-size:11px}
.footer{margin-top:14px;text-align:center;}
CSS

cat > "$BE/static/app.js" <<'JS'
const $ = (id)=>document.getElementById(id);

function addMsg(who, text){
  const div = document.createElement("div");
  div.className = "msg " + (who==="me" ? "me":"ai");
  div.textContent = (who==="me" ? "You: " : "FlashTM8: ") + text;
  $("chatbox").appendChild(div);
  $("chatbox").scrollTop = $("chatbox").scrollHeight;
}

async function health(){
  const r = await fetch("/api/health");
  const j = await r.json();
  $("healthInfo").textContent = JSON.stringify(j, null, 2);
  $("healthBadge").textContent = j.ok ? `✅ Online • Provider: ${j.provider_mode}` : "❌ Offline";
  $("healthBadge").style.color = j.ok ? "#bbf7d0" : "#fecaca";
}

async function indexNow(){
  $("indexInfo").textContent = "Indexing…";
  const r = await fetch("/api/index", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({})});
  const j = await r.json();
  $("indexInfo").textContent = `✅ Indexed ${j.count} files in ${j.seconds}s`;
}

async function search(){
  const q = $("searchBox").value.trim();
  $("searchResults").innerHTML = "";
  if(!q) return;
  const r = await fetch("/api/search?q="+encodeURIComponent(q));
  const j = await r.json();
  (j.results||[]).forEach(it=>{
    const d = document.createElement("div");
    d.className = "resultItem";
    d.textContent = it.path;
    $("searchResults").appendChild(d);
  });
}

async function loadProviders(){
  const r = await fetch("/api/providers");
  const j = await r.json();
  const p = j.providers || {};
  ["AI_PROVIDER","OLLAMA_BASE_URL","OLLAMA_MODEL","OPENAI_API_KEY","DEEPSEEK_API_KEY","GEMINI_API_KEY"].forEach(k=>{
    if($(k)) $(k).value = p[k] || "";
  });
  $("provStatus").textContent = "✅ Loaded providers";
}

async function saveProviders(){
  const payload = {};
  ["AI_PROVIDER","OLLAMA_BASE_URL","OLLAMA_MODEL","OPENAI_API_KEY","DEEPSEEK_API_KEY","GEMINI_API_KEY"].forEach(k=>{
    payload[k] = ($(k)?.value||"").trim();
  });
  const r = await fetch("/api/providers", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify(payload)});
  const j = await r.json();
  $("provStatus").textContent = j.ok ? "✅ Saved providers" : "❌ Save failed";
}

async function chat(){
  const msg = $("chatInput").value.trim();
  if(!msg) return;
  $("chatInput").value = "";
  addMsg("me", msg);

  const r = await fetch("/api/chat", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({message:msg})});
  const j = await r.json();
  addMsg("ai", j.reply || "No reply");
  $("providerUsed").textContent = "Provider used: " + (j.provider || "unknown");
}

$("btnHealth").onclick = health;
$("btnIndex").onclick = indexNow;
$("btnSearch").onclick = search;
$("btnLoadProviders").onclick = loadProviders;
$("btnSaveProviders").onclick = saveProviders;
$("btnSend").onclick = chat;
$("chatInput").addEventListener("keydown",(e)=>{ if(e.key==="Enter") chat(); });

health();
JS

echo "✅ Wrote dashboard UI"

# ------------------------------------------------------------
# 8) Start scripts (Termux-safe: always run with bash)
# ------------------------------------------------------------
cat > "$REPO/start_flashtm8.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
APP="$REPO/apps/flashtm8"
BE="$APP/backend"

# load env safely
if [ -f "$APP/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$APP/.env"
  set +a
fi

export WORKSPACE_ROOT="${WORKSPACE_ROOT:-$REPO}"
export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-5000}"

echo "==============================================="
echo "⚡ FlashTM8 AI Dashboard"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "   Workspace: $WORKSPACE_ROOT"
echo "   URL: http://127.0.0.1:$PORT"
echo "==============================================="

cd "$APP"
python -m backend.app
SH

cat > "$APP/run_flashtm8.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
python -m backend.app
SH

chmod +x "$REPO/start_flashtm8.sh" "$APP/run_flashtm8.sh" 2>/dev/null || true

echo ""
echo "✅ FULL RESET DONE!"
echo ""
echo "Run:"
echo "  cd $REPO"
echo "  PORT=5000 bash start_flashtm8.sh"
echo ""
echo "Open in browser:"
echo "  http://127.0.0.1:5000"
echo ""
