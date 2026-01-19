#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

echo "==============================================="
echo "⚡ Termux Sovereign Console Setup (UVLOOP SAFE)"
echo "==============================================="

# -----------------------------
# 1) System packages
# -----------------------------
echo ""
echo "✅ Updating Termux packages..."
pkg update -y && pkg upgrade -y

echo ""
echo "✅ Installing core tools..."
pkg install -y \
  python git openssh curl wget unzip zip tar \
  clang make cmake ninja pkg-config \
  nodejs-lts sqlite jq ripgrep fd tree tmux htop procps openssl libffi

# -----------------------------
# 2) Python venv
# -----------------------------
VENV="$HOME/.venvs/sovereign-ai"
echo ""
echo "✅ Creating Python venv: $VENV"
mkdir -p "$(dirname "$VENV")"
python -m venv "$VENV"

# shellcheck disable=SC1091
source "$VENV/bin/activate"

echo ""
echo "✅ Upgrading pip tools (Termux safe)..."
python -m pip install -U wheel setuptools

# -----------------------------
# 3) Install python deps (NO uvicorn[standard], NO uvloop)
# -----------------------------
echo ""
echo "✅ Installing Python packages (Termux-safe, no uvloop)..."

python -m pip install -U \
  fastapi \
  uvicorn \
  jinja2 \
  python-multipart \
  aiofiles \
  websockets \
  psutil \
  watchdog \
  rich \
  python-dotenv \
  requests \
  gitpython \
  httptools \
  pyyaml \
  watchfiles

echo ""
echo "✅ Python deps installed successfully (uvloop skipped)."

# -----------------------------
# 4) Build Ultimate Dashboard (workspace console)
# -----------------------------
REPO="${PWD}"
APP_DIR="$REPO/apps/sovereign_console"
BACKEND="$APP_DIR/backend"
STATIC="$BACKEND/static"
TEMPLATES="$BACKEND/templates"
RUNTIME="$APP_DIR/runtime"

echo ""
echo "==============================================="
echo "⚡ Building Ultimate Sovereign Dev Dashboard"
echo "==============================================="

mkdir -p "$BACKEND" "$STATIC" "$TEMPLATES" "$RUNTIME"

# -----------------------------
# .env (NO secrets embedded)
# -----------------------------
cat <<'ENV' > "$APP_DIR/.env"
# ===========================
# ⚡ Sovereign Console Config
# ===========================

# Server
PORT=5000
WORKSPACE_ROOT=.

# Security
SESSION_SECRET=change-me

# AI provider selection:
# auto = llama.cpp -> ollama -> cloud -> fallback
AI_PROVIDER=auto

# Local llama.cpp server endpoint (llama-server)
LLAMA_CPP_URL=http://127.0.0.1:8080

# Ollama endpoint (optional)
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.1:8b

# Cloud keys (optional)
OPENAI_API_KEY=
GEMINI_API_KEY=
DEEPSEEK_API_KEY=

# Permissions (SAFE DEFAULTS)
EXEC_ENABLED=false
WRITE_ENABLED=false

# Runtime
LOG_FILE=apps/sovereign_console/runtime/console.log
INDEX_DB=apps/sovereign_console/runtime/index.db
ENV

# -----------------------------
# backend/providers.py
# -----------------------------
cat <<'PY' > "$BACKEND/providers.py"
import os, json, requests

def _env(k, d=""):
    return os.getenv(k, d)

def _ok(provider, reply):
    return {"ok": True, "provider": provider, "reply": reply}

def _fail(provider, err):
    return {"ok": False, "provider": provider, "error": err}

def chat_llama_cpp(prompt: str) -> dict:
    """
    llama.cpp server API (llama-server):
      POST /completion {"prompt": "...", "n_predict": 256}
    """
    base = _env("LLAMA_CPP_URL", "http://127.0.0.1:8080").rstrip("/")
    url = f"{base}/completion"
    try:
        r = requests.post(url, json={"prompt": prompt, "n_predict": 256}, timeout=30)
        if r.status_code != 200:
            return _fail("llama.cpp", f"HTTP {r.status_code}: {r.text[:300]}")
        data = r.json()
        text = data.get("content") or data.get("completion") or ""
        if not text:
            text = json.dumps(data)[:600]
        return _ok("llama.cpp", text.strip())
    except Exception as e:
        return _fail("llama.cpp", str(e))

def chat_ollama(prompt: str) -> dict:
    base = _env("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
    model = _env("OLLAMA_MODEL", "llama3.1:8b")
    url = f"{base}/api/generate"
    try:
        r = requests.post(url, json={"model": model, "prompt": prompt, "stream": False}, timeout=30)
        if r.status_code != 200:
            return _fail("ollama", f"HTTP {r.status_code}: {r.text[:300]}")
        data = r.json()
        return _ok("ollama", (data.get("response") or "").strip())
    except Exception as e:
        return _fail("ollama", str(e))

def chat_openai(prompt: str) -> dict:
    key = _env("OPENAI_API_KEY", "").strip()
    if not key:
        return _fail("openai", "OPENAI_API_KEY missing")
    try:
        url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        payload = {
            "model": _env("OPENAI_MODEL", "gpt-4o-mini"),
            "messages": [
                {"role": "system", "content": "You are FlashTM8-like assistant tied to a local workspace. Be concise and practical."},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
        }
        r = requests.post(url, headers=headers, json=payload, timeout=30)
        if r.status_code != 200:
            return _fail("openai", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        text = data["choices"][0]["message"]["content"]
        return _ok("openai", text.strip())
    except Exception as e:
        return _fail("openai", str(e))

def chat_deepseek(prompt: str) -> dict:
    key = _env("DEEPSEEK_API_KEY", "").strip()
    if not key:
        return _fail("deepseek", "DEEPSEEK_API_KEY missing")
    try:
        url = _env("DEEPSEEK_BASE_URL", "https://api.deepseek.com/v1/chat/completions")
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        payload = {
            "model": _env("DEEPSEEK_MODEL", "deepseek-chat"),
            "messages": [
                {"role": "system", "content": "You are a workspace-aware assistant. Answer using repository context tools."},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
        }
        r = requests.post(url, headers=headers, json=payload, timeout=30)
        if r.status_code != 200:
            return _fail("deepseek", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        text = data["choices"][0]["message"]["content"]
        return _ok("deepseek", text.strip())
    except Exception as e:
        return _fail("deepseek", str(e))

def fallback_reply(prompt: str) -> dict:
    return _ok(
        "fallback",
        "FlashTM8 is running ✅ No AI provider reachable right now.\n"
        "But workspace indexing/search/tools still work.\n\n"
        "Try: Index Workspace → then Search or Read files."
    )

def generate_reply(prompt: str) -> dict:
    """
    Provider chain:
      llama.cpp -> ollama -> openai -> deepseek -> fallback
    """
    mode = _env("AI_PROVIDER", "auto").strip().lower()

    if mode == "llama.cpp":
        return chat_llama_cpp(prompt)
    if mode == "ollama":
        return chat_ollama(prompt)
    if mode == "openai":
        return chat_openai(prompt)
    if mode == "deepseek":
        return chat_deepseek(prompt)
    if mode == "fallback":
        return fallback_reply(prompt)

    # AUTO chain
    for fn in (chat_llama_cpp, chat_ollama, chat_openai, chat_deepseek):
        res = fn(prompt)
        if res.get("ok"):
            return res
    return fallback_reply(prompt)
PY

# -----------------------------
# backend/tools.py
# -----------------------------
cat <<'PY' > "$BACKEND/tools.py"
import os, subprocess, sqlite3
from pathlib import Path

def root() -> Path:
    return Path(os.getenv("WORKSPACE_ROOT", ".")).resolve()

def safe_rel(p: Path) -> str:
    try:
        return str(p.relative_to(root()))
    except Exception:
        return str(p)

def index_db_path() -> Path:
    return Path(os.getenv("INDEX_DB", "apps/sovereign_console/runtime/index.db")).resolve()

def ensure_db():
    db = index_db_path()
    db.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db)
    cur = con.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS files(
        path TEXT PRIMARY KEY,
        size INTEGER,
        mtime INTEGER
    )""")
    con.commit()
    con.close()

def index_workspace(max_files: int = 5000):
    ensure_db()
    base = root()
    files = []
    for p in base.rglob("*"):
        if p.is_file():
            sp = str(p)
            if "/.git/" in sp or "/node_modules/" in sp or "/.venv/" in sp or "/__pycache__/" in sp:
                continue
            files.append(p)
            if len(files) >= max_files:
                break

    con = sqlite3.connect(index_db_path())
    cur = con.cursor()
    n = 0
    for f in files:
        st = f.stat()
        cur.execute(
            "INSERT OR REPLACE INTO files(path,size,mtime) VALUES(?,?,?)",
            (safe_rel(f), int(st.st_size), int(st.st_mtime)),
        )
        n += 1
    con.commit()
    con.close()
    return {"ok": True, "count": n}

def search_workspace(query: str, limit: int = 50):
    if not query.strip():
        return {"ok": True, "results": []}
    base = root()
    cmd = ["rg", "-n", "--no-heading", "--smart-case", query, str(base)]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=20).decode("utf-8", "ignore")
    except subprocess.CalledProcessError as e:
        out = e.output.decode("utf-8", "ignore")
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "results": out.splitlines()[:limit]}

def read_file(rel_path: str, max_bytes: int = 200_000):
    p = root() / rel_path
    if not p.exists() or not p.is_file():
        return {"ok": False, "error": "File not found"}
    data = p.read_bytes()[:max_bytes]
    return {"ok": True, "path": rel_path, "content": data.decode("utf-8", "ignore")}

def exec_cmd(cmd: str, timeout: int = 25):
    if os.getenv("EXEC_ENABLED", "false").lower() != "true":
        return {"ok": False, "error": "EXEC disabled. Enable EXEC_ENABLED=true in Settings."}
    try:
        proc = subprocess.run(
            cmd, shell=True, cwd=str(root()),
            timeout=timeout, capture_output=True, text=True
        )
        return {"ok": True, "code": proc.returncode, "stdout": proc.stdout[-20000:], "stderr": proc.stderr[-20000:]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def write_file(rel_path: str, content: str):
    if os.getenv("WRITE_ENABLED", "false").lower() != "true":
        return {"ok": False, "error": "WRITE disabled. Enable WRITE_ENABLED=true in Settings."}
    p = root() / rel_path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8", errors="ignore")
    return {"ok": True, "path": rel_path}

def metrics():
    try:
        import psutil
        du = psutil.disk_usage(str(root()))
        vm = psutil.virtual_memory()
        return {"ok": True,
                "cpu_percent": psutil.cpu_percent(interval=0.3),
                "mem_percent": vm.percent,
                "disk_percent": du.percent,
                "disk_free_gb": round(du.free/(1024**3), 2)}
    except Exception as e:
        return {"ok": False, "error": str(e)}
PY

# -----------------------------
# backend/app.py
# -----------------------------
cat <<'PY' > "$BACKEND/app.py"
import os
from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

from providers import generate_reply
import tools

APP_ROOT = Path(__file__).resolve().parent
TEMPLATES = APP_ROOT / "templates"
STATIC = APP_ROOT / "static"

def load_env():
    env_file = (APP_ROOT.parent / ".env").resolve()
    if env_file.exists():
        load_dotenv(env_file)

load_env()
app = FastAPI(title="⚡ Sovereign Console")
app.mount("/static", StaticFiles(directory=str(STATIC)), name="static")

def html_template() -> str:
    return (TEMPLATES / "index.html").read_text(encoding="utf-8", errors="ignore")

@app.get("/", response_class=HTMLResponse)
async def home():
    return HTMLResponse(content=html_template())

@app.get("/api/health")
async def health():
    return {
        "ok": True,
        "provider": os.getenv("AI_PROVIDER", "auto"),
        "workspace": os.getenv("WORKSPACE_ROOT", "."),
        "exec_enabled": os.getenv("EXEC_ENABLED", "false"),
        "write_enabled": os.getenv("WRITE_ENABLED", "false"),
    }

@app.post("/api/index")
async def do_index():
    return JSONResponse(tools.index_workspace())

@app.get("/api/search")
async def do_search(q: str = ""):
    return JSONResponse(tools.search_workspace(q))

@app.get("/api/read")
async def do_read(path: str = ""):
    return JSONResponse(tools.read_file(path))

@app.post("/api/exec")
async def do_exec(req: Request):
    data = await req.json()
    return JSONResponse(tools.exec_cmd(data.get("cmd", "")))

@app.post("/api/write")
async def do_write(req: Request):
    data = await req.json()
    return JSONResponse(tools.write_file(data.get("path", ""), data.get("content", "")))

@app.get("/api/metrics")
async def do_metrics():
    return JSONResponse(tools.metrics())

@app.post("/api/chat")
async def do_chat(req: Request):
    data = await req.json()
    msg = (data.get("message") or "").strip()
    if not msg:
        return JSONResponse({"ok": False, "error": "Empty message"})
    return JSONResponse(generate_reply(msg))
PY

# -----------------------------
# frontend HTML
# -----------------------------
cat <<'HTML' > "$TEMPLATES/index.html"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>⚡ Sovereign Console</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <div class="topbar">
    <div class="brand">⚡ Sovereign Console</div>
    <div class="status" id="status">Loading...</div>
  </div>

  <div class="grid">
    <div class="sidebar">
      <button class="tabbtn active" data-tab="chat">Chat</button>
      <button class="tabbtn" data-tab="terminal">Terminal</button>
      <button class="tabbtn" data-tab="files">Files</button>
      <button class="tabbtn" data-tab="search">Search</button>
      <button class="tabbtn" data-tab="monitor">Monitor</button>
      <button class="tabbtn" data-tab="settings">Settings</button>
      <div class="actions">
        <button id="btnIndex" class="ghost">Index Workspace</button>
      </div>
    </div>

    <div class="main">
      <div class="panel active" id="tab-chat">
        <div class="panelTitle">⚡ Chat (Workspace-Aware)</div>
        <div class="chatbox" id="chatbox"></div>
        <div class="row">
          <input id="chatInput" placeholder="Ask anything about your workspace..." />
          <button id="sendChat">Send</button>
        </div>
        <div class="hint">Provider used: <span id="providerUsed">auto</span></div>
      </div>

      <div class="panel" id="tab-terminal">
        <div class="panelTitle">🖥 Terminal Exec (safe)</div>
        <div class="row">
          <input id="cmdInput" placeholder="ex: ls -la" />
          <button id="runCmd">Run</button>
        </div>
        <pre class="out" id="cmdOut"></pre>
        <div class="hint">Exec is disabled by default → enable in Settings.</div>
      </div>

      <div class="panel" id="tab-files">
        <div class="panelTitle">📁 File Reader</div>
        <div class="row">
          <input id="filePath" placeholder="ex: README.md" />
          <button id="readFile">Read</button>
        </div>
        <pre class="out" id="fileOut"></pre>
      </div>

      <div class="panel" id="tab-search">
        <div class="panelTitle">🔎 Workspace Search</div>
        <div class="row">
          <input id="searchQ" placeholder="ex: TELEGRAM_BOT_TOKEN" />
          <button id="doSearch">Search</button>
        </div>
        <pre class="out" id="searchOut"></pre>
      </div>

      <div class="panel" id="tab-monitor">
        <div class="panelTitle">📊 System Monitor</div>
        <div class="cards">
          <div class="card"><div class="k">CPU</div><div class="v" id="cpu">-</div></div>
          <div class="card"><div class="k">Memory</div><div class="v" id="mem">-</div></div>
          <div class="card"><div class="k">Disk</div><div class="v" id="disk">-</div></div>
          <div class="card"><div class="k">Free (GB)</div><div class="v" id="free">-</div></div>
        </div>
        <button id="refreshMetrics" class="ghost">Refresh</button>
      </div>

      <div class="panel" id="tab-settings">
        <div class="panelTitle">⚙ Settings</div>
        <div class="form">
          <label>AI_PROVIDER</label>
          <select id="AI_PROVIDER">
            <option value="auto">auto (llama.cpp→ollama→cloud→fallback)</option>
            <option value="llama.cpp">llama.cpp</option>
            <option value="ollama">ollama</option>
            <option value="openai">openai</option>
            <option value="deepseek">deepseek</option>
            <option value="fallback">fallback</option>
          </select>

          <label>LLAMA_CPP_URL</label>
          <input id="LLAMA_CPP_URL" placeholder="http://127.0.0.1:8080" />

          <label>OLLAMA_BASE_URL</label>
          <input id="OLLAMA_BASE_URL" placeholder="http://127.0.0.1:11434" />

          <label>OPENAI_API_KEY</label>
          <input id="OPENAI_API_KEY" placeholder="sk-..." />

          <label>GEMINI_API_KEY</label>
          <input id="GEMINI_API_KEY" placeholder="AIza..." />

          <label>DEEPSEEK_API_KEY</label>
          <input id="DEEPSEEK_API_KEY" placeholder="sk-..." />

          <label>EXEC_ENABLED</label>
          <select id="EXEC_ENABLED">
            <option value="false">false (safe)</option>
            <option value="true">true (danger)</option>
          </select>

          <label>WRITE_ENABLED</label>
          <select id="WRITE_ENABLED">
            <option value="false">false (safe)</option>
            <option value="true">true (danger)</option>
          </select>

          <button id="saveKeys">Save</button>
          <div class="hint" id="saveMsg"></div>
        </div>
      </div>
    </div>
  </div>

  <script src="/static/app.js"></script>
</body>
</html>
HTML

# -----------------------------
# style.css
# -----------------------------
cat <<'CSS' > "$STATIC/style.css"
:root{
  --bg:#0b0f17; --card:#121a27; --muted:#7b8aa0; --text:#e8eefc;
  --accent:#7c5cff; --border:#223049; --ok:#22c55e; --bad:#ef4444;
}
*{box-sizing:border-box;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto;}
body{margin:0;background:var(--bg);color:var(--text);}
.topbar{display:flex;align-items:center;justify-content:space-between;padding:14px 16px;
border-bottom:1px solid var(--border);background:rgba(18,26,39,.9);position:sticky;top:0;z-index:9;}
.brand{font-weight:800;letter-spacing:.5px}
.status{font-size:12px;color:var(--muted)}
.grid{display:grid;grid-template-columns:220px 1fr;min-height:calc(100vh - 52px);}
.sidebar{border-right:1px solid var(--border);padding:12px;background:rgba(18,26,39,.4);}
.tabbtn{width:100%;padding:10px 12px;margin-bottom:8px;border-radius:12px;border:1px solid var(--border);
background:transparent;color:var(--text);cursor:pointer;text-align:left;}
.tabbtn.active{background:var(--card);border-color:rgba(124,92,255,.7)}
.actions{margin-top:10px;padding-top:10px;border-top:1px dashed var(--border)}
.ghost{width:100%;padding:10px 12px;border-radius:12px;border:1px dashed var(--border);
background:transparent;color:var(--muted);cursor:pointer}
.main{padding:16px}
.panel{display:none}
.panel.active{display:block}
.panelTitle{font-size:14px;color:var(--muted);margin-bottom:10px}
.row{display:flex;gap:10px}
input,select{flex:1;padding:10px;border-radius:12px;border:1px solid var(--border);
background:var(--card);color:var(--text);}
button{padding:10px 12px;border-radius:12px;border:1px solid rgba(124,92,255,.7);
background:rgba(124,92,255,.15);color:var(--text);cursor:pointer;}
.chatbox{height:52vh;overflow:auto;border:1px solid var(--border);border-radius:16px;padding:12px;
background:rgba(18,26,39,.3);margin-bottom:10px;}
.msg{padding:10px 12px;border-radius:16px;border:1px solid var(--border);margin-bottom:8px;white-space:pre-wrap}
.msg.user{border-color:rgba(124,92,255,.5)}
.msg.ai{border-color:rgba(34,197,94,.4)}
.out{height:52vh;overflow:auto;border:1px solid var(--border);border-radius:16px;padding:12px;
background:rgba(18,26,39,.3);white-space:pre-wrap;}
.hint{color:var(--muted);font-size:12px;margin-top:10px}
.cards{display:grid;grid-template-columns:repeat(2,minmax(160px,1fr));gap:10px;margin-bottom:12px}
.card{border:1px solid var(--border);border-radius:16px;background:rgba(18,26,39,.35);padding:12px}
.k{color:var(--muted);font-size:12px}
.v{font-size:18px;font-weight:800;margin-top:8px}
.form{display:grid;gap:10px;max-width:520px}
label{color:var(--muted);font-size:12px}
CSS

# -----------------------------
# app.js
# -----------------------------
cat <<'JS' > "$STATIC/app.js"
async function api(path, method="GET", body=null){
  const opt = {method, headers:{}};
  if(body){
    opt.headers["Content-Type"]="application/json";
    opt.body = JSON.stringify(body);
  }
  const r = await fetch(path, opt);
  const txt = await r.text();
  try{ return JSON.parse(txt); }
  catch(e){ return {ok:false,error:"Bad JSON response",raw:txt}; }
}

function addMsg(role, text){
  const box = document.getElementById("chatbox");
  const div = document.createElement("div");
  div.className = "msg " + (role==="user" ? "user" : "ai");
  div.textContent = text;
  box.appendChild(div);
  box.scrollTop = box.scrollHeight;
}

async function refreshHealth(){
  const h = await api("/api/health");
  const el = document.getElementById("status");
  if(h.ok){
    el.innerHTML = `✅ Online • Provider: <b>${h.provider}</b> • Exec=${h.exec_enabled} • Write=${h.write_enabled}`;
    document.getElementById("providerUsed").textContent = h.provider;
  }else{
    el.innerHTML = "❌ Offline";
  }
}

function tab(name){
  document.querySelectorAll(".tabbtn").forEach(b=>b.classList.remove("active"));
  document.querySelectorAll(".panel").forEach(p=>p.classList.remove("active"));
  document.querySelector(`[data-tab="${name}"]`).classList.add("active");
  document.getElementById("tab-"+name).classList.add("active");
}

document.querySelectorAll(".tabbtn").forEach(btn=>{
  btn.addEventListener("click", ()=>tab(btn.dataset.tab));
});

document.getElementById("sendChat").addEventListener("click", async ()=>{
  const input = document.getElementById("chatInput");
  const msg = input.value.trim();
  if(!msg) return;
  input.value="";
  addMsg("user", "You: " + msg);

  const res = await api("/api/chat","POST",{message:msg});
  if(res.ok){
    addMsg("ai", `FlashTM8 (${res.provider}): ${res.reply}`);
    document.getElementById("providerUsed").textContent = res.provider;
  }else{
    addMsg("ai", `Error: ${res.error || "Unknown"}\n${res.raw || ""}`);
  }
});

document.getElementById("runCmd").addEventListener("click", async ()=>{
  const cmd = document.getElementById("cmdInput").value.trim();
  if(!cmd) return;
  const res = await api("/api/exec","POST",{cmd});
  document.getElementById("cmdOut").textContent = JSON.stringify(res,null,2);
});

document.getElementById("readFile").addEventListener("click", async ()=>{
  const p = document.getElementById("filePath").value.trim();
  if(!p) return;
  const res = await api("/api/read?path="+encodeURIComponent(p));
  document.getElementById("fileOut").textContent = res.ok ? res.content : JSON.stringify(res,null,2);
});

document.getElementById("doSearch").addEventListener("click", async ()=>{
  const q = document.getElementById("searchQ").value.trim();
  const res = await api("/api/search?q="+encodeURIComponent(q));
  document.getElementById("searchOut").textContent = res.ok ? (res.results||[]).join("\\n") : JSON.stringify(res,null,2);
});

document.getElementById("btnIndex").addEventListener("click", async ()=>{
  const res = await api("/api/index","POST",{});
  addMsg("ai", "Index result: " + JSON.stringify(res));
});

document.getElementById("refreshMetrics").addEventListener("click", async ()=>{
  const m = await api("/api/metrics");
  if(m.ok){
    document.getElementById("cpu").textContent = m.cpu_percent+"%";
    document.getElementById("mem").textContent = m.mem_percent+"%";
    document.getElementById("disk").textContent = m.disk_percent+"%";
    document.getElementById("free").textContent = m.disk_free_gb;
  }
});

document.getElementById("saveKeys").addEventListener("click", async ()=>{
  const payload = {
    AI_PROVIDER: document.getElementById("AI_PROVIDER").value,
    LLAMA_CPP_URL: document.getElementById("LLAMA_CPP_URL").value,
    OLLAMA_BASE_URL: document.getElementById("OLLAMA_BASE_URL").value,
    OPENAI_API_KEY: document.getElementById("OPENAI_API_KEY").value,
    GEMINI_API_KEY: document.getElementById("GEMINI_API_KEY").value,
    DEEPSEEK_API_KEY: document.getElementById("DEEPSEEK_API_KEY").value,
    EXEC_ENABLED: document.getElementById("EXEC_ENABLED").value,
    WRITE_ENABLED: document.getElementById("WRITE_ENABLED").value,
  };
  const res = await api("/api/save_keys","POST",payload);
  document.getElementById("saveMsg").textContent = res.ok ? "✅ Saved. Restart for full reload." : "❌ Save failed.";
});

refreshHealth();
setInterval(refreshHealth, 6000);
JS

# -----------------------------
# start script (Termux-safe)
# -----------------------------
cat <<'SH' > "$REPO/start_sovereign_console.sh"
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
APP="$REPO/apps/sovereign_console"
ENVFILE="$APP/.env"

set -a
source "$ENVFILE"
set +a

PORT="${PORT:-5000}"

if [[ -f "$HOME/.venvs/sovereign-ai/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.venvs/sovereign-ai/bin/activate"
fi

cd "$APP/backend"
echo "==============================================="
echo "⚡ Sovereign Console Running"
echo "   URL: http://127.0.0.1:${PORT}"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "==============================================="
python -m uvicorn app:app --host 0.0.0.0 --port "$PORT"
SH

chmod +x "$REPO/start_sovereign_console.sh" 2>/dev/null || true

echo ""
echo "==============================================="
echo "✅ DONE"
echo ""
echo "Start:"
echo "  bash start_sovereign_console.sh"
echo ""
echo "Open:"
echo "  http://127.0.0.1:5000"
echo "==============================================="
