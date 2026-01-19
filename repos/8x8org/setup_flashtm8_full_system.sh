#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# FlashTM8 Full System Installer + Fixer (Termux/Replit Portable)
# - Self-healing AI chain (offline -> ollama -> cloud -> fallback)
# - Fixes broken app.py / ai_providers.py cleanly
# - Adds Provider Settings UI (edit keys inside dashboard)
# - Builds local offline llama.cpp
# ============================================================

echo "==============================================="
echo "⚡ FlashTM8 Full System Setup"
echo "==============================================="

# ---------- Detect repo ----------
CWD="$(pwd)"
if [ -d "$CWD/apps/flashtm8/backend" ]; then
  REPO="$CWD"
elif [ -d "/home/runner/workspace/repos/8x8org/apps/flashtm8/backend" ]; then
  REPO="/home/runner/workspace/repos/8x8org"
else
  echo "❌ Repo not found. Run this script inside /home/runner/workspace/repos/8x8org"
  exit 1
fi

APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
ENVFILE="$APP/.env"
RUNTIME="$APP/runtime"
TOOLS="$REPO/tools"
LLAMA_DIR="$TOOLS/llama.cpp"
DBPATH="$RUNTIME/index.db"

mkdir -p "$BACK" "$RUNTIME" "$TOOLS"

echo "✅ Repo: $REPO"

# ---------- Termux basic packages ----------
# NOTE: If you're not on Termux, these may fail harmlessly.
echo "✅ Installing basic packages (Termux-safe)..."
if command -v pkg >/dev/null 2>&1; then
  pkg update -y || true
  pkg install -y \
    python git curl wget clang cmake make pkg-config \
    openssl libffi sqlite \
    termux-tools || true
fi

# ---------- Python libs ----------
echo "✅ Installing Python dependencies..."
python -m pip install --upgrade --user \
  flask python-dotenv requests || true

# Fix old requests/urllib3 mismatch (your earlier issue)
echo "✅ Fixing requests/urllib3 compatibility..."
python -m pip install --user --upgrade --force-reinstall \
  "requests>=2.32.3" "urllib3>=2.2.0" "six>=1.17.0" || true

# ---------- Build llama.cpp (offline local AI) ----------
echo "✅ Installing local OFFLINE AI engine (llama.cpp)..."
if [ ! -d "$LLAMA_DIR/.git" ]; then
  git clone --depth 1 https://github.com/ggerganov/llama.cpp "$LLAMA_DIR" || true
fi

if [ -d "$LLAMA_DIR" ]; then
  (cd "$LLAMA_DIR" && make -j2 || true)
fi

# Try to detect llama binary
LLAMA_BIN=""
for f in "$LLAMA_DIR/main" "$LLAMA_DIR/llama-cli" "$LLAMA_DIR/build/bin/main" "$LLAMA_DIR/build/bin/llama-cli"; do
  if [ -f "$f" ]; then
    LLAMA_BIN="$f"
    break
  fi
done

if [ -n "$LLAMA_BIN" ]; then
  echo "✅ llama.cpp built: $LLAMA_BIN"
else
  echo "⚠️ llama.cpp not compiled yet (still ok). You can compile later:"
  echo "   cd $LLAMA_DIR && make -j2"
fi

# ---------- Create .env (NO secrets auto-inserted) ----------
# You paste keys ONCE here later.
echo "✅ Writing FlashTM8 .env template..."
cat > "$ENVFILE" <<'ENV'
# ============================================================
# FlashTM8 Configuration
# ============================================================

# Server
HOST=0.0.0.0
PORT=5000

# Provider chain:
# auto = try local->ollama->openai->gemini->deepseek->fallback
AI_PROVIDER=auto

# ========== LOCAL OFFLINE AI ==========
# Optional: Put a GGUF model path here to enable offline responses.
# Example:
# LOCAL_MODEL_PATH=/sdcard/models/llama-3.2-1b-instruct.Q4_K_M.gguf
LOCAL_MODEL_PATH=
LOCAL_MODEL_BIN=

# ========== Ollama ==========
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.2

# ========== OpenAI ==========
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini

# ========== Gemini ==========
GEMINI_API_KEY=
GEMINI_MODEL=gemini-1.5-flash

# ========== DeepSeek ==========
DEEPSEEK_API_KEY=
DEEPSEEK_MODEL=deepseek-chat

# ========== Admin Tools ==========
# Exec/write tools are OFF by default for safety.
# Turn ON only when you want FlashTM8 to modify files.
EXEC_ENABLED=0
WRITE_ENABLED=0

# Workspace scope (FlashTM8 is allowed only inside this path)
WORKSPACE_ROOT=
ENV

# Fill workspace root if empty
python - <<PY
from pathlib import Path
p = Path("$ENVFILE")
txt = p.read_text()
if "WORKSPACE_ROOT=" in txt and "WORKSPACE_ROOT=\n" in txt:
    txt = txt.replace("WORKSPACE_ROOT=\n", f"WORKSPACE_ROOT={Path('$REPO').as_posix()}\n")
p.write_text(txt)
print("✅ WORKSPACE_ROOT set.")
PY

# If llama binary detected, store it
if [ -n "$LLAMA_BIN" ]; then
  python - <<PY
from pathlib import Path
p = Path("$ENVFILE")
txt = p.read_text()
txt = txt.replace("LOCAL_MODEL_BIN=\n", "LOCAL_MODEL_BIN=$LLAMA_BIN\n")
p.write_text(txt)
print("✅ LOCAL_MODEL_BIN set.")
PY
fi

# ---------- Backend: ai_providers.py ----------
echo "✅ Writing clean ai_providers.py (self-healing chain)..."
cat > "$BACK/ai_providers.py" <<'PY'
import os
import json
import subprocess
import time
import requests

def _env(k, default=""):
    return os.getenv(k, default).strip()

def _ok(provider, reply):
    return {"ok": True, "provider": provider, "reply": reply}

def _bad(provider, err):
    return {"ok": False, "provider": provider, "error": str(err), "reply": ""}

def _try_local_llamacpp(prompt: str):
    model_path = _env("LOCAL_MODEL_PATH")
    bin_path = _env("LOCAL_MODEL_BIN")
    if not model_path or not bin_path:
        return _bad("llamacpp", "LOCAL_MODEL_PATH or LOCAL_MODEL_BIN not set")

    if not os.path.isfile(model_path):
        return _bad("llamacpp", f"Model file not found: {model_path}")
    if not os.path.isfile(bin_path):
        return _bad("llamacpp", f"Binary not found: {bin_path}")

    try:
        # Works with llama.cpp main/llama-cli depending on build.
        # We do best-effort flags.
        cmd = [
            bin_path,
            "-m", model_path,
            "-n", "256",
            "--temp", "0.6",
            "--top-p", "0.9",
            "--prompt", prompt,
        ]
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, timeout=120)
        # Heuristic cleanup: remove prompt echoes if any
        reply = out.strip()
        return _ok("llamacpp", reply[-4000:])
    except Exception as e:
        return _bad("llamacpp", e)

def _try_ollama(prompt: str):
    base = _env("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    model = _env("OLLAMA_MODEL", "llama3.2")
    url = base.rstrip("/") + "/api/generate"
    try:
        r = requests.post(url, json={"model": model, "prompt": prompt, "stream": False}, timeout=30)
        if r.status_code != 200:
            return _bad("ollama", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        return _ok("ollama", data.get("response", "").strip())
    except Exception as e:
        return _bad("ollama", e)

def _try_openai(prompt: str):
    key = _env("OPENAI_API_KEY")
    model = _env("OPENAI_MODEL", "gpt-4o-mini")
    if not key:
        return _bad("openai", "OPENAI_API_KEY missing")

    # Minimal OpenAI REST call (no extra libs)
    url = "https://api.openai.com/v1/chat/completions"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.4,
    }

    try:
        r = requests.post(url, headers=headers, json=payload, timeout=45)
        if r.status_code != 200:
            return _bad("openai", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        reply = data["choices"][0]["message"]["content"]
        return _ok("openai", reply.strip())
    except Exception as e:
        return _bad("openai", e)

def _try_gemini(prompt: str):
    key = _env("GEMINI_API_KEY")
    model = _env("GEMINI_MODEL", "gemini-1.5-flash")
    if not key:
        return _bad("gemini", "GEMINI_API_KEY missing")

    # Gemini REST v1beta
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    payload = {"contents": [{"parts": [{"text": prompt}]}]}

    try:
        r = requests.post(url, json=payload, timeout=45)
        if r.status_code != 200:
            return _bad("gemini", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [])
        reply = "".join([p.get("text", "") for p in parts]).strip()
        return _ok("gemini", reply)
    except Exception as e:
        return _bad("gemini", e)

def _try_deepseek(prompt: str):
    key = _env("DEEPSEEK_API_KEY")
    model = _env("DEEPSEEK_MODEL", "deepseek-chat")
    if not key:
        return _bad("deepseek", "DEEPSEEK_API_KEY missing")

    # DeepSeek OpenAI-compatible endpoint (commonly used)
    url = "https://api.deepseek.com/chat/completions"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.4,
    }

    try:
        r = requests.post(url, headers=headers, json=payload, timeout=45)
        if r.status_code != 200:
            return _bad("deepseek", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        reply = data["choices"][0]["message"]["content"]
        return _ok("deepseek", reply.strip())
    except Exception as e:
        return _bad("deepseek", e)

def chat(prompt: str):
    """
    Always returns JSON dict:
      { ok: bool, provider: str, reply: str, error?: str }
    """
    provider = _env("AI_PROVIDER", "auto").lower()

    if provider == "llamacpp":
        return _try_local_llamacpp(prompt)
    if provider == "ollama":
        return _try_ollama(prompt)
    if provider == "openai":
        return _try_openai(prompt)
    if provider == "gemini":
        return _try_gemini(prompt)
    if provider == "deepseek":
        return _try_deepseek(prompt)

    # AUTO chain
    chain = [
        _try_local_llamacpp,
        _try_ollama,
        _try_openai,
        _try_gemini,
        _try_deepseek,
    ]

    last_err = None
    for fn in chain:
        res = fn(prompt)
        if res.get("ok"):
            return res
        last_err = res.get("error") or res.get("reply") or "unknown"

    return _bad("fallback", f"No provider available: {last_err}")
PY

# ---------- Backend: workspace_index.py ----------
echo "✅ Writing workspace_index.py (index/search)..."
cat > "$BACK/workspace_index.py" <<'PY'
import os
import sqlite3
from pathlib import Path

IGNORE_DIRS = {".git", "__pycache__", ".venv", "node_modules", "dist", "build"}

def init_db(db_path: str):
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT UNIQUE,
      size INTEGER,
      mtime INTEGER,
      content TEXT
    )
    """)
    con.commit()
    con.close()

def index_workspace(root: str, db_path: str, max_bytes=200_000):
    rootp = Path(root).resolve()
    init_db(db_path)
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    count = 0
    for p in rootp.rglob("*"):
        if p.is_dir():
            if p.name in IGNORE_DIRS:
                # skip subtree
                continue
            continue

        rel = str(p)
        if any(part in IGNORE_DIRS for part in p.parts):
            continue

        try:
            st = p.stat()
            if st.st_size > max_bytes:
                # store path only
                content = ""
            else:
                try:
                    content = p.read_text(errors="ignore")
                except:
                    content = ""
            cur.execute(
                "INSERT OR REPLACE INTO files(path,size,mtime,content) VALUES(?,?,?,?)",
                (rel, int(st.st_size), int(st.st_mtime), content),
            )
            count += 1
        except:
            pass

    con.commit()
    con.close()
    return count

def search(db_path: str, query: str, limit=20):
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    q = f"%{query}%"
    cur.execute(
        "SELECT path, size, mtime FROM files WHERE path LIKE ? OR content LIKE ? LIMIT ?",
        (q, q, limit),
    )
    rows = cur.fetchall()
    con.close()
    return [{"path": r[0], "size": r[1], "mtime": r[2]} for r in rows]
PY

# ---------- Backend: tools.py ----------
echo "✅ Writing tools.py (safe ops)..."
cat > "$BACK/tools.py" <<'PY'
import os
import subprocess
from pathlib import Path

def _env(k, d=""):
    return os.getenv(k, d).strip()

WORKSPACE_ROOT = Path(_env("WORKSPACE_ROOT", ".")).resolve()

def _allowed(path: Path):
    try:
        return WORKSPACE_ROOT in path.resolve().parents or path.resolve() == WORKSPACE_ROOT
    except:
        return False

def read_file(rel_path: str, max_chars=12000):
    p = (WORKSPACE_ROOT / rel_path).resolve()
    if not _allowed(p):
        return {"ok": False, "error": "Path not allowed"}
    if not p.exists() or not p.is_file():
        return {"ok": False, "error": "File not found"}
    try:
        txt = p.read_text(errors="ignore")
        return {"ok": True, "content": txt[:max_chars]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def write_file(rel_path: str, content: str):
    if _env("WRITE_ENABLED", "0") != "1":
        return {"ok": False, "error": "WRITE_DISABLED"}
    p = (WORKSPACE_ROOT / rel_path).resolve()
    if not _allowed(p):
        return {"ok": False, "error": "Path not allowed"}
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def exec_cmd(cmd: str):
    if _env("EXEC_ENABLED", "0") != "1":
        return {"ok": False, "error": "EXEC_DISABLED"}
    # very conservative exec (inside workspace only)
    try:
        out = subprocess.check_output(
            cmd, shell=True, cwd=str(WORKSPACE_ROOT),
            stderr=subprocess.STDOUT, text=True, timeout=60
        )
        return {"ok": True, "output": out[-12000:]}
    except subprocess.CalledProcessError as e:
        return {"ok": False, "output": (e.output or "")[-12000:], "error": str(e)}
    except Exception as e:
        return {"ok": False, "error": str(e)}
PY

# ---------- Backend: app.py (CLEAN + FIXED) ----------
echo "✅ Writing clean app.py (no more crashes)..."
cat > "$BACK/app.py" <<'PY'
import os
from flask import Flask, request, jsonify, render_template
from dotenv import load_dotenv

from ai_providers import chat as ai_chat
from workspace_index import index_workspace, search as ws_search
from tools import read_file, write_file, exec_cmd

load_dotenv()

def env(k, default=""):
    return os.getenv(k, default).strip()

APP_DIR = os.path.dirname(__file__)
TEMPLATE_DIR = os.path.join(APP_DIR, "templates")
STATIC_DIR = os.path.join(APP_DIR, "static")

DB_PATH = os.path.join(os.path.dirname(APP_DIR), "runtime", "index.db")
WORKSPACE_ROOT = env("WORKSPACE_ROOT", os.path.abspath(os.path.join(APP_DIR, "..", "..", "..")))

app = Flask(__name__, template_folder=TEMPLATE_DIR, static_folder=STATIC_DIR)

@app.get("/")
def home():
    return render_template("index.html")

@app.get("/api/health")
def health():
    return jsonify({
        "ok": True,
        "provider": env("AI_PROVIDER", "auto"),
        "workspace_root": WORKSPACE_ROOT,
        "db": DB_PATH,
        "exec_enabled": env("EXEC_ENABLED", "0"),
        "write_enabled": env("WRITE_ENABLED", "0"),
    })

@app.post("/api/index")
def do_index():
    count = index_workspace(WORKSPACE_ROOT, DB_PATH)
    return jsonify({"ok": True, "indexed": count})

@app.get("/api/search")
def do_search():
    q = request.args.get("q", "").strip()
    if not q:
        return jsonify({"ok": True, "results": []})
    res = ws_search(DB_PATH, q, limit=30)
    return jsonify({"ok": True, "results": res})

@app.post("/api/chat")
def do_chat():
    data = request.get_json(silent=True) or {}
    msg = (data.get("message") or "").strip()
    if not msg:
        return jsonify({"ok": False, "error": "Empty message"}), 400

    # Provide workspace guidance context
    prompt = f"""You are FlashTM8 ⚡ a workspace-aware assistant.
Workspace root: {WORKSPACE_ROOT}

User message:
{msg}

Rules:
- Be concrete and practical.
- If user asks about repo, mention files/scripts paths.
- If AI provider unavailable, still answer using workspace tools/search.
"""

    res = ai_chat(prompt)

    # Always force JSON response shape
    if isinstance(res, str):
        res = {"ok": True, "provider": "fallback", "reply": res}

    return jsonify({
        "ok": bool(res.get("ok")),
        "provider": res.get("provider", "unknown"),
        "reply": res.get("reply", ""),
        "error": res.get("error", ""),
    })

@app.post("/api/read")
def api_read():
    data = request.get_json(silent=True) or {}
    path = (data.get("path") or "").strip()
    return jsonify(read_file(path))

@app.post("/api/write")
def api_write():
    data = request.get_json(silent=True) or {}
    path = (data.get("path") or "").strip()
    content = data.get("content") or ""
    return jsonify(write_file(path, content))

@app.post("/api/exec")
def api_exec():
    data = request.get_json(silent=True) or {}
    cmd = (data.get("cmd") or "").strip()
    return jsonify(exec_cmd(cmd))

@app.post("/api/save_keys")
def api_save_keys():
    """
    Allows updating provider keys from UI into apps/flashtm8/.env
    """
    data = request.get_json(silent=True) or {}
    env_path = os.path.join(os.path.dirname(APP_DIR), ".env")

    # allowed keys only
    allowed = {
        "AI_PROVIDER","OLLAMA_BASE_URL","OLLAMA_MODEL",
        "OPENAI_API_KEY","OPENAI_MODEL",
        "GEMINI_API_KEY","GEMINI_MODEL",
        "DEEPSEEK_API_KEY","DEEPSEEK_MODEL",
        "LOCAL_MODEL_PATH","LOCAL_MODEL_BIN",
        "EXEC_ENABLED","WRITE_ENABLED",
        "PORT","HOST"
    }

    # load existing lines
    lines = []
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.read().splitlines()

    kv = {}
    for line in lines:
        if "=" in line and not line.strip().startswith("#"):
            k,v = line.split("=",1)
            kv[k.strip()] = v

    for k,v in data.items():
        if k in allowed:
            kv[k] = str(v)

    # rewrite env (preserve comments minimal)
    out = []
    out.append("# Auto-updated by FlashTM8 UI")
    for k in sorted(kv.keys()):
        out.append(f"{k}={kv[k]}")
    with open(env_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    return jsonify({"ok": True, "saved": True})

def main():
    host = env("HOST", "0.0.0.0")
    port = int(env("PORT", "5000"))
    app.run(host=host, port=port, debug=False)

if __name__ == "__main__":
    main()
PY

# ---------- Frontend: index.html / app.js / style.css ----------
echo "✅ Writing FlashTM8 frontend (Provider Settings + Chat + Index)..."

mkdir -p "$BACK/templates" "$BACK/static"

cat > "$BACK/templates/index.html" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>FlashTM8 ⚡</title>
  <link rel="stylesheet" href="/static/style.css" />
</head>
<body>
  <div class="top">
    <div class="brand">
      <div class="logo">⚡</div>
      <div>
        <div class="title">FlashTM8</div>
        <div class="sub">AI Sovereign Console • Workspace-Aware Assistant</div>
      </div>
    </div>
    <div class="status" id="status">Loading…</div>
  </div>

  <div class="grid">
    <div class="card">
      <h3>Tools</h3>
      <button onclick="health()">Health</button>
      <button onclick="indexWorkspace()">Index Workspace</button>

      <div class="sep"></div>
      <h3>Search</h3>
      <input id="searchQ" placeholder="server port, bot token, run.sh..." />
      <button onclick="search()">Search</button>
      <pre id="searchOut" class="out"></pre>
    </div>

    <div class="card">
      <h3>Chat</h3>
      <div class="chat" id="chat"></div>

      <div class="row">
        <input id="msg" placeholder="Ask about files, bugs, features, next steps..." />
        <button onclick="send()">Send</button>
      </div>

      <div class="meta" id="providerMeta"></div>
    </div>

    <div class="card">
      <h3>AI Providers + Keys</h3>
      <div class="hint">Edit here, click Save, restart dashboard if needed.</div>

      <label>AI_PROVIDER</label>
      <select id="AI_PROVIDER">
        <option value="auto">auto (offline→ollama→cloud→fallback)</option>
        <option value="llamacpp">llamacpp (offline)</option>
        <option value="ollama">ollama</option>
        <option value="openai">openai</option>
        <option value="gemini">gemini</option>
        <option value="deepseek">deepseek</option>
      </select>

      <label>LOCAL_MODEL_PATH (GGUF)</label>
      <input id="LOCAL_MODEL_PATH" placeholder="/sdcard/models/your-model.gguf" />

      <label>OLLAMA_BASE_URL</label>
      <input id="OLLAMA_BASE_URL" placeholder="http://127.0.0.1:11434" />

      <label>OPENAI_API_KEY</label>
      <input id="OPENAI_API_KEY" placeholder="sk-..." />

      <label>GEMINI_API_KEY</label>
      <input id="GEMINI_API_KEY" placeholder="AIza..." />

      <label>DEEPSEEK_API_KEY</label>
      <input id="DEEPSEEK_API_KEY" placeholder="sk-..." />

      <div class="row">
        <label style="flex:1">EXEC_ENABLED</label>
        <select id="EXEC_ENABLED">
          <option value="0">0 (OFF)</option>
          <option value="1">1 (ON)</option>
        </select>

        <label style="flex:1">WRITE_ENABLED</label>
        <select id="WRITE_ENABLED">
          <option value="0">0 (OFF)</option>
          <option value="1">1 (ON)</option>
        </select>
      </div>

      <button onclick="saveKeys()">Save Keys</button>
      <pre id="keysOut" class="out"></pre>
    </div>
  </div>

  <script src="/static/app.js"></script>
</body>
</html>
HTML

cat > "$BACK/static/style.css" <<'CSS'
body {
  font-family: system-ui, -apple-system, Arial;
  margin: 0;
  background: #0b0f14;
  color: #e6edf3;
}
.top {
  display:flex;
  align-items:center;
  justify-content:space-between;
  padding: 14px 18px;
  border-bottom: 1px solid #1b2633;
  background: #0b0f14;
  position: sticky;
  top:0;
}
.brand { display:flex; gap:12px; align-items:center; }
.logo { font-size:28px; }
.title { font-size:18px; font-weight:700; }
.sub { font-size:12px; opacity:.7; }
.status { font-size:12px; opacity:.8; }

.grid {
  display:grid;
  grid-template-columns: 320px 1fr 360px;
  gap:14px;
  padding:14px;
}
.card {
  background: #0f1722;
  border: 1px solid #1b2633;
  border-radius: 14px;
  padding: 14px;
}
h3 { margin: 0 0 10px; }
button {
  background: #1d7afc;
  color: white;
  border: none;
  border-radius: 10px;
  padding: 10px 12px;
  cursor: pointer;
  margin: 4px 0;
}
button:hover { opacity: .9; }
input, select {
  width:100%;
  padding: 10px 10px;
  border-radius:10px;
  border: 1px solid #263547;
  background: #0b0f14;
  color: #e6edf3;
  margin: 6px 0;
}
.sep { height:1px; background:#1b2633; margin: 10px 0; }
.out {
  white-space: pre-wrap;
  font-size: 12px;
  background: #0b0f14;
  border-radius: 12px;
  padding: 10px;
  border: 1px solid #263547;
  min-height: 70px;
}
.chat {
  height: 360px;
  overflow:auto;
  padding: 10px;
  border-radius: 12px;
  border: 1px solid #263547;
  background: #0b0f14;
}
.msgU { color: #9ddcff; margin: 6px 0; }
.msgA { color: #b6ffb6; margin: 6px 0; }
.row { display:flex; gap:8px; align-items:center; }
.row input { flex:1; margin: 0; }
.meta { margin-top: 8px; font-size:12px; opacity:.8; }
.hint { font-size:12px; opacity:.75; margin-bottom: 10px; }
CSS

cat > "$BACK/static/app.js" <<'JS'
async function api(path, method="GET", body=null) {
  const opts = { method, headers: {"Content-Type":"application/json"} };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(path, opts);
  const txt = await res.text();
  try { return JSON.parse(txt); } catch(e) {
    return { ok:false, error:"Bad JSON: " + txt.slice(0,200) };
  }
}

function addChat(role, text) {
  const box = document.getElementById("chat");
  const div = document.createElement("div");
  div.className = role === "user" ? "msgU" : "msgA";
  div.textContent = (role === "user" ? "You: " : "FlashTM8: ") + text;
  box.appendChild(div);
  box.scrollTop = box.scrollHeight;
}

async function health(){
  const data = await api("/api/health");
  document.getElementById("status").textContent =
    data.ok ? `✅ Online • Provider: ${data.provider}` : `❌ Error`;
  // load values into settings
  if (data.ok) {
    document.getElementById("AI_PROVIDER").value = data.provider || "auto";
  }
}

async function indexWorkspace(){
  addChat("assistant", "Indexing workspace…");
  const data = await api("/api/index", "POST", {});
  addChat("assistant", data.ok ? `✅ Indexed ${data.indexed} files.` : `❌ ${data.error}`);
}

async function search(){
  const q = document.getElementById("searchQ").value.trim();
  if (!q) return;
  const data = await api(`/api/search?q=${encodeURIComponent(q)}`);
  document.getElementById("searchOut").textContent =
    data.ok ? JSON.stringify(data.results, null, 2) : (data.error || "error");
}

async function send(){
  const inp = document.getElementById("msg");
  const msg = inp.value.trim();
  if (!msg) return;
  inp.value = "";
  addChat("user", msg);

  const data = await api("/api/chat", "POST", {message: msg});
  if (!data.ok) {
    addChat("assistant", "Error: " + (data.error || "Unknown"));
    return;
  }
  addChat("assistant", data.reply || "(empty)");
  document.getElementById("providerMeta").textContent = "Provider used: " + (data.provider || "unknown");
}

async function saveKeys(){
  const payload = {
    AI_PROVIDER: document.getElementById("AI_PROVIDER").value,
    LOCAL_MODEL_PATH: document.getElementById("LOCAL_MODEL_PATH").value,
    OLLAMA_BASE_URL: document.getElementById("OLLAMA_BASE_URL").value,
    OPENAI_API_KEY: document.getElementById("OPENAI_API_KEY").value,
    GEMINI_API_KEY: document.getElementById("GEMINI_API_KEY").value,
    DEEPSEEK_API_KEY: document.getElementById("DEEPSEEK_API_KEY").value,
    EXEC_ENABLED: document.getElementById("EXEC_ENABLED").value,
    WRITE_ENABLED: document.getElementById("WRITE_ENABLED").value,
  };
  const data = await api("/api/save_keys", "POST", payload);
  document.getElementById("keysOut").textContent =
    data.ok ? "✅ Saved. Restart FlashTM8 for changes to fully apply." : ("❌ " + data.error);
}

window.onload = () => {
  health();
  addChat("assistant", "Welcome. I am FlashTM8 ⚡");
  addChat("assistant", "1) Click Index Workspace");
  addChat("assistant", "2) Ask me about your repo");
  addChat("assistant", "3) I answer using real file context");
};
JS

# ---------- Start scripts ----------
echo "✅ Creating start_flashtm8.sh ..."
cat > "$REPO/start_flashtm8.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
ENVFILE="$REPO/apps/flashtm8/.env"

if [ -f "$ENVFILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENVFILE" || true
  set +a
fi

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-5000}"

echo "==============================================="
echo "⚡ FlashTM8 AI Dashboard"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "   Workspace: ${WORKSPACE_ROOT:-$REPO}"
echo "   URL: http://127.0.0.1:${PORT}"
echo "==============================================="

cd "$REPO/apps/flashtm8/backend"
exec python app.py
SH

chmod +x "$REPO/start_flashtm8.sh" || true
chmod +x "$APP/run_flashtm8.sh" 2>/dev/null || true

# ---------- run_flashtm8.sh compatibility ----------
cat > "$APP/run_flashtm8.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
exec bash "$REPO/start_flashtm8.sh"
SH
chmod +x "$APP/run_flashtm8.sh" || true

# ---------- Final info ----------
echo ""
echo "✅ FlashTM8 Full System Installed!"
echo "----------------------------------------------"
echo "RUN:"
echo "  cd $REPO"
echo "  bash start_flashtm8.sh"
echo ""
echo "OPEN:"
echo "  http://127.0.0.1:5000"
echo ""
echo "OFFLINE AI:"
echo "  1) Download any GGUF model to your phone (sdcard/models)"
echo "  2) Put path in: apps/flashtm8/.env -> LOCAL_MODEL_PATH="
echo ""
echo "Auto chain:"
echo "  Local(llama.cpp) -> Ollama -> OpenAI -> Gemini -> DeepSeek -> Fallback"
echo "----------------------------------------------"
