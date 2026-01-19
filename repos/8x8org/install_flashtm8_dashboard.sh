#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/runner/workspace/repos/8x8org"
APP_DIR="$ROOT/apps/flashtm8"
PY_DIR="$APP_DIR/backend"
TPL_DIR="$PY_DIR/templates"
STATIC_DIR="$PY_DIR/static"

echo "==============================================="
echo "✅ Installing FlashTM8 AI Dashboard into:"
echo "   $APP_DIR"
echo "==============================================="

mkdir -p "$TPL_DIR" "$STATIC_DIR" "$APP_DIR/runtime"

# ---------------------------
# 1) requirements (safe)
# ---------------------------
# We will not upgrade pip (Termux blocks it).
# We only ensure Flask + requests exist.
python - << 'PY'
import sys
need = ["flask","requests"]
missing=[]
for m in need:
    try:
        __import__(m)
    except Exception:
        missing.append(m)
if missing:
    print("Missing:", missing)
    sys.exit(1)
print("OK: Flask + requests already installed.")
PY

# ---------------------------
# 2) .env.example
# ---------------------------
cat > "$APP_DIR/.env.example" << 'ENV'
# ============================
# FlashTM8 AI Dashboard Config
# ============================

# --- Server ---
PORT=5050
HOST=0.0.0.0

# --- Workspace ---
# This is where FlashTM8 will index and read your repo.
WORKSPACE_ROOT=/home/runner/workspace/repos/8x8org

# --- Security ---
# Admin token is required for dangerous endpoints (write/exec).
# Keep it secret.
ADMIN_TOKEN=CHANGE_ME_SUPER_SECRET

# Tool execution is OFF by default.
ENABLE_EXEC=0
ENABLE_WRITE=0

# --- AI Providers ---
# Choose provider: "openai" or "ollama" (default tries ollama then openai)
AI_PROVIDER=ollama

# OpenAI
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4.1-mini

# Ollama (local LLM server)
# If you run ollama: it usually listens on http://127.0.0.1:11434
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.1:8b
ENV

# ---------------------------
# 3) Backend: ai_providers.py
# ---------------------------
cat > "$PY_DIR/ai_providers.py" << 'PY'
import os
import json
import requests

def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default)

def chat_with_openai(messages):
    """
    Minimal OpenAI chat call (REST).
    Requires OPENAI_API_KEY.
    """
    api_key = _env("OPENAI_API_KEY")
    model = _env("OPENAI_MODEL", "gpt-4.1-mini")
    if not api_key:
        return {"ok": False, "error": "OPENAI_API_KEY not set"}

    url = "https://api.openai.com/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model,
        "messages": messages,
        "temperature": 0.3,
    }
    r = requests.post(url, headers=headers, json=payload, timeout=60)
    if r.status_code != 200:
        return {"ok": False, "error": f"OpenAI error {r.status_code}: {r.text}"}

    data = r.json()
    text = data["choices"][0]["message"]["content"]
    return {"ok": True, "text": text, "provider": "openai", "model": model}

def chat_with_ollama(messages):
    """
    Local Ollama call.
    Requires ollama running + OLLAMA_BASE_URL + OLLAMA_MODEL.
    """
    base_url = _env("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
    model = _env("OLLAMA_MODEL", "llama3.1:8b")

    # Convert chat messages to a single prompt
    prompt = []
    for m in messages:
        role = m.get("role", "user")
        content = m.get("content", "")
        prompt.append(f"[{role.upper()}]\n{content}")
    prompt_text = "\n\n".join(prompt).strip()

    url = f"{base_url}/api/generate"
    payload = {"model": model, "prompt": prompt_text, "stream": False}

    try:
        r = requests.post(url, json=payload, timeout=60)
    except Exception as e:
        return {"ok": False, "error": f"Ollama request failed: {e}"}

    if r.status_code != 200:
        return {"ok": False, "error": f"Ollama error {r.status_code}: {r.text}"}

    data = r.json()
    text = data.get("response", "")
    return {"ok": True, "text": text, "provider": "ollama", "model": model}

def chat(messages):
    """
    Router:
    - If AI_PROVIDER=ollama -> try ollama
    - If AI_PROVIDER=openai -> try openai
    - Otherwise: try ollama then openai
    """
    provider = _env("AI_PROVIDER", "ollama").lower().strip()

    if provider == "openai":
        return chat_with_openai(messages)
    if provider == "ollama":
        return chat_with_ollama(messages)

    # fallback order
    res = chat_with_ollama(messages)
    if res.get("ok"):
        return res
    return chat_with_openai(messages)
PY

# ---------------------------
# 4) Backend: workspace_index.py
# ---------------------------
cat > "$PY_DIR/workspace_index.py" << 'PY'
import os
import re
import json
import time
import sqlite3
from pathlib import Path

DEFAULT_IGNORE = {
    ".git", ".venv", "node_modules", "__pycache__", ".pytest_cache",
    "dist", "build", ".cache", ".mypy_cache", ".next"
}

TEXT_EXTS = {
    ".py",".js",".ts",".tsx",".jsx",".html",".css",".md",".json",".yml",".yaml",
    ".sh",".txt",".toml",".env",".ini",".sql"
}

def safe_relpath(path: str, root: str) -> str:
    try:
        return str(Path(path).resolve().relative_to(Path(root).resolve()))
    except Exception:
        return path

def is_text_file(p: Path) -> bool:
    if p.suffix.lower() in TEXT_EXTS:
        return True
    # accept files without suffix but small size
    try:
        if p.suffix == "" and p.stat().st_size < 200_000:
            return True
    except Exception:
        pass
    return False

def load_text(p: Path, max_chars=250_000) -> str:
    try:
        data = p.read_text(errors="ignore")
        if len(data) > max_chars:
            return data[:max_chars] + "\n\n...[TRUNCATED]..."
        return data
    except Exception:
        return ""

def simple_tokens(s: str):
    # basic tokenization
    s = s.lower()
    return re.findall(r"[a-z0-9_./-]{2,}", s)

def ensure_db(db_path: str):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT UNIQUE,
        mtime REAL,
        size INTEGER,
        text TEXT
    )
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)")
    conn.commit()
    conn.close()

def index_workspace(root: str, db_path: str, max_files=3000):
    ensure_db(db_path)
    root_path = Path(root).resolve()
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    count = 0
    for p in root_path.rglob("*"):
        if count >= max_files:
            break
        if not p.is_file():
            continue

        parts = set(p.parts)
        if any(x in parts for x in DEFAULT_IGNORE):
            continue

        if not is_text_file(p):
            continue

        try:
            st = p.stat()
        except Exception:
            continue

        rel = safe_relpath(str(p), str(root_path))
        text = load_text(p)
        if not text.strip():
            continue

        cur.execute("""
            INSERT INTO files(path, mtime, size, text)
            VALUES(?,?,?,?)
            ON CONFLICT(path) DO UPDATE SET
                mtime=excluded.mtime,
                size=excluded.size,
                text=excluded.text
        """, (rel, st.st_mtime, st.st_size, text))
        count += 1

    conn.commit()
    conn.close()
    return {"ok": True, "indexed_files": count}

def search_workspace(db_path: str, query: str, limit=6):
    ensure_db(db_path)
    q_tokens = simple_tokens(query)
    if not q_tokens:
        return []

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT path, text FROM files")
    rows = cur.fetchall()
    conn.close()

    scored = []
    for path, text in rows:
        t = text.lower()
        score = 0
        for tok in q_tokens:
            # boost filename hits
            if tok in path.lower():
                score += 7
            score += t.count(tok) * 1
        if score > 0:
            scored.append((score, path, text))

    scored.sort(key=lambda x: x[0], reverse=True)
    top = scored[:limit]

    results = []
    for score, path, text in top:
        # extract best snippets around first hit
        snippet = best_snippet(text, q_tokens, max_len=1200)
        results.append({
            "path": path,
            "score": score,
            "snippet": snippet
        })
    return results

def best_snippet(text: str, tokens, max_len=1200):
    lower = text.lower()
    pos = None
    for tok in tokens:
        i = lower.find(tok)
        if i != -1:
            pos = i
            break

    if pos is None:
        return (text[:max_len] + " ...") if len(text) > max_len else text

    start = max(0, pos - 350)
    end = min(len(text), pos + (max_len - 350))
    chunk = text[start:end]
    if start > 0:
        chunk = "… " + chunk
    if end < len(text):
        chunk = chunk + " …"
    return chunk
PY

# ---------------------------
# 5) Backend: tools.py (safe operations)
# ---------------------------
cat > "$PY_DIR/tools.py" << 'PY'
import os
import subprocess
from pathlib import Path

def _env(name, default=""):
    return os.getenv(name, default)

def _workspace_root():
    return Path(_env("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")).resolve()

def _is_enabled(flag):
    return _env(flag, "0").strip() == "1"

ALLOWED_COMMANDS = [
    "ls", "pwd", "whoami",
    "git status", "git log --oneline -n 10",
    "python -V",
    "tree -L 3",
    "find . -maxdepth 3 -type f | head -n 60",
]

def run_safe_command(cmd: str):
    """
    Runs only allowlisted commands and only inside WORKSPACE_ROOT.
    Disabled unless ENABLE_EXEC=1
    """
    if not _is_enabled("ENABLE_EXEC"):
        return {"ok": False, "error": "ENABLE_EXEC is disabled"}

    cmd = cmd.strip()
    if cmd not in ALLOWED_COMMANDS:
        return {"ok": False, "error": "Command not allowlisted", "allowed": ALLOWED_COMMANDS}

    try:
        out = subprocess.check_output(
            cmd, shell=True, cwd=str(_workspace_root()),
            stderr=subprocess.STDOUT, timeout=30
        ).decode(errors="ignore")
        return {"ok": True, "output": out}
    except subprocess.CalledProcessError as e:
        return {"ok": False, "error": f"Command failed: {e}", "output": e.output.decode(errors='ignore')}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def write_file(rel_path: str, content: str):
    """
    Writes files ONLY inside WORKSPACE_ROOT.
    Disabled unless ENABLE_WRITE=1
    """
    if not _is_enabled("ENABLE_WRITE"):
        return {"ok": False, "error": "ENABLE_WRITE is disabled"}

    root = _workspace_root()
    target = (root / rel_path).resolve()

    if not str(target).startswith(str(root)):
        return {"ok": False, "error": "Path escape blocked"}

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8", errors="ignore")
    return {"ok": True, "written": str(target)}
PY

# ---------------------------
# 6) Backend: app.py (Flask)
# ---------------------------
cat > "$PY_DIR/app.py" << 'PY'
import os
import time
from flask import Flask, request, jsonify, render_template

from ai_providers import chat as ai_chat
from workspace_index import index_workspace, search_workspace
from tools import run_safe_command, write_file

def env(name, default=""):
    return os.getenv(name, default)

def require_admin(req):
    token = req.headers.get("X-Admin-Token", "")
    return token and token == env("ADMIN_TOKEN", "")

def create_app():
    app = Flask(__name__, template_folder="templates", static_folder="static")

    @app.get("/")
    def home():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        return jsonify({
            "ok": True,
            "name": "FlashTM8",
            "time": time.time(),
            "workspace_root": env("WORKSPACE_ROOT", ""),
            "ai_provider": env("AI_PROVIDER", "ollama")
        })

    @app.post("/api/index")
    def do_index():
        root = env("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")
        db_path = os.path.join(os.path.dirname(__file__), "..", "runtime", "index.db")
        res = index_workspace(root=root, db_path=db_path, max_files=4000)
        return jsonify(res)

    @app.post("/api/search")
    def do_search():
        body = request.get_json(force=True, silent=True) or {}
        q = (body.get("q") or "").strip()
        db_path = os.path.join(os.path.dirname(__file__), "..", "runtime", "index.db")
        results = search_workspace(db_path=db_path, query=q, limit=6)
        return jsonify({"ok": True, "results": results})

    @app.post("/api/chat")
    def do_chat():
        body = request.get_json(force=True, silent=True) or {}
        user_msg = (body.get("message") or "").strip()

        if not user_msg:
            return jsonify({"ok": False, "error": "Empty message"}), 400

        # Retrieve top workspace context
        db_path = os.path.join(os.path.dirname(__file__), "..", "runtime", "index.db")
        ctx = search_workspace(db_path=db_path, query=user_msg, limit=6)

        context_blob = "\n\n".join([
            f"FILE: {c['path']}\n---\n{c['snippet']}\n---"
            for c in ctx
        ]) if ctx else "No indexed context found. User should click 'Index Workspace'."

        system_prompt = f"""
You are FlashTM8 — the project's AI core assistant.

Your job:
- Help the user understand and develop the 8x8org workspace.
- Use only the provided workspace context snippets to answer questions about files.
- If you don't see enough evidence, ask the user to run Index and try again.
- Always give practical commands and next steps.

Workspace root: {env("WORKSPACE_ROOT","")}
"""

        messages = [
            {"role": "system", "content": system_prompt.strip()},
            {"role": "user", "content": f"USER QUESTION:\n{user_msg}\n\nWORKSPACE CONTEXT:\n{context_blob}".strip()},
        ]

        res = ai_chat(messages)
        return jsonify({
            "ok": bool(res.get("ok")),
            "reply": res.get("text", ""),
            "provider": res.get("provider"),
            "model": res.get("model"),
            "context_used": ctx,
            "error": res.get("error")
        })

    # --------- optional tools (admin only) ----------
    @app.post("/api/exec")
    def do_exec():
        if not require_admin(request):
            return jsonify({"ok": False, "error": "Admin token required"}), 401
        body = request.get_json(force=True, silent=True) or {}
        cmd = (body.get("cmd") or "").strip()
        res = run_safe_command(cmd)
        return jsonify(res)

    @app.post("/api/write")
    def do_write():
        if not require_admin(request):
            return jsonify({"ok": False, "error": "Admin token required"}), 401
        body = request.get_json(force=True, silent=True) or {}
        path = (body.get("path") or "").strip()
        content = body.get("content") or ""
        if not path:
            return jsonify({"ok": False, "error": "Missing path"}), 400
        res = write_file(path, content)
        return jsonify(res)

    return app

if __name__ == "__main__":
    app = create_app()
    host = env("HOST", "0.0.0.0")
    port = int(env("PORT", "5050") or "5050")
    app.run(host=host, port=port, debug=False)
PY

# ---------------------------
# 7) Frontend: index.html
# ---------------------------
cat > "$TPL_DIR/index.html" << 'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>FlashTM8 — AI Sovereign Console</title>
  <link rel="stylesheet" href="/static/style.css"/>
</head>
<body>
  <div class="wrap">
    <header class="top">
      <div class="brand">
        <div class="logo">⚡</div>
        <div>
          <div class="title">FlashTM8</div>
          <div class="sub">AI Sovereign Console • Workspace-Aware Assistant</div>
        </div>
      </div>

      <div class="actions">
        <button id="btnHealth" class="btn ghost">Health</button>
        <button id="btnIndex" class="btn">Index Workspace</button>
      </div>
    </header>

    <main class="grid">
      <section class="card chat">
        <div class="cardHead">
          <div class="h1">Chat</div>
          <div class="hint">Ask about files, bugs, features, next steps.</div>
        </div>

        <div id="chatLog" class="chatLog"></div>

        <div class="composer">
          <input id="chatInput" placeholder="Type: 'Explain the repo structure' or 'How do I run the bot?'"/>
          <button id="btnSend" class="btn">Send</button>
        </div>
      </section>

      <section class="card side">
        <div class="cardHead">
          <div class="h1">Tools</div>
          <div class="hint">Workspace search + safe ops</div>
        </div>

        <div class="toolBlock">
          <div class="label">Search workspace index</div>
          <div class="row">
            <input id="searchInput" placeholder="e.g. server port, bot token, run.sh"/>
            <button id="btnSearch" class="btn ghost">Search</button>
          </div>
          <pre id="searchOut" class="out"></pre>
        </div>

        <div class="toolBlock">
          <div class="label">AI Providers available</div>
          <div class="chips">
            <span class="chip">Ollama</span>
            <span class="chip">OpenAI</span>
            <span class="chip">Anthropic*</span>
            <span class="chip">Gemini*</span>
            <span class="chip">Groq*</span>
            <span class="chip">Together*</span>
            <span class="chip">Mistral*</span>
            <span class="chip">Cohere*</span>
            <span class="chip">DeepSeek*</span>
          </div>
          <div class="note">
            *Templates supported. Enable in backend by adding API calls in <code>ai_providers.py</code>.
          </div>
        </div>

        <div class="toolBlock">
          <div class="label">Admin Tools (disabled by default)</div>
          <div class="note">
            Exec & Write are OFF unless you enable them in <code>.env</code>.<br/>
            This prevents accidental damage.
          </div>
        </div>
      </section>
    </main>

    <footer class="foot">
      <span>FlashTM8 • Built for 8x8org</span>
      <span class="muted">Use Index Workspace first for best answers.</span>
    </footer>
  </div>

  <script src="/static/app.js"></script>
</body>
</html>
HTML

# ---------------------------
# 8) Frontend: app.js
# ---------------------------
cat > "$STATIC_DIR/app.js" << 'JS'
const chatLog = document.getElementById("chatLog");
const chatInput = document.getElementById("chatInput");
const btnSend = document.getElementById("btnSend");

const btnIndex = document.getElementById("btnIndex");
const btnHealth = document.getElementById("btnHealth");

const searchInput = document.getElementById("searchInput");
const btnSearch = document.getElementById("btnSearch");
const searchOut = document.getElementById("searchOut");

function addMsg(role, text) {
  const item = document.createElement("div");
  item.className = `msg ${role}`;
  item.innerHTML = `
    <div class="meta">${role === "user" ? "You" : "FlashTM8"}</div>
    <div class="bubble">${escapeHtml(text).replace(/\n/g, "<br/>")}</div>
  `;
  chatLog.appendChild(item);
  chatLog.scrollTop = chatLog.scrollHeight;
}

function escapeHtml(s) {
  return (s || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function postJSON(url, payload) {
  const res = await fetch(url, {
    method: "POST",
    headers: {"Content-Type":"application/json"},
    body: JSON.stringify(payload || {})
  });
  return await res.json();
}

btnSend.addEventListener("click", async () => {
  const msg = (chatInput.value || "").trim();
  if (!msg) return;
  chatInput.value = "";
  addMsg("user", msg);

  addMsg("ai", "Thinking…");
  const thinkingNode = chatLog.lastChild;

  try {
    const data = await postJSON("/api/chat", {message: msg});
    thinkingNode.remove();
    if (!data.ok) {
      addMsg("ai", `Error: ${data.error || "Unknown"}`);
      return;
    }
    addMsg("ai", data.reply || "(empty)");
  } catch (e) {
    thinkingNode.remove();
    addMsg("ai", "Request failed: " + e);
  }
});

chatInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") btnSend.click();
});

btnIndex.addEventListener("click", async () => {
  addMsg("ai", "Indexing workspace… (this may take a bit)");
  try {
    const data = await postJSON("/api/index", {});
    addMsg("ai", `✅ Indexed ${data.indexed_files} files.`);
  } catch (e) {
    addMsg("ai", "Index failed: " + e);
  }
});

btnHealth.addEventListener("click", async () => {
  try {
    const res = await fetch("/api/health");
    const data = await res.json();
    addMsg("ai", `Health OK ✅ Provider=${data.ai_provider} Root=${data.workspace_root}`);
  } catch (e) {
    addMsg("ai", "Health failed: " + e);
  }
});

btnSearch.addEventListener("click", async () => {
  const q = (searchInput.value || "").trim();
  if (!q) return;
  searchOut.textContent = "Searching…";
  try {
    const data = await postJSON("/api/search", {q});
    const lines = [];
    for (const r of (data.results || [])) {
      lines.push(`• ${r.path} (score=${r.score})\n${r.snippet}\n`);
    }
    searchOut.textContent = lines.join("\n") || "(no matches)";
  } catch (e) {
    searchOut.textContent = "Search failed: " + e;
  }
});

// Welcome
addMsg("ai",
`Welcome. I am FlashTM8 ⚡

1) Click "Index Workspace"
2) Ask me anything about your repo
3) I will answer using real file context

Try: "How do I run the dashboard and the bot?"`);
JS

# ---------------------------
# 9) Frontend: style.css
# ---------------------------
cat > "$STATIC_DIR/style.css" << 'CSS'
:root{
  --bg:#0b0f14;
  --card:#121a23;
  --muted:#8aa0b2;
  --text:#e7eef6;
  --accent:#35d0ff;
  --accent2:#9b6bff;
  --border:rgba(255,255,255,0.08);
}
*{box-sizing:border-box;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Arial;}
body{margin:0;background:radial-gradient(800px 400px at 20% 10%,rgba(53,208,255,0.14),transparent),radial-gradient(800px 400px at 80% 0%,rgba(155,107,255,0.12),transparent),var(--bg);color:var(--text);}
.wrap{max-width:1200px;margin:0 auto;padding:18px;}
.top{display:flex;justify-content:space-between;align-items:center;padding:14px 16px;border:1px solid var(--border);border-radius:16px;background:rgba(18,26,35,0.7);backdrop-filter: blur(10px);}
.brand{display:flex;gap:12px;align-items:center}
.logo{width:44px;height:44px;border-radius:14px;display:grid;place-items:center;background:linear-gradient(135deg,var(--accent),var(--accent2));color:#001018;font-size:22px;font-weight:900;}
.title{font-size:18px;font-weight:800;letter-spacing:0.2px}
.sub{font-size:12px;color:var(--muted)}
.actions{display:flex;gap:10px}
.btn{border:1px solid var(--border);background:linear-gradient(135deg,rgba(53,208,255,0.18),rgba(155,107,255,0.12));color:var(--text);padding:10px 14px;border-radius:12px;cursor:pointer;font-weight:700}
.btn.ghost{background:transparent}
.btn:hover{transform:translateY(-1px);transition:0.15s}
.grid{display:grid;grid-template-columns: 1.7fr 1fr;gap:16px;margin-top:16px}
.card{border:1px solid var(--border);border-radius:16px;background:rgba(18,26,35,0.7);backdrop-filter: blur(10px);padding:14px}
.cardHead{margin-bottom:10px}
.h1{font-size:16px;font-weight:900}
.hint{font-size:12px;color:var(--muted);margin-top:2px}
.chatLog{height:520px;overflow:auto;padding:10px;border:1px solid var(--border);border-radius:14px;background:rgba(0,0,0,0.15)}
.msg{margin:10px 0;display:flex;flex-direction:column;gap:6px}
.msg .meta{font-size:11px;color:var(--muted)}
.msg .bubble{padding:10px 12px;border-radius:14px;border:1px solid var(--border);line-height:1.35}
.msg.user .bubble{background:rgba(53,208,255,0.10)}
.msg.ai .bubble{background:rgba(155,107,255,0.10)}
.composer{display:flex;gap:10px;margin-top:10px}
.composer input{flex:1;padding:12px;border-radius:12px;border:1px solid var(--border);background:rgba(0,0,0,0.25);color:var(--text);outline:none}
.toolBlock{margin-top:14px}
.label{font-size:12px;color:var(--muted);margin-bottom:6px}
.row{display:flex;gap:10px}
.row input{flex:1;padding:10px;border-radius:12px;border:1px solid var(--border);background:rgba(0,0,0,0.25);color:var(--text);outline:none}
.out{white-space:pre-wrap;background:rgba(0,0,0,0.20);border:1px solid var(--border);padding:10px;border-radius:12px;max-height:240px;overflow:auto}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}
.chip{font-size:12px;padding:6px 10px;border:1px solid var(--border);border-radius:999px;background:rgba(255,255,255,0.04)}
.note{font-size:12px;color:var(--muted);margin-top:8px;line-height:1.4}
.foot{display:flex;justify-content:space-between;align-items:center;margin-top:14px;color:var(--muted);font-size:12px}
.muted{opacity:0.9}
code{font-family:ui-monospace,Menlo,Consolas,monospace;color:#cde9ff}
@media(max-width:900px){
  .grid{grid-template-columns:1fr}
  .chatLog{height:420px}
}
CSS

# ---------------------------
# 10) Run script
# ---------------------------
cat > "$APP_DIR/run_flashtm8.sh" << 'RUN'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/runner/workspace/repos/8x8org/apps/flashtm8"
BACKEND="$APP_DIR/backend"

# Load .env if present
if [ -f "$APP_DIR/.env" ]; then
  set -a
  source "$APP_DIR/.env"
  set +a
fi

export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-5050}"
export WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/runner/workspace/repos/8x8org}"

cd "$BACKEND"

echo "==============================================="
echo "⚡ FlashTM8 AI Dashboard"
echo "   Provider: ${AI_PROVIDER:-ollama}"
echo "   Workspace: $WORKSPACE_ROOT"
echo "   URL: http://127.0.0.1:$PORT"
echo "==============================================="

python app.py
RUN
chmod +x "$APP_DIR/run_flashtm8.sh"

# ---------------------------
# 11) Create repo shortcut (optional)
# ---------------------------
cat > "$ROOT/start_flashtm8.sh" << 'SHORT'
#!/usr/bin/env bash
set -e
bash /home/runner/workspace/repos/8x8org/apps/flashtm8/run_flashtm8.sh
SHORT
chmod +x "$ROOT/start_flashtm8.sh"

echo ""
echo "✅ Installed FlashTM8 AI Dashboard successfully!"
echo ""
echo "Next:"
echo "1) Copy env example:"
echo "   cp $APP_DIR/.env.example $APP_DIR/.env"
echo ""
echo "2) Start the dashboard:"
echo "   bash $ROOT/start_flashtm8.sh"
echo ""
echo "3) Open in browser:"
echo "   http://127.0.0.1:5050"
echo ""
echo "4) Click: Index Workspace"
echo "==============================================="
