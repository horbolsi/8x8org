#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# FlashTM8 ULTIMATE - Sovereign Console (Offline + Cloud)
# Works on Termux + Replit-like Linux shells
# ==========================================================

REPO="${1:-$(pwd)}"
APP="$REPO/apps/flashtm8_ultimate"
BACK="$APP/backend"
STATIC="$BACK/static"
TPL="$BACK/templates"
RUNTIME="$APP/runtime"
ENVFILE="$APP/.env"
START="$REPO/start_flashtm8_ultimate.sh"

say()  { printf "\n✅ %s\n" "$*"; }
warn() { printf "\n⚠️ %s\n" "$*"; }

if [ ! -d "$REPO" ]; then
  echo "❌ Repo path not found: $REPO"
  exit 1
fi

mkdir -p "$BACK" "$STATIC" "$TPL" "$RUNTIME"

say "Repo: $REPO"
say "App:  $APP"

# ----------------------------------------------------------
# 1) Install system tools (best-effort)
# ----------------------------------------------------------
say "Installing system tools (best-effort)..."

if command -v pkg >/dev/null 2>&1; then
  # Termux
  pkg update -y || true
  pkg install -y python git curl jq ripgrep tree sqlite nodejs-lts || true
elif command -v apt-get >/dev/null 2>&1; then
  # Debian/Ubuntu
  sudo apt-get update -y || apt-get update -y || true
  sudo apt-get install -y python3 python3-pip git curl jq ripgrep tree sqlite3 nodejs npm || \
    apt-get install -y python3 python3-pip git curl jq ripgrep tree sqlite3 nodejs npm || true
else
  warn "No pkg/apt-get found. Skipping system package install."
fi

# ----------------------------------------------------------
# 2) Python deps (Termux safe user install)
# ----------------------------------------------------------
say "Installing Python dependencies..."
python -m pip install --user --upgrade \
  flask requests python-dotenv \
  >/dev/null || true

# Fix old Termux requests/urllib3 combos (your earlier bug)
say "Fixing requests/urllib3/six compatibility..."
python -m pip install --user --upgrade --force-reinstall \
  "requests>=2.32.3" "urllib3>=2.2.0" "six>=1.17.0" \
  >/dev/null || true

# Optional but powerful: faster search + embeddings (can fail on Termux; non-fatal)
python -m pip install --user --upgrade \
  pydantic \
  >/dev/null 2>&1 || true

# ----------------------------------------------------------
# 3) Write a clean .env (SAFE format, quoted)
# ----------------------------------------------------------
say "Creating default .env (safe quoted values)..."

cat > "$ENVFILE" <<ENV
# ==========================================================
# FlashTM8 ULTIMATE .env (safe quoted values)
# ==========================================================
AI_PROVIDER="auto"

# Workspace root (auto)
WORKSPACE_ROOT="$REPO"

# Offline local model (optional)
# Put a GGUF here if you use llama-cpp-python:
LOCAL_MODEL_PATH=""

# Ollama (optional)
OLLAMA_BASE_URL="http://127.0.0.1:11434"
OLLAMA_MODEL="llama3"

# Cloud providers (optional)
OPENAI_API_KEY=""
OPENAI_MODEL="gpt-4o-mini"

GEMINI_API_KEY=""
GEMINI_MODEL="gemini-1.5-flash"

DEEPSEEK_API_KEY=""
DEEPSEEK_MODEL="deepseek-chat"
DEEPSEEK_BASE_URL="https://api.deepseek.com"

XAI_API_KEY=""
XAI_MODEL="grok-2-latest"
XAI_BASE_URL="https://api.x.ai/v1"

# Memory/Indexing
INDEX_DB_PATH="$RUNTIME/index.db"
MAX_FILE_BYTES="250000"

# Security gates (OFF by default)
EXEC_ENABLED="0"
WRITE_ENABLED="0"

# Write policy (safety)
ALLOW_WRITE_SUBDIRS="apps,services,scripts,docs,projects,tools,patches"
DENY_WRITE_PATTERNS=".env,.git,ssh,id_rsa,token,secret,key"

# Session secret for dashboard cookies (optional)
SESSION_SECRET=""

# Your project secrets (optional, keep quoted!)
SMTP_USER=""
SMTP_PASS=""
CLICKUP_API_TOKEN=""
OWNER_ID=""

TELEGRAM_BOT_TOKEN=""
app8x8org_BOT_TOKEN=""
out8x8org_BOT_TOKEN=""
in8x8org_bot=""
airdrop8x8org_bot=""
wallet8x8org_bot=""

GITHUB_TOKEN=""
ENV

# ----------------------------------------------------------
# 4) Build Workspace Indexer (SQLite)
# ----------------------------------------------------------
say "Writing workspace_index.py..."

cat > "$BACK/workspace_index.py" <<'PY'
import os, sqlite3, hashlib
from pathlib import Path

DEFAULT_EXCLUDES = {
    ".git", ".venv", "node_modules", "__pycache__", ".pytest_cache",
    "dist", "build", ".mypy_cache", ".cache", ".idea", ".vscode"
}

TEXT_EXTS = {
    ".py",".js",".ts",".tsx",".json",".md",".txt",".sh",".html",".css",
    ".yml",".yaml",".toml",".ini",".env.example",".sql",".graphql"
}

def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", "ignore")).hexdigest()

def init_db(db_path: str):
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    cur.execute("""
      CREATE TABLE IF NOT EXISTS files (
        path TEXT PRIMARY KEY,
        mtime REAL,
        size INTEGER,
        sha TEXT,
        content TEXT
      );
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_path ON files(path);")
    con.commit()
    con.close()

def index_workspace(root: str, db_path: str, max_bytes: int, extra_excludes=None):
    rootp = Path(root).resolve()
    exclude = set(extra_excludes or []) | DEFAULT_EXCLUDES
    init_db(db_path)

    con = sqlite3.connect(db_path)
    cur = con.cursor()
    count = 0

    for p in rootp.rglob("*"):
        try:
            if p.is_dir():
                if p.name in exclude:
                    continue
                continue

            # skip excluded dirs
            if any(part in exclude for part in p.parts):
                continue

            # only index text-like extensions
            ext = p.suffix.lower()
            if ext not in TEXT_EXTS:
                continue

            st = p.stat()
            rel = str(p.relative_to(rootp))

            if st.st_size > max_bytes:
                content = f"[SKIPPED large file: {st.st_size} bytes]"
            else:
                content = p.read_text(errors="ignore")

            sha = _sha(content)

            cur.execute("""
              INSERT INTO files(path, mtime, size, sha, content)
              VALUES(?,?,?,?,?)
              ON CONFLICT(path) DO UPDATE SET
                mtime=excluded.mtime,
                size=excluded.size,
                sha=excluded.sha,
                content=excluded.content
            """, (rel, st.st_mtime, st.st_size, sha, content))

            count += 1
        except Exception:
            continue

    con.commit()
    con.close()
    return count

def search(db_path: str, q: str, limit: int = 12):
    if not Path(db_path).exists():
        return []
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    q2 = f"%{q}%"
    cur.execute("""
      SELECT path, substr(content, 1, 1400)
      FROM files
      WHERE path LIKE ? OR content LIKE ?
      LIMIT ?
    """, (q2, q2, limit))
    rows = cur.fetchall()
    con.close()
    return [{"path": r[0], "snippet": r[1]} for r in rows]
PY

# ----------------------------------------------------------
# 5) Safe Tools (exec/write guarded)
# ----------------------------------------------------------
say "Writing tools.py..."

cat > "$BACK/tools.py" <<'PY'
import os, subprocess
from pathlib import Path

def _env(k, d=""):
    return os.getenv(k, d)

def enabled(flag: str) -> bool:
    return _env(flag, "0").lower() in ("1","true","yes","on")

def _deny_by_pattern(path: str) -> bool:
    deny = _env("DENY_WRITE_PATTERNS","").lower().split(",")
    path_l = path.lower()
    return any(x.strip() and x.strip() in path_l for x in deny)

def _allowed_subdir(path: str) -> bool:
    allow = [x.strip() for x in _env("ALLOW_WRITE_SUBDIRS","").split(",") if x.strip()]
    if not allow:
        return True
    parts = Path(path).parts
    if not parts:
        return False
    # allow if first folder is in allow list
    return parts[0] in allow

def safe_exec(cmd: str, cwd: str):
    if not enabled("EXEC_ENABLED"):
        return {"ok": False, "error": "EXEC is disabled (set EXEC_ENABLED=1 in .env)"}
    try:
        r = subprocess.run(cmd, shell=True, cwd=cwd, text=True, capture_output=True)
        return {"ok": r.returncode == 0, "code": r.returncode, "stdout": r.stdout[-8000:], "stderr": r.stderr[-8000:]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def safe_write(rel_path: str, content: str, root: str):
    if not enabled("WRITE_ENABLED"):
        return {"ok": False, "error": "WRITE is disabled (set WRITE_ENABLED=1 in .env)"}

    if _deny_by_pattern(rel_path):
        return {"ok": False, "error": "Write blocked by DENY_WRITE_PATTERNS"}

    if not _allowed_subdir(rel_path):
        return {"ok": False, "error": "Write blocked (path not in ALLOW_WRITE_SUBDIRS)"}

    rp = Path(root).resolve()
    p = (rp / rel_path).resolve()

    if not str(p).startswith(str(rp)):
        return {"ok": False, "error": "Write blocked (outside WORKSPACE_ROOT)"}

    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    return {"ok": True, "path": str(p)}

def safe_read(rel_path: str, root: str):
    rp = Path(root).resolve()
    p = (rp / rel_path).resolve()
    if not str(p).startswith(str(rp)) or not p.exists() or p.is_dir():
        return {"ok": False, "error": "File not found"}
    try:
        return {"ok": True, "content": p.read_text(errors="ignore")[:20000]}
    except Exception as e:
        return {"ok": False, "error": str(e)}
PY

# ----------------------------------------------------------
# 6) AI Providers (Auto chain + offline + fallback)
# ----------------------------------------------------------
say "Writing ai_providers.py (auto provider chain)..."

cat > "$BACK/ai_providers.py" <<'PY'
import os, json, requests
from typing import Tuple

def env(k, d=""):
    return os.getenv(k, d)

def ok(provider: str, reply: str):
    return {"ok": True, "provider": provider, "reply": reply}

def fail(provider: str, err: str):
    return {"ok": False, "provider": provider, "error": err}

def post_json(url, headers=None, payload=None, timeout=60):
    r = requests.post(url, headers=headers or {}, json=payload or {}, timeout=timeout)
    return r.status_code, r.text

def local_llama(prompt: str):
    model_path = env("LOCAL_MODEL_PATH","")
    if not model_path:
        return fail("local", "LOCAL_MODEL_PATH missing")
    try:
        from llama_cpp import Llama
    except Exception:
        return fail("local", "llama-cpp-python not installed (optional)")
    try:
        llm = Llama(model_path=model_path, n_ctx=4096)
        out = llm(prompt, max_tokens=512)
        text = out["choices"][0]["text"].strip()
        return ok("local", text or "[empty]")
    except Exception as e:
        return fail("local", str(e))

def ollama(prompt: str):
    base = env("OLLAMA_BASE_URL","http://127.0.0.1:11434").rstrip("/")
    model = env("OLLAMA_MODEL","llama3")
    try:
        code, txt = post_json(f"{base}/api/generate", payload={"model": model, "prompt": prompt, "stream": False}, timeout=60)
        if code != 200:
            return fail("ollama", f"HTTP {code}: {txt[:200]}")
        data = json.loads(txt)
        return ok("ollama", (data.get("response") or "").strip() or "[empty]")
    except Exception as e:
        return fail("ollama", str(e))

def gemini(prompt: str):
    key = env("GEMINI_API_KEY","")
    if not key:
        return fail("gemini", "GEMINI_API_KEY missing")
    model = env("GEMINI_MODEL","gemini-1.5-flash")
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
        payload = {"contents":[{"parts":[{"text": prompt}]}]}
        code, txt = post_json(url, payload=payload, timeout=60)
        if code != 200:
            return fail("gemini", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["candidates"][0]["content"]["parts"][0]["text"]
        return ok("gemini", reply.strip())
    except Exception as e:
        return fail("gemini", str(e))

def openai(prompt: str):
    key = env("OPENAI_API_KEY","")
    if not key:
        return fail("openai", "OPENAI_API_KEY missing")
    model = env("OPENAI_MODEL","gpt-4o-mini")
    try:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type":"application/json"}
        payload = {"model": model, "messages":[{"role":"user","content":prompt}], "temperature":0.2}
        code, txt = post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return fail("openai", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return ok("openai", reply.strip())
    except Exception as e:
        return fail("openai", str(e))

def deepseek(prompt: str):
    key = env("DEEPSEEK_API_KEY","")
    if not key:
        return fail("deepseek", "DEEPSEEK_API_KEY missing")
    model = env("DEEPSEEK_MODEL","deepseek-chat")
    base = env("DEEPSEEK_BASE_URL","https://api.deepseek.com").rstrip("/")
    try:
        url = f"{base}/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type":"application/json"}
        payload = {"model": model, "messages":[{"role":"user","content":prompt}], "temperature":0.2}
        code, txt = post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return fail("deepseek", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return ok("deepseek", reply.strip())
    except Exception as e:
        return fail("deepseek", str(e))

def xai(prompt: str):
    key = env("XAI_API_KEY","")
    if not key:
        return fail("xai", "XAI_API_KEY missing")
    model = env("XAI_MODEL","grok-2-latest")
    base = env("XAI_BASE_URL","https://api.x.ai/v1").rstrip("/")
    try:
        url = f"{base}/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type":"application/json"}
        payload = {"model": model, "messages":[{"role":"user","content":prompt}], "temperature":0.2}
        code, txt = post_json(url, headers=headers, payload=payload, timeout=60)
        if code != 200:
            return fail("xai", f"HTTP {code}: {txt[:240]}")
        data = json.loads(txt)
        reply = data["choices"][0]["message"]["content"]
        return ok("xai", reply.strip())
    except Exception as e:
        return fail("xai", str(e))

def fallback(prompt: str):
    return ok(
        "fallback",
        "FlashTM8 Ultimate is running ✅\n"
        "AI provider not reachable now, but indexing + search + tools still work.\n"
        "Try: Index Workspace → Search 'run.sh' → Ask how to start bots."
    )

def generate_reply(prompt: str) -> Tuple[str, dict]:
    mode = env("AI_PROVIDER","auto").strip().lower()

    chain = []
    if mode == "auto":
        chain = [local_llama, ollama, gemini, openai, xai, deepseek, fallback]
    elif mode == "local":
        chain = [local_llama, fallback]
    elif mode == "ollama":
        chain = [ollama, fallback]
    elif mode == "gemini":
        chain = [gemini, fallback]
    elif mode == "openai":
        chain = [openai, fallback]
    elif mode == "xai":
        chain = [xai, fallback]
    elif mode == "deepseek":
        chain = [deepseek, fallback]
    else:
        chain = [fallback]

    last = None
    for fn in chain:
        res = fn(prompt)
        last = res
        if res.get("ok"):
            return res.get("provider","unknown"), res

    return "fallback", last or fallback(prompt)
PY

# ----------------------------------------------------------
# 7) Pro Dashboard Backend (Flask)
# ----------------------------------------------------------
say "Writing app.py (Ultimate dashboard backend)..."

cat > "$BACK/app.py" <<'PY'
import os
from pathlib import Path
from flask import Flask, request, jsonify, render_template
from dotenv import load_dotenv

from workspace_index import index_workspace, search as search_index
from ai_providers import generate_reply
from tools import safe_exec, safe_write, safe_read

HERE = Path(__file__).resolve().parent
APPROOT = HERE.parent
ENVFILE = APPROOT / ".env"

load_dotenv(ENVFILE)

def env(k, d=""):
    return os.getenv(k, d)

def mask(v: str):
    if not v: return ""
    if len(v) <= 8: return "****"
    return v[:4] + "…" + v[-4:]

def create_app():
    app = Flask(__name__, template_folder=str(HERE/"templates"), static_folder=str(HERE/"static"))

    @app.get("/")
    def home():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        return jsonify({
            "ok": True,
            "provider": env("AI_PROVIDER","auto"),
            "workspace_root": env("WORKSPACE_ROOT",""),
            "exec": env("EXEC_ENABLED","0"),
            "write": env("WRITE_ENABLED","0"),
        })

    @app.post("/api/index")
    def api_index():
        root = env("WORKSPACE_ROOT", str(Path.cwd()))
        db = env("INDEX_DB_PATH", str(APPROOT/"runtime/index.db"))
        maxb = int(env("MAX_FILE_BYTES","250000"))
        count = index_workspace(root, db, maxb)
        return jsonify({"ok": True, "indexed_files": count, "db": db})

    @app.post("/api/search")
    def api_search():
        q = (request.json or {}).get("q","").strip()
        if not q:
            return jsonify({"ok": False, "error":"missing q"}), 400
        db = env("INDEX_DB_PATH", str(APPROOT/"runtime/index.db"))
        hits = search_index(db, q, limit=12)
        return jsonify({"ok": True, "hits": hits})

    @app.post("/api/chat")
    def api_chat():
        msg = (request.json or {}).get("message","").strip()
        if not msg:
            return jsonify({"ok": False, "error":"missing message"}), 400

        provider, res = generate_reply(msg)
        if isinstance(res, str):
            res = {"ok": True, "provider": provider, "reply": res}

        if not res.get("ok"):
            return jsonify({"ok": False, "provider": provider, "error": res.get("error","unknown")})

        return jsonify({"ok": True, "provider": provider, "reply": res.get("reply","")})

    @app.get("/api/config")
    def api_config():
        cfg = {
            "AI_PROVIDER": env("AI_PROVIDER","auto"),
            "LOCAL_MODEL_PATH": env("LOCAL_MODEL_PATH",""),
            "OLLAMA_BASE_URL": env("OLLAMA_BASE_URL",""),
            "OPENAI_API_KEY": mask(env("OPENAI_API_KEY","")),
            "GEMINI_API_KEY": mask(env("GEMINI_API_KEY","")),
            "DEEPSEEK_API_KEY": mask(env("DEEPSEEK_API_KEY","")),
            "XAI_API_KEY": mask(env("XAI_API_KEY","")),
            "EXEC_ENABLED": env("EXEC_ENABLED","0"),
            "WRITE_ENABLED": env("WRITE_ENABLED","0"),
        }
        return jsonify({"ok": True, "config": cfg})

    @app.post("/api/config")
    def api_config_save():
        data = request.json or {}
        allowed = {
            "AI_PROVIDER","LOCAL_MODEL_PATH",
            "OLLAMA_BASE_URL","OLLAMA_MODEL",
            "OPENAI_API_KEY","OPENAI_MODEL",
            "GEMINI_API_KEY","GEMINI_MODEL",
            "DEEPSEEK_API_KEY","DEEPSEEK_MODEL","DEEPSEEK_BASE_URL",
            "XAI_API_KEY","XAI_MODEL","XAI_BASE_URL",
            "EXEC_ENABLED","WRITE_ENABLED",
        }

        # Read current .env
        kv = {}
        if ENVFILE.exists():
            for ln in ENVFILE.read_text(errors="ignore").splitlines():
                if not ln.strip() or ln.strip().startswith("#") or "=" not in ln:
                    continue
                k,v = ln.split("=",1)
                kv[k.strip()] = v.strip().strip('"').strip("'")

        # Apply updates
        for k,v in data.items():
            if k in allowed:
                kv[k] = str(v)

        # Always keep WORKSPACE_ROOT stable
        kv["WORKSPACE_ROOT"] = env("WORKSPACE_ROOT","")

        # Rewrite .env safely quoted
        out = []
        out.append("# FlashTM8 Ultimate .env (auto-written)")
        for k in sorted(kv.keys()):
            val = kv[k].replace('"','\\"')
            out.append(f'{k}="{val}"')
        ENVFILE.write_text("\n".join(out) + "\n")

        load_dotenv(ENVFILE, override=True)
        return jsonify({"ok": True, "saved": True})

    @app.post("/api/read")
    def api_read():
        p = (request.json or {}).get("path","").strip()
        root = env("WORKSPACE_ROOT", str(Path.cwd()))
        return jsonify(safe_read(p, root))

    @app.post("/api/exec")
    def api_exec():
        cmd = (request.json or {}).get("cmd","").strip()
        root = env("WORKSPACE_ROOT", str(Path.cwd()))
        return jsonify(safe_exec(cmd, root))

    @app.post("/api/write")
    def api_write():
        p = (request.json or {}).get("path","").strip()
        content = (request.json or {}).get("content","")
        root = env("WORKSPACE_ROOT", str(Path.cwd()))
        return jsonify(safe_write(p, content, root))

    return app

if __name__ == "__main__":
    app = create_app()
    port = int(os.getenv("PORT","5000"))
    app.run(host="0.0.0.0", port=port, debug=False)
PY

# ----------------------------------------------------------
# 8) Pro UI (single-page, fast, mobile friendly)
# ----------------------------------------------------------
say "Writing professional UI..."

cat > "$TPL/index.html" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>FlashTM8 Ultimate ⚡</title>
  <link rel="stylesheet" href="/static/style.css"/>
</head>
<body>
  <div class="wrap">
    <div class="top">
      <div class="brand">
        <div class="logo">⚡ FlashTM8</div>
        <div class="tag">Ultimate Sovereign Console • Workspace-Aware • Self-Healing</div>
      </div>
      <div id="health" class="health">Loading…</div>
    </div>

    <div class="grid">
      <section class="card">
        <h2>Tools</h2>
        <div class="row">
          <button id="btnIndex">Index Workspace</button>
          <input id="q" placeholder="Search: run.sh, bot token, port, error..." />
          <button id="btnSearch">Search</button>
        </div>
        <pre id="out" class="out"></pre>
      </section>

      <section class="card">
        <h2>Chat</h2>
        <div id="chatlog" class="chatlog"></div>
        <div class="row">
          <input id="msg" placeholder="Ask FlashTM8 about repo, bugs, next steps..." />
          <button id="btnSend">Send</button>
        </div>
        <div id="provider" class="small"></div>
      </section>

      <section class="card wide">
        <h2>AI Providers + Keys</h2>
        <div class="form">
          <label>AI_PROVIDER <input id="AI_PROVIDER" value="auto"></label>
          <label>LOCAL_MODEL_PATH (GGUF) <input id="LOCAL_MODEL_PATH" placeholder="/sdcard/models/model.gguf"></label>
          <label>OLLAMA_BASE_URL <input id="OLLAMA_BASE_URL" value="http://127.0.0.1:11434"></label>
          <label>OPENAI_API_KEY <input id="OPENAI_API_KEY" placeholder="sk-..."></label>
          <label>GEMINI_API_KEY <input id="GEMINI_API_KEY" placeholder="AIza..."></label>
          <label>DEEPSEEK_API_KEY <input id="DEEPSEEK_API_KEY" placeholder="sk-..."></label>
          <label>XAI_API_KEY <input id="XAI_API_KEY" placeholder="..."></label>
          <label>EXEC_ENABLED <input id="EXEC_ENABLED" value="0"></label>
          <label>WRITE_ENABLED <input id="WRITE_ENABLED" value="0"></label>
        </div>
        <div class="row">
          <button id="btnSave">Save Keys</button>
          <div id="saveMsg" class="small"></div>
        </div>
      </section>
    </div>

    <footer class="foot">
      FlashTM8 Ultimate • Designed for full sovereign control of 8x8org
    </footer>
  </div>

  <script src="/static/app.js"></script>
</body>
</html>
HTML

cat > "$STATIC/style.css" <<'CSS'
:root{--bg:#0a0f16;--card:#0f1724;--b:#223248;--txt:#d7e2ee;--mut:#9bb1c7;--acc:#1f6feb}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--txt);font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu}
.wrap{max-width:1100px;margin:0 auto;padding:18px}
.top{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-bottom:12px}
.brand .logo{font-weight:900;font-size:22px}
.brand .tag{color:var(--mut);font-size:12px;margin-top:4px}
.health{padding:10px 12px;border:1px solid var(--b);border-radius:14px;background:#0b1220;color:var(--mut);font-size:12px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.card{background:var(--card);border:1px solid var(--b);border-radius:18px;padding:14px}
.card.wide{grid-column:1 / -1}
h2{margin:0 0 10px 0;font-size:16px}
.row{display:flex;gap:10px;align-items:center;margin-top:10px}
input{flex:1;background:#0b1220;border:1px solid var(--b);border-radius:14px;padding:10px 12px;color:var(--txt);outline:none}
button{background:var(--acc);border:none;border-radius:14px;padding:10px 12px;color:white;font-weight:700;cursor:pointer}
button:active{transform:translateY(1px)}
pre.out{white-space:pre-wrap;background:#0b1220;border:1px solid var(--b);border-radius:14px;padding:12px;min-height:120px;margin-top:10px}
.chatlog{background:#0b1220;border:1px solid var(--b);border-radius:14px;padding:12px;min-height:180px;overflow:auto}
.small{color:var(--mut);font-size:12px}
.form{display:grid;grid-template-columns:1fr 1fr;gap:10px}
label{display:flex;flex-direction:column;gap:6px;font-size:12px;color:var(--mut)}
.foot{color:var(--mut);font-size:11px;margin-top:14px;text-align:center}
.msgU{color:#9bd;margin:6px 0}
.msgB{color:#bfe;margin:6px 0}
@media(max-width:900px){.grid{grid-template-columns:1fr}.form{grid-template-columns:1fr}}
CSS

cat > "$STATIC/app.js" <<'JS'
const el=id=>document.getElementById(id);
async function post(url, body){
  const r=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body||{})});
  return await r.json();
}
async function get(url){const r=await fetch(url);return await r.json();}

function chat(cls, txt){
  const d=document.createElement("div");
  d.className=cls;
  d.textContent=txt;
  el("chatlog").appendChild(d);
  el("chatlog").scrollTop=el("chatlog").scrollHeight;
}

async function refreshHealth(){
  const h=await get("/api/health");
  if(h.ok){
    el("health").textContent=`✅ Online • Provider: ${h.provider} • EXEC=${h.exec} • WRITE=${h.write}`;
  }else{
    el("health").textContent="⚠️ Offline";
  }
}

async function refreshConfig(){
  const r=await get("/api/config");
  if(!r.ok) return;
  const c=r.config||{};
  ["AI_PROVIDER","LOCAL_MODEL_PATH","OLLAMA_BASE_URL","EXEC_ENABLED","WRITE_ENABLED"].forEach(k=>{
    if(c[k]!==undefined) el(k).value=c[k];
  });
}

el("btnIndex").onclick=async()=>{
  el("out").textContent="Indexing workspace...";
  const r=await post("/api/index",{});
  el("out").textContent=JSON.stringify(r,null,2);
  await refreshHealth();
};

el("btnSearch").onclick=async()=>{
  const q=el("q").value.trim();
  if(!q) return;
  el("out").textContent="Searching...";
  const r=await post("/api/search",{q});
  el("out").textContent=JSON.stringify(r,null,2);
};

el("btnSend").onclick=async()=>{
  const m=el("msg").value.trim();
  if(!m) return;
  el("msg").value="";
  chat("msgU","You: "+m);
  const r=await post("/api/chat",{message:m});
  if(r.ok){
    chat("msgB","FlashTM8: "+r.reply);
    el("provider").textContent="Provider used: "+(r.provider||"unknown");
  }else{
    chat("msgB","FlashTM8: Error: "+(r.error||"unknown"));
    el("provider").textContent="Provider used: "+(r.provider||"unknown");
  }
};

el("btnSave").onclick=async()=>{
  const payload={
    AI_PROVIDER: el("AI_PROVIDER").value.trim(),
    LOCAL_MODEL_PATH: el("LOCAL_MODEL_PATH").value.trim(),
    OLLAMA_BASE_URL: el("OLLAMA_BASE_URL").value.trim(),
    OPENAI_API_KEY: el("OPENAI_API_KEY").value.trim(),
    GEMINI_API_KEY: el("GEMINI_API_KEY").value.trim(),
    DEEPSEEK_API_KEY: el("DEEPSEEK_API_KEY").value.trim(),
    XAI_API_KEY: el("XAI_API_KEY").value.trim(),
    EXEC_ENABLED: el("EXEC_ENABLED").value.trim(),
    WRITE_ENABLED: el("WRITE_ENABLED").value.trim(),
  };
  const r=await post("/api/config",payload);
  el("saveMsg").textContent=r.ok?"✅ Saved. Restart recommended.":"❌ Save failed";
  await refreshHealth();
};

(async()=>{
  await refreshHealth();
  await refreshConfig();
  chat("msgB","FlashTM8 Ultimate: Welcome ⚡");
  chat("msgB","1) Click Index Workspace");
  chat("msgB","2) Ask me about your repo");
  chat("msgB","3) I self-heal providers automatically");
})();
JS

# ----------------------------------------------------------
# 9) Start script (Termux-friendly)
# ----------------------------------------------------------
say "Writing start_flashtm8_ultimate.sh..."

cat > "$START" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
ENVFILE="$REPO/apps/flashtm8_ultimate/.env"
PORT="${PORT:-5000}"

set -a
[ -f "$ENVFILE" ] && . "$ENVFILE"
set +a

export PORT="$PORT"

echo "==============================================="
echo "⚡ FlashTM8 ULTIMATE"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "   Workspace: ${WORKSPACE_ROOT:-$REPO}"
echo "   URL: http://127.0.0.1:${PORT}"
echo "==============================================="

cd "$REPO/apps/flashtm8_ultimate/backend"
python app.py
SH

chmod +x "$START" || true

# ----------------------------------------------------------
# 10) Install offline AI options (optional helpers)
# ----------------------------------------------------------
say "Offline AI options (optional install steps printed below)"

cat > "$APP/OFFLINE_AI_GUIDE.txt" <<'TXT'
FlashTM8 Ultimate Offline AI Options
===================================

A) Ollama (best if supported)
----------------------------
1) Install Ollama on a PC/VPS and expose port 11434 securely
2) Set in dashboard: OLLAMA_BASE_URL=http://YOUR_SERVER:11434
3) AI_PROVIDER=auto or ollama

B) Local GGUF on Android (Termux)
---------------------------------
This may or may not compile on Termux depending on device/ABI.

1) Download a GGUF model to:
   /sdcard/models/model.gguf

2) Try install:
   python -m pip install --user llama-cpp-python

3) Set:
   LOCAL_MODEL_PATH="/sdcard/models/model.gguf"
   AI_PROVIDER="auto"

C) “No AI credit / no offline model”
------------------------------------
Auto chain falls back safely.
Index + Search still works, so FlashTM8 stays useful.

TXT

say "Final python compile check..."
python -m py_compile "$BACK/app.py" "$BACK/ai_providers.py" "$BACK/workspace_index.py" "$BACK/tools.py"

say "✅ FlashTM8 Ultimate installed successfully!"

echo ""
echo "NEXT:"
echo "  1) Start it:"
echo "     PORT=5000 bash start_flashtm8_ultimate.sh"
echo ""
echo "  2) Open:"
echo "     http://127.0.0.1:5000"
echo ""
echo "  3) Click Index Workspace"
echo ""
echo "Keys file:"
echo "  $ENVFILE"
echo ""
