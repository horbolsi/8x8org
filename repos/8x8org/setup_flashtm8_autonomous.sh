#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
RUNTIME="$APP/runtime"
ENVFILE="$APP/.env"
START="$REPO/start_flashtm8.sh"
RUNNER="$APP/run_flashtm8.sh"
SUPERVISOR="$REPO/run_flashtm8_supervisor.sh"

mkdir -p "$BACK" "$RUNTIME"

echo "✅ FlashTM8 Autonomous Setup"
echo "   Repo: $REPO"
echo "   App : $APP"
echo ""

# -----------------------------
# 0) Termux-safe python deps fix
# -----------------------------
echo "✅ Fixing requests/urllib3 for Termux (if needed)..."
python -m pip install --upgrade --force-reinstall \
  "requests>=2.32.3" "urllib3>=2.2.0" six >/dev/null 2>&1 || true

# -----------------------------
# 1) Create/merge FlashTM8 .env safely
#    (NO secret printing)
# -----------------------------
echo "✅ Writing FlashTM8 .env (safe merge)..."

python - <<'PY'
from pathlib import Path
import os

env_path = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/.env")
existing = {}
if env_path.exists():
    for ln in env_path.read_text(errors="ignore").splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("#") or "=" not in ln:
            continue
        k,v = ln.split("=",1)
        existing[k.strip()] = v.strip().strip('"').strip("'")

# Pull from current shell env if available (your secrets are likely exported already)
def pick(key, default=""):
    return os.environ.get(key) or existing.get(key) or default

# Core settings
final = {}
final["WORKSPACE_ROOT"] = pick("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")
final["HOST"] = pick("HOST", "0.0.0.0")
final["PORT"] = pick("PORT", "5000")

# Provider chain: auto-heal tries these in order
final["AI_PROVIDER"] = pick("AI_PROVIDER", "auto")
final["PROVIDER_CHAIN"] = pick("PROVIDER_CHAIN", "ollama,openai,gemini,deepseek,fallback")

# AI keys (stored if present in env; if not present, stays empty)
final["OPENAI_API_KEY"] = pick("OPENAI_API_KEY", "")
final["GEMINI_API_KEY"] = pick("GEMINI_API_KEY", "")
final["DEEPSEEK_API_KEY"] = pick("DEEPSEEK_API_KEY", "")
final["OLLAMA_BASE_URL"] = pick("OLLAMA_BASE_URL", "http://127.0.0.1:11434")

# Your bots / admin secrets (if already exported)
final["TELEGRAM_BOT_TOKEN"] = pick("TELEGRAM_BOT_TOKEN", "")
final["OWNER_ID"] = pick("OWNER_ID", "")

# Optional “dangerous” ops: OFF by default; you can enable later
final["ENABLE_EXEC"] = pick("ENABLE_EXEC", "0")
final["ENABLE_WRITE"] = pick("ENABLE_WRITE", "0")

# Auth token for admin actions (you can set it yourself)
final["ADMIN_TOKEN"] = pick("ADMIN_TOKEN", "changeme-admin-token")

# Helper safe writer
def q(v: str) -> str:
    v = (v or "").strip()
    # always write quoted (prevents Termux "No command ..." issues)
    v = v.replace('"', '\\"')
    return f"\"{v}\""

out = []
out.append("# FlashTM8 runtime configuration")
for k in sorted(final.keys()):
    out.append(f"{k}={q(final[k])}")

env_path.write_text("\n".join(out).strip() + "\n")
print("✅ .env saved:", env_path)
PY

# -----------------------------
# 2) workspace_index.py (indexes EVERYTHING useful)
# -----------------------------
echo "✅ Writing workspace_index.py ..."
cat <<'PY' > "$BACK/workspace_index.py"
import os
import sqlite3
import hashlib

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "runtime", "index.db")

EXCLUDE_NAMES = {
    ".git",
    ".venv",
    "__pycache__",
    "node_modules",
    "dist",
    "build",
    ".cache",
}

EXTS = {
    ".py",".sh",".md",".txt",".json",".toml",".yaml",".yml",
    ".js",".ts",".tsx",".css",".html",".env",".replit",".lock",".sql"
}

MAX_BYTES = 900_000

def _conn():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    c = sqlite3.connect(DB_PATH)
    c.execute("""
    CREATE TABLE IF NOT EXISTS files (
        path TEXT PRIMARY KEY,
        size INTEGER,
        mtime REAL,
        sha TEXT,
        text TEXT
    )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)")
    return c

def _hash(txt: str) -> str:
    return hashlib.sha256(txt.encode("utf-8", errors="ignore")).hexdigest()[:16]

def index_workspace(root: str) -> dict:
    root = os.path.abspath(root)
    c = _conn()
    files = 0

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_NAMES]

        for fn in filenames:
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root).replace("\\", "/")
            ext = os.path.splitext(fn)[1].lower()

            if ext and ext not in EXTS:
                continue

            try:
                st = os.stat(p)
                if st.st_size > MAX_BYTES:
                    continue

                try:
                    with open(p, "r", encoding="utf-8", errors="ignore") as f:
                        txt = f.read()
                except Exception:
                    txt = ""

                sha = _hash(txt[:60000])
                c.execute(
                    "INSERT OR REPLACE INTO files(path,size,mtime,sha,text) VALUES(?,?,?,?,?)",
                    (rel, st.st_size, st.st_mtime, sha, txt[:60000])
                )
                files += 1
            except Exception:
                continue

    c.commit()
    c.close()
    return {"ok": True, "files": files, "db": DB_PATH}

def search(query: str, limit: int = 25):
    q = (query or "").strip().lower()
    if not q:
        return []
    c = _conn()
    cur = c.execute("SELECT path, text FROM files")
    hits = []
    for path, text in cur.fetchall():
        t = (text or "").lower()
        if q in path.lower() or q in t:
            idx = t.find(q)
            snippet = ""
            if idx >= 0:
                snippet = (text or "")[max(0, idx-90): idx+260].replace("\n"," ")
            hits.append({"path": path, "snippet": snippet[:380]})
            if len(hits) >= limit:
                break
    c.close()
    return hits
PY

# -----------------------------
# 3) tools.py (read/search/write/exec)
# -----------------------------
echo "✅ Writing tools.py ..."
cat <<'PY' > "$BACK/tools.py"
import os, subprocess, shlex, json
from pathlib import Path
from . import workspace_index

def _root():
    return os.environ.get("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")

def index():
    return workspace_index.index_workspace(_root())

def search(q: str, limit: int = 25):
    return {"ok": True, "query": q, "results": workspace_index.search(q, limit=limit)}

def read_file(path: str, max_chars: int = 20000):
    p = Path(_root()) / path
    if not p.exists():
        return {"ok": False, "error": "file_not_found", "path": str(path)}
    txt = p.read_text(errors="ignore")
    return {"ok": True, "path": str(path), "text": txt[:max_chars]}

def write_file(path: str, content: str):
    if os.environ.get("ENABLE_WRITE","0") != "1":
        return {"ok": False, "error": "write_disabled"}
    p = Path(_root()) / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return {"ok": True, "wrote": str(path), "bytes": len(content)}

def exec_cmd(cmd: str, timeout: int = 25):
    if os.environ.get("ENABLE_EXEC","0") != "1":
        return {"ok": False, "error": "exec_disabled"}

    # Very basic safety fence: block destructive patterns
    blocked = ["rm -rf", "mkfs", ":(){", "dd if=", "shutdown", "reboot"]
    low = cmd.lower()
    for b in blocked:
        if b in low:
            return {"ok": False, "error": "blocked_command", "blocked": b}

    try:
        out = subprocess.check_output(
            cmd,
            shell=True,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            cwd=_root()
        ).decode("utf-8", errors="ignore")
        return {"ok": True, "cmd": cmd, "output": out[-8000:]}
    except subprocess.CalledProcessError as e:
        return {"ok": False, "cmd": cmd, "output": (e.output or b"").decode("utf-8", errors="ignore")[-8000:]}
    except Exception as e:
        return {"ok": False, "cmd": cmd, "error": str(e)}
PY

# -----------------------------
# 4) ai_providers.py (AUTO chain + self-heal)
# -----------------------------
echo "✅ Writing ai_providers.py ..."
cat <<'PY' > "$BACK/ai_providers.py"
import os, json, time
import requests
from . import tools

def _chain():
    raw = os.environ.get("PROVIDER_CHAIN","ollama,openai,gemini,deepseek,fallback")
    return [x.strip() for x in raw.split(",") if x.strip()]

def _ollama(prompt: str):
    base = os.environ.get("OLLAMA_BASE_URL","http://127.0.0.1:11434")
    try:
        r = requests.post(f"{base}/api/generate", json={"model":"llama3.1", "prompt":prompt, "stream":False}, timeout=20)
        r.raise_for_status()
        data = r.json()
        return {"ok": True, "provider": "ollama", "reply": data.get("response","").strip()}
    except Exception as e:
        return {"ok": False, "provider": "ollama", "error": str(e)}

def _openai(prompt: str):
    key = os.environ.get("OPENAI_API_KEY","")
    if not key:
        return {"ok": False, "provider": "openai", "error": "missing_key"}
    try:
        # minimal OpenAI Chat Completions compatible call
        r = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}", "Content-Type":"application/json"},
            json={
                "model":"gpt-4o-mini",
                "messages":[{"role":"system","content":"You are FlashTM8, a repo-aware autonomous dev assistant."},
                            {"role":"user","content":prompt}],
                "temperature":0.2
            },
            timeout=25
        )
        data = r.json()
        if r.status_code != 200:
            return {"ok": False, "provider": "openai", "error": f"{r.status_code}: {json.dumps(data)[:500]}"}
        reply = data["choices"][0]["message"]["content"]
        return {"ok": True, "provider": "openai", "reply": reply}
    except Exception as e:
        return {"ok": False, "provider": "openai", "error": str(e)}

def _gemini(prompt: str):
    key = os.environ.get("GEMINI_API_KEY","")
    if not key:
        return {"ok": False, "provider": "gemini", "error": "missing_key"}
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={key}"
        r = requests.post(url, json={
            "contents":[{"parts":[{"text":prompt}]}]
        }, timeout=25)
        data = r.json()
        if r.status_code != 200:
            return {"ok": False, "provider":"gemini", "error": f"{r.status_code}: {json.dumps(data)[:500]}"}
        reply = data["candidates"][0]["content"]["parts"][0]["text"]
        return {"ok": True, "provider":"gemini", "reply": reply}
    except Exception as e:
        return {"ok": False, "provider":"gemini", "error": str(e)}

def _deepseek(prompt: str):
    key = os.environ.get("DEEPSEEK_API_KEY","")
    if not key:
        return {"ok": False, "provider": "deepseek", "error": "missing_key"}
    try:
        r = requests.post(
            "https://api.deepseek.com/chat/completions",
            headers={"Authorization": f"Bearer {key}", "Content-Type":"application/json"},
            json={
                "model":"deepseek-chat",
                "messages":[{"role":"system","content":"You are FlashTM8, a repo-aware autonomous dev assistant."},
                            {"role":"user","content":prompt}],
                "temperature":0.2
            },
            timeout=25
        )
        data = r.json()
        if r.status_code != 200:
            return {"ok": False, "provider":"deepseek", "error": f"{r.status_code}: {json.dumps(data)[:500]}"}
        reply = data["choices"][0]["message"]["content"]
        return {"ok": True, "provider":"deepseek", "reply": reply}
    except Exception as e:
        return {"ok": False, "provider":"deepseek", "error": str(e)}

def _fallback(prompt: str):
    # Still useful even with no AI reachable
    # It uses indexing/search tools and gives actionable answers
    return {
        "ok": True,
        "provider": "fallback",
        "reply": "FlashTM8 is running ✅ AI provider not reachable now, but workspace tools + indexing still work.\n\nTry: click Index Workspace, then ask: 'Search run.sh' or 'Explain repo structure'."
    }

PROVIDERS = {
    "ollama": _ollama,
    "openai": _openai,
    "gemini": _gemini,
    "deepseek": _deepseek,
    "fallback": _fallback,
}

def chat(user_msg: str, context: str = "") -> dict:
    # Build prompt with workspace context summary
    prompt = f"""You are FlashTM8 ⚡ a workspace-aware dev assistant.

Workspace root: {os.environ.get("WORKSPACE_ROOT")}
Rules:
- If user asks about a file, use search() or read_file() mentally.
- Provide steps + exact commands.
- Prefer safe changes.

User message:
{user_msg}

Extra context:
{context}
"""
    for name in _chain():
        fn = PROVIDERS.get(name)
        if not fn:
            continue
        res = fn(prompt)
        if res.get("ok"):
            return {"ok": True, "provider": res.get("provider"), "reply": res.get("reply","")}
    return {"ok": False, "provider": "none", "reply": "No provider worked."}
PY

# -----------------------------
# 5) app.py (stable JSON, self-heal endpoints)
# -----------------------------
echo "✅ Writing backend/app.py ..."
cat <<'PY' > "$BACK/app.py"
import os
from flask import Flask, request, jsonify, render_template_string
from .ai_providers import chat as ai_chat
from . import tools

HTML = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>FlashTM8 ⚡</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <div class="topbar">
    <div class="brand">⚡ FlashTM8</div>
    <div class="sub">AI Sovereign Console • Workspace-Aware Assistant</div>
  </div>

  <div class="grid">
    <div class="card">
      <h3>Status</h3>
      <div id="health">Loading...</div>
      <button id="btnIndex">Index Workspace</button>
      <pre id="indexResult"></pre>
    </div>

    <div class="card">
      <h3>Tools</h3>
      <input id="q" placeholder="Search: server port, run.sh, bot token..."/>
      <button id="btnSearch">Search</button>
      <pre id="searchResult"></pre>
    </div>

    <div class="card wide">
      <h3>Chat</h3>
      <div id="chatlog" class="chatlog"></div>
      <div class="row">
        <input id="msg" placeholder="Ask about files, bugs, features, next steps..." />
        <button id="btnSend">Send</button>
      </div>
      <div class="provider" id="providerUsed"></div>
    </div>
  </div>

<script src="/static/app.js"></script>
</body>
</html>
"""

def create_app():
    app = Flask(__name__, static_folder="static", template_folder="templates")

    @app.get("/")
    def home():
        return render_template_string(HTML)

    @app.get("/api/health")
    def health():
        return jsonify({
            "ok": True,
            "provider_mode": os.environ.get("AI_PROVIDER","auto"),
            "chain": os.environ.get("PROVIDER_CHAIN",""),
            "workspace": os.environ.get("WORKSPACE_ROOT",""),
            "exec_enabled": os.environ.get("ENABLE_EXEC","0"),
            "write_enabled": os.environ.get("ENABLE_WRITE","0"),
        })

    @app.post("/api/index")
    def do_index():
        res = tools.index()
        return jsonify(res)

    @app.post("/api/search")
    def do_search():
        data = request.get_json(force=True) or {}
        q = data.get("q","")
        res = tools.search(q)
        return jsonify(res)

    @app.post("/api/chat")
    def do_chat():
        data = request.get_json(force=True) or {}
        msg = (data.get("msg") or "").strip()
        if not msg:
            return jsonify({"ok": False, "error": "empty_message"}), 400

        # Auto add small context from search if user asks "run" or "error"
        context = ""
        if any(k in msg.lower() for k in ["run.sh","start","error","traceback","port","bot"]):
            s = tools.search(msg, limit=6)
            context = str(s.get("results",[])[:6])

        res = ai_chat(msg, context=context)

        # Always return JSON stable
        return jsonify({
            "ok": bool(res.get("ok")),
            "provider": res.get("provider","unknown"),
            "reply": res.get("reply",""),
        })

    @app.post("/api/exec")
    def do_exec():
        token = request.headers.get("X-ADMIN-TOKEN","")
        if token != os.environ.get("ADMIN_TOKEN",""):
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        data = request.get_json(force=True) or {}
        cmd = data.get("cmd","")
        return jsonify(tools.exec_cmd(cmd))

    @app.post("/api/write")
    def do_write():
        token = request.headers.get("X-ADMIN-TOKEN","")
        if token != os.environ.get("ADMIN_TOKEN",""):
            return jsonify({"ok": False, "error": "unauthorized"}), 401
        data = request.get_json(force=True) or {}
        path = data.get("path","")
        content = data.get("content","")
        return jsonify(tools.write_file(path, content))

    return app

if __name__ == "__main__":
    app = create_app()
    port = int(os.environ.get("PORT","5000"))
    host = os.environ.get("HOST","0.0.0.0")
    app.run(host=host, port=port)
PY

# -----------------------------
# 6) Minimal UI JS + CSS
# -----------------------------
echo "✅ Writing frontend static files ..."
mkdir -p "$BACK/static"

cat <<'JS' > "$BACK/static/app.js"
async function postJSON(url, body) {
  const r = await fetch(url, {
    method: "POST",
    headers: {"Content-Type":"application/json"},
    body: JSON.stringify(body || {})
  });
  return await r.json();
}

async function refreshHealth() {
  const r = await fetch("/api/health");
  const j = await r.json();
  document.getElementById("health").innerText =
    `✅ Online • Provider mode: ${j.provider_mode}\nChain: ${j.chain}\nWorkspace: ${j.workspace}\nExec: ${j.exec_enabled} | Write: ${j.write_enabled}`;
}

function addChat(role, text) {
  const el = document.createElement("div");
  el.className = role === "user" ? "bubble user" : "bubble ai";
  el.innerText = text;
  document.getElementById("chatlog").appendChild(el);
  document.getElementById("chatlog").scrollTop = 999999;
}

document.getElementById("btnIndex").onclick = async () => {
  document.getElementById("indexResult").innerText = "Indexing...";
  const j = await postJSON("/api/index", {});
  document.getElementById("indexResult").innerText = JSON.stringify(j, null, 2);
  await refreshHealth();
};

document.getElementById("btnSearch").onclick = async () => {
  const q = document.getElementById("q").value;
  const j = await postJSON("/api/search", {q});
  document.getElementById("searchResult").innerText = JSON.stringify(j, null, 2);
};

document.getElementById("btnSend").onclick = async () => {
  const msg = document.getElementById("msg").value.trim();
  if (!msg) return;
  document.getElementById("msg").value = "";
  addChat("user", "You: " + msg);

  const j = await postJSON("/api/chat", {msg});
  document.getElementById("providerUsed").innerText = "Provider used: " + (j.provider || "unknown");
  addChat("ai", "FlashTM8: " + (j.reply || "Error"));
};

refreshHealth();
JS

cat <<'CSS' > "$BACK/static/style.css"
body { font-family: Arial, sans-serif; background:#0b0f14; color:#e8eef6; margin:0; }
.topbar { padding:14px 18px; border-bottom:1px solid #1f2937; background:#0f1620; }
.brand { font-size:20px; font-weight:700; }
.sub { font-size:12px; opacity:.8; }
.grid { display:grid; grid-template-columns: 1fr 1fr; gap:14px; padding:14px; }
.card { background:#0f1620; border:1px solid #1f2937; border-radius:12px; padding:12px; }
.card.wide { grid-column: 1 / span 2; }
button { background:#2563eb; border:none; color:white; padding:10px 12px; border-radius:10px; cursor:pointer; margin-top:10px; }
input { width:100%; padding:10px; background:#0b0f14; border:1px solid #1f2937; border-radius:10px; color:#e8eef6; margin-top:8px; }
pre { white-space:pre-wrap; font-size:12px; background:#0b0f14; padding:10px; border-radius:10px; border:1px solid #1f2937; margin-top:10px; }
.chatlog { height:270px; overflow:auto; background:#0b0f14; border:1px solid #1f2937; border-radius:10px; padding:10px; }
.bubble { padding:10px; border-radius:10px; margin-bottom:8px; font-size:13px; }
.bubble.user { background:#1f2937; }
.bubble.ai { background:#111827; }
.row { display:flex; gap:10px; margin-top:10px; }
.row input { flex:1; }
.provider { opacity:.8; font-size:12px; margin-top:8px; }
CSS

# -----------------------------
# 7) Runner scripts (bash-safe, permission-safe)
# -----------------------------
echo "✅ Writing runner scripts..."

cat <<'SH' > "$RUNNER"
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

set -a
[ -f ".env" ] && source ".env"
set +a

PORT="${PORT:-5000}"
HOST="${HOST:-0.0.0.0}"

echo "==============================================="
echo "⚡ FlashTM8 Autonomous Console"
echo "   Provider mode : ${AI_PROVIDER:-auto}"
echo "   Provider chain: ${PROVIDER_CHAIN:-}"
echo "   Workspace     : ${WORKSPACE_ROOT:-}"
echo "   URL           : http://127.0.0.1:${PORT}"
echo "==============================================="

python -m backend.app
SH

cat <<'SH' > "$START"
#!/usr/bin/env bash
set -euo pipefail
cd "/home/runner/workspace/repos/8x8org"

chmod +x "apps/flashtm8/run_flashtm8.sh" 2>/dev/null || true

# ensure env loaded
set -a
source "apps/flashtm8/.env"
set +a

# if user exports PORT, respect it; else default to env
export PORT="${PORT:-5000}"

bash "apps/flashtm8/run_flashtm8.sh"
SH

cat <<'SH' > "$SUPERVISOR"
#!/usr/bin/env bash
set -euo pipefail
cd "/home/runner/workspace/repos/8x8org"

# Self-healing loop: restart if crash
while true; do
  echo "⚡ Supervisor: starting FlashTM8..."
  bash start_flashtm8.sh || true
  echo "⚠️ FlashTM8 stopped/crashed. Restarting in 2s..."
  sleep 2
done
SH

chmod +x "$RUNNER" "$START" "$SUPERVISOR"

# -----------------------------
# 8) Quick local index test
# -----------------------------
echo "✅ Quick index test..."
set -a
source "$ENVFILE"
set +a

python - <<'PY'
import os
from apps.flashtm8.backend import workspace_index
root = os.environ.get("WORKSPACE_ROOT")
res = workspace_index.index_workspace(root)
print("✅ Indexed files:", res.get("files"))
PY

echo ""
echo "✅ DONE ✅"
echo ""
echo "START IT NOW:"
echo "  cd $REPO"
echo "  PORT=5000 bash start_flashtm8.sh"
echo ""
echo "OR run self-healing supervisor:"
echo "  bash run_flashtm8_supervisor.sh"
echo ""
echo "Open in browser:"
echo "  http://127.0.0.1:5000"
echo ""
