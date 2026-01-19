#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
ENVFILE="$APP/.env"

APP_PY="$BACK/app.py"
PROVIDERS_PY="$BACK/ai_providers.py"
INDEX_PY="$BACK/workspace_index.py"

JS="$BACK/static/app.js"
CSS="$BACK/static/style.css"
HTML="$BACK/templates/index.html"

START="$REPO/start_flashtm8.sh"
RUNNER="$APP/run_flashtm8.sh"

mkdir -p "$BACK/static" "$BACK/templates" "$APP/runtime"

echo "✅ Repo: $REPO"
echo "✅ Upgrading FlashTM8 dashboard + backend + env compatibility..."

# ---------------------------------------------------------
# 1) Fix requests/urllib3/six compatibility (Termux)
# ---------------------------------------------------------
echo "✅ Fixing python requests/urllib3/six (Termux safe)..."
python -m pip install --upgrade --force-reinstall "requests>=2.32.3" "urllib3>=2.2.0" six >/dev/null 2>&1 || true
echo "✅ requests/urllib3 fixed"

# ---------------------------------------------------------
# 2) Make .env SOURCE-SAFE (quote secrets with spaces)
# ---------------------------------------------------------
echo "✅ Making .env safe for bash 'source' (auto-quote spaces)..."

touch "$ENVFILE"

python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/.env")
txt = p.read_text(errors="ignore") if p.exists() else ""

out = []
seen = set()

def quote_if_needed(val: str) -> str:
    v = val.strip()
    if not v:
        return '""'
    # already quoted?
    if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
        return v
    # needs quoting (spaces or special chars)
    if re.search(r"\s", v):
        # single quote safe wrap (escape existing single quotes)
        v = v.replace("'", "'\"'\"'")
        return f"'{v}'"
    return v

for raw in txt.splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if "=" not in line:
        continue

    k, v = line.split("=", 1)
    k = k.strip()
    v = v.strip()

    if not k or k in seen:
        continue

    seen.add(k)
    out.append(f"{k}={quote_if_needed(v)}")

def upsert(key, value):
    nonlocal_out = []
    found = False
    for r in out:
        if r.startswith(key + "="):
            nonlocal_out.append(f'{key}="{value}"')
            found = True
        else:
            nonlocal_out.append(r)
    if not found:
        nonlocal_out.append(f'{key}="{value}"')
    return nonlocal_out

# Force stable defaults (does NOT remove your keys)
out = upsert("HOST", "0.0.0.0")
out = upsert("PORT", "5000")
out = upsert("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")

# AUTO provider chain
out = upsert("AI_PROVIDER", "auto")

# Safety toggles (prevent damage unless you enable)
out = upsert("ENABLE_EXEC", "0")
out = upsert("ENABLE_WRITE", "0")

p.write_text("\n".join(out).strip() + "\n")
print("✅ .env is now source-safe + AI_PROVIDER=auto")
PY

# ---------------------------------------------------------
# 3) Write ai_providers.py (AUTO chain with JSON response)
# ---------------------------------------------------------
echo "✅ Installing AI provider AUTO chain..."

cat <<'PY' > "$PROVIDERS_PY"
import os
import json
import time
import requests

def _env(k: str, default: str = "") -> str:
    return os.environ.get(k, default) or default

def _has(k: str) -> bool:
    return bool(_env(k, "").strip())

def _ok(provider: str, reply: str) -> dict:
    return {"ok": True, "provider": provider, "reply": reply}

def _fail(provider: str, err: str) -> dict:
    return {"ok": False, "provider": provider, "reply": "", "error": err}

def _openai_chat(message: str, context: dict | None = None) -> dict:
    # Works only if OPENAI_API_KEY is valid and has quota
    api_key = _env("OPENAI_API_KEY")
    if not api_key:
        return _fail("openai", "missing OPENAI_API_KEY")

    model = _env("OPENAI_MODEL", "gpt-4o-mini")
    url = "https://api.openai.com/v1/chat/completions"

    sys = "You are FlashTM8 ⚡. You are a workspace-aware assistant. Use the indexed workspace context when provided."
    ctx = context or {}
    extra = ""
    if isinstance(ctx, dict) and ctx.get("workspace_summary"):
        extra = "\n\nWORKSPACE CONTEXT:\n" + str(ctx["workspace_summary"])[:12000]

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": sys + extra},
            {"role": "user", "content": message},
        ],
        "temperature": 0.2,
    }

    try:
        r = requests.post(
            url,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            data=json.dumps(payload),
            timeout=30,
        )
        if r.status_code != 200:
            return _fail("openai", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        reply = data["choices"][0]["message"]["content"]
        return _ok("openai", reply)
    except Exception as e:
        return _fail("openai", str(e))

def _gemini_chat(message: str, context: dict | None = None) -> dict:
    # Basic Gemini REST
    api_key = _env("GEMINI_API_KEY")
    if not api_key:
        return _fail("gemini", "missing GEMINI_API_KEY")

    model = _env("GEMINI_MODEL", "gemini-1.5-flash")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"

    ctx = context or {}
    extra = ""
    if isinstance(ctx, dict) and ctx.get("workspace_summary"):
        extra = "\n\nWORKSPACE CONTEXT:\n" + str(ctx["workspace_summary"])[:12000]

    payload = {
        "contents": [{"parts": [{"text": f"You are FlashTM8 ⚡.{extra}\n\nUser: {message}"}]}]
    }

    try:
        r = requests.post(url, json=payload, timeout=30)
        if r.status_code != 200:
            return _fail("gemini", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        reply = data["candidates"][0]["content"]["parts"][0]["text"]
        return _ok("gemini", reply)
    except Exception as e:
        return _fail("gemini", str(e))

def _deepseek_chat(message: str, context: dict | None = None) -> dict:
    # DeepSeek OpenAI-compatible endpoint (common pattern)
    api_key = _env("DEEPSEEK_API_KEY")
    if not api_key:
        return _fail("deepseek", "missing DEEPSEEK_API_KEY")

    base = _env("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
    model = _env("DEEPSEEK_MODEL", "deepseek-chat")
    url = base.rstrip("/") + "/v1/chat/completions"

    ctx = context or {}
    extra = ""
    if isinstance(ctx, dict) and ctx.get("workspace_summary"):
        extra = "\n\nWORKSPACE CONTEXT:\n" + str(ctx["workspace_summary"])[:12000]

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are FlashTM8 ⚡." + extra},
            {"role": "user", "content": message},
        ],
        "temperature": 0.2,
    }

    try:
        r = requests.post(
            url,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            data=json.dumps(payload),
            timeout=30,
        )
        if r.status_code != 200:
            return _fail("deepseek", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        reply = data["choices"][0]["message"]["content"]
        return _ok("deepseek", reply)
    except Exception as e:
        return _fail("deepseek", str(e))

def _ollama_chat(message: str, context: dict | None = None) -> dict:
    base = _env("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    model = _env("OLLAMA_MODEL", "llama3.1")
    url = base.rstrip("/") + "/api/generate"

    ctx = context or {}
    extra = ""
    if isinstance(ctx, dict) and ctx.get("workspace_summary"):
        extra = "\n\nWORKSPACE CONTEXT:\n" + str(ctx["workspace_summary"])[:12000]

    prompt = f"You are FlashTM8 ⚡.\n{extra}\n\nUser: {message}\nAssistant:"

    try:
        r = requests.post(url, json={"model": model, "prompt": prompt, "stream": False}, timeout=60)
        if r.status_code != 200:
            return _fail("ollama", f"HTTP {r.status_code}: {r.text[:400]}")
        data = r.json()
        return _ok("ollama", data.get("response", "").strip())
    except Exception as e:
        return _fail("ollama", str(e))

def generate_reply(message: str, context: dict | None = None):
    """
    Returns: (provider_used, reply_text)
    """
    provider = _env("AI_PROVIDER", "auto").strip().lower() or "auto"

    # Provider order
    chain = []
    if provider == "auto":
        chain = ["openai", "gemini", "deepseek", "ollama", "fallback"]
    else:
        chain = [provider]

    last_err = None

    for p in chain:
        if p == "openai":
            res = _openai_chat(message, context=context)
        elif p == "gemini":
            res = _gemini_chat(message, context=context)
        elif p == "deepseek":
            res = _deepseek_chat(message, context=context)
        elif p == "ollama":
            res = _ollama_chat(message, context=context)
        elif p == "fallback":
            res = _ok("fallback", "FlashTM8 is running ✅\n\nAI provider not reachable now, but workspace tools + indexing still work.")
        else:
            res = _fail(p, "unknown provider")

        if res.get("ok"):
            return res.get("provider", p), str(res.get("reply", "")).strip()

        last_err = res.get("error") or str(res)

    return "fallback", f"FlashTM8 fallback ✅\nLast error: {last_err}"

def chat(message: str, context: dict | None = None) -> dict:
    prov, reply = generate_reply(message, context=context)
    return {"ok": True, "provider": prov, "reply": reply}
PY

# ---------------------------------------------------------
# 4) Write stable backend app.py (always JSON)
# ---------------------------------------------------------
echo "✅ Installing stable FlashTM8 backend API..."

cat <<'PY' > "$APP_PY"
import os
import traceback
from flask import Flask, request, jsonify, render_template

from ai_providers import chat as ai_chat
import workspace_index

def _env(k: str, d: str = "") -> str:
    return os.environ.get(k, d) or d

def create_app() -> Flask:
    app = Flask(
        __name__,
        template_folder=os.path.join(os.path.dirname(__file__), "templates"),
        static_folder=os.path.join(os.path.dirname(__file__), "static"),
    )

    @app.get("/")
    def home():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        return jsonify({
            "ok": True,
            "name": "FlashTM8",
            "provider": _env("AI_PROVIDER", "auto"),
            "workspace": _env("WORKSPACE_ROOT", os.getcwd()),
        })

    @app.post("/api/index")
    def api_index():
        root = _env("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")
        try:
            out = workspace_index.index_workspace(root)
            return jsonify({"ok": True, "files": out.get("files", 0), "db": out.get("db")})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500

    @app.post("/api/search")
    def api_search():
        data = request.get_json(silent=True) or {}
        q = (data.get("query") or "").strip()
        root = _env("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")
        if not q:
            return jsonify({"ok": False, "error": "query is empty"}), 400
        try:
            results = workspace_index.search(q, root=root)
            return jsonify({"ok": True, "results": results})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500

    @app.post("/api/chat")
    def api_chat():
        data = request.get_json(silent=True) or {}
        msg = (data.get("message") or "").strip()
        if not msg:
            return jsonify({"ok": False, "error": "message is empty"}), 400

        root = _env("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")
        summary = workspace_index.workspace_summary(root)

        try:
            res = ai_chat(msg, context={"workspace_summary": summary})
            if isinstance(res, dict):
                return jsonify(res)
            return jsonify({"ok": True, "provider": _env("AI_PROVIDER", "auto"), "reply": str(res)})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500

    @app.errorhandler(Exception)
    def err_all(e):
        return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500

    return app

def main():
    app = create_app()
    host = _env("HOST", "0.0.0.0")
    port = int(_env("PORT", "5000"))
    app.run(host=host, port=port, debug=False)

if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------
# 5) Workspace index system (fast + safe)
# ---------------------------------------------------------
echo "✅ Installing workspace indexer..."

cat <<'PY' > "$INDEX_PY"
import os
import sqlite3
import time
import hashlib

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "runtime", "index.db")

EXCLUDE_DIRS = {
    ".git", ".venv", "__pycache__", "node_modules", "dist", "build",
    "archive/patch_backups", "archive/legacy_patches", "apps/dashboard/frontend/dist",
}

def _is_excluded(path: str) -> bool:
    p = path.replace("\\", "/")
    for x in EXCLUDE_DIRS:
        if x in p:
            return True
    return False

def _hash_text(txt: str) -> str:
    return hashlib.sha256(txt.encode("utf-8", errors="ignore")).hexdigest()[:16]

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

def index_workspace(root: str) -> dict:
    root = os.path.abspath(root)
    c = _conn()
    files = 0
    for dirpath, dirnames, filenames in os.walk(root):
        if _is_excluded(dirpath):
            dirnames[:] = []
            continue

        for fn in filenames:
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root).replace("\\", "/")

            # only index useful files
            if not any(rel.endswith(x) for x in [".py",".sh",".md",".txt",".json",".toml",".yaml",".yml",".js",".ts",".tsx",".css",".html"]):
                continue

            try:
                st = os.stat(p)
                size = st.st_size
                mtime = st.st_mtime
                if size > 350_000:
                    continue

                txt = ""
                try:
                    with open(p, "r", encoding="utf-8", errors="ignore") as f:
                        txt = f.read()
                except Exception:
                    txt = ""

                sha = _hash_text(txt[:25000])
                c.execute("INSERT OR REPLACE INTO files(path,size,mtime,sha,text) VALUES(?,?,?,?,?)",
                          (rel, size, mtime, sha, txt[:25000]))
                files += 1
            except Exception:
                continue

    c.commit()
    c.close()
    return {"ok": True, "files": files, "db": DB_PATH}

def workspace_summary(root: str) -> str:
    root = os.path.abspath(root)
    c = _conn()
    cur = c.execute("SELECT path FROM files ORDER BY path LIMIT 200")
    paths = [r[0] for r in cur.fetchall()]
    c.close()
    return "Indexed files (sample):\n" + "\n".join(paths)

def search(query: str, root: str | None = None, limit: int = 25):
    q = query.strip().lower()
    if not q:
        return []
    c = _conn()
    cur = c.execute("SELECT path, text FROM files")
    hits = []
    for path, text in cur.fetchall():
        t = (text or "").lower()
        if q in path.lower() or q in t:
            # small snippet
            idx = t.find(q)
            snippet = ""
            if idx >= 0:
                snippet = text[max(0, idx-80): idx+160].replace("\n"," ")
            hits.append({"path": path, "snippet": snippet[:280]})
            if len(hits) >= limit:
                break
    c.close()
    return hits
PY

# ---------------------------------------------------------
# 6) Upgrade UI files (clean + compatible + status)
# ---------------------------------------------------------
echo "✅ Updating FlashTM8 frontend UI..."

cat <<'HTML' > "$HTML"
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>FlashTM8 ⚡</title>
  <link rel="stylesheet" href="/static/style.css" />
</head>
<body>
  <div class="wrap">
    <header class="top">
      <div class="logo">⚡ FlashTM8</div>
      <div class="sub">AI Sovereign Console • Workspace-Aware Assistant</div>
      <div class="status" id="status">Starting…</div>
    </header>

    <main class="grid">
      <section class="card">
        <h2>Tools</h2>
        <button id="btnHealth">Health</button>
        <button id="btnIndex">Index Workspace</button>
        <div class="small" id="indexInfo">Not indexed yet.</div>

        <h3>Search</h3>
        <input id="searchQ" placeholder="server port, bot token, run.sh..." />
        <button id="btnSearch">Search</button>
        <pre id="searchOut"></pre>
      </section>

      <section class="card chat">
        <h2>Chat</h2>
        <div class="small">Ask about files, bugs, features, next steps.</div>
        <div id="chatlog" class="chatlog"></div>
        <div class="row">
          <input id="msg" placeholder="Ask FlashTM8..." />
          <button id="send">Send</button>
        </div>
        <div class="small muted" id="providerInfo"></div>
      </section>
    </main>

    <footer class="foot">
      FlashTM8 • Built for 8x8org
    </footer>
  </div>

  <script src="/static/app.js"></script>
</body>
</html>
HTML

cat <<'CSS' > "$CSS"
:root{--bg:#0b0f14;--card:#111827;--muted:#9ca3af;--text:#e5e7eb;--btn:#1f2937;--btn2:#2563eb;}
*{box-sizing:border-box;font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial;}
body{margin:0;background:var(--bg);color:var(--text);}
.wrap{max-width:1100px;margin:0 auto;padding:16px;}
.top{display:flex;flex-direction:column;gap:6px;margin-bottom:16px;}
.logo{font-size:28px;font-weight:800;}
.sub{color:var(--muted);}
.status{padding:8px 10px;border-radius:10px;background:#0f172a;display:inline-block;width:max-content}
.grid{display:grid;grid-template-columns:340px 1fr;gap:14px;}
.card{background:var(--card);border:1px solid #1f2937;border-radius:16px;padding:14px;box-shadow:0 10px 24px rgba(0,0,0,.2);}
.card h2{margin:0 0 10px 0;}
.card h3{margin:14px 0 8px 0;color:#cbd5e1;}
.small{color:var(--muted);font-size:13px;margin-top:8px;}
.muted{opacity:.85}
button{background:var(--btn);color:var(--text);border:1px solid #2b3342;border-radius:12px;padding:10px 12px;cursor:pointer;margin-right:8px;margin-top:8px;}
button:hover{border-color:#3b82f6}
input{width:100%;background:#0f172a;color:var(--text);border:1px solid #243042;border-radius:12px;padding:10px 12px;margin-top:8px;}
pre{white-space:pre-wrap;background:#0f172a;border:1px solid #243042;border-radius:12px;padding:10px;min-height:120px;max-height:260px;overflow:auto;}
.chat{display:flex;flex-direction:column;min-height:520px;}
.chatlog{flex:1;background:#0f172a;border:1px solid #243042;border-radius:12px;padding:10px;margin-top:10px;overflow:auto;}
.msg{margin:8px 0;padding:10px;border-radius:12px;}
.me{background:#1f2937}
.ai{background:#111827;border:1px solid #243042}
.row{display:flex;gap:10px;margin-top:10px;}
.row input{flex:1;margin-top:0;}
.foot{color:var(--muted);margin-top:16px;text-align:center;font-size:13px;}
@media(max-width:900px){.grid{grid-template-columns:1fr}}
CSS

cat <<'JS' > "$JS"
async function postJSON(url, body){
  const res = await fetch(url, {
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body: JSON.stringify(body || {})
  });

  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch(e){
    // If backend crashed and returned HTML, show it
    throw new Error("Non-JSON response: " + text.slice(0,160));
  }
}

function addMsg(cls, txt){
  const log = document.getElementById("chatlog");
  const div = document.createElement("div");
  div.className = "msg " + cls;
  div.textContent = txt;
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}

async function health(){
  const r = await fetch("/api/health");
  const t = await r.text();
  try {
    const j = JSON.parse(t);
    document.getElementById("status").textContent = "✅ Online • Provider: " + j.provider;
    return j;
  } catch(e){
    document.getElementById("status").textContent = "⚠️ Health parse error";
    return null;
  }
}

async function indexWorkspace(){
  document.getElementById("indexInfo").textContent = "Indexing...";
  const res = await postJSON("/api/index", {});
  if(res.ok){
    document.getElementById("indexInfo").textContent = "✅ Indexed " + res.files + " files.";
  }else{
    document.getElementById("indexInfo").textContent = "❌ " + (res.error || "index failed");
  }
}

async function searchIndex(){
  const q = document.getElementById("searchQ").value.trim();
  if(!q) return;
  const out = document.getElementById("searchOut");
  out.textContent = "Searching...";
  const res = await postJSON("/api/search", {query:q});
  if(res.ok){
    out.textContent = JSON.stringify(res.results, null, 2);
  } else {
    out.textContent = "Error: " + (res.error || "failed");
  }
}

async function chat(){
  const box = document.getElementById("msg");
  const m = box.value.trim();
  if(!m) return;
  box.value = "";
  addMsg("me", "You: " + m);

  try{
    const res = await postJSON("/api/chat", {message:m});
    if(res.ok){
      addMsg("ai", "FlashTM8 (" + (res.provider || "auto") + "): " + res.reply);
      document.getElementById("providerInfo").textContent = "Provider used: " + (res.provider || "auto");
    } else {
      addMsg("ai", "Error: " + (res.error || "Unknown"));
    }
  }catch(e){
    addMsg("ai", "Request failed: " + e.message);
  }
}

document.getElementById("btnHealth").onclick = health;
document.getElementById("btnIndex").onclick = indexWorkspace;
document.getElementById("btnSearch").onclick = searchIndex;
document.getElementById("send").onclick = chat;
document.getElementById("msg").addEventListener("keydown", (e)=>{ if(e.key==="Enter"){ chat(); } });

health();
JS

# ---------------------------------------------------------
# 7) Fix start scripts: always bash, always PORT=5000
# ---------------------------------------------------------
echo "✅ Creating start scripts..."

cat <<'SH' > "$RUNNER"
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
source ".env"
set +a
cd backend
exec python app.py
SH

cat <<'SH' > "$START"
#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"

cd "$REPO"

echo "==============================================="
echo "⚡ FlashTM8 AI Dashboard"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "   Workspace: ${WORKSPACE_ROOT:-$REPO}"
echo "   URL: http://127.0.0.1:${PORT:-5000}"
echo "==============================================="

PORT="${PORT:-5000}"
export PORT

bash "$APP/run_flashtm8.sh"
SH

chmod +x "$RUNNER" "$START" 2>/dev/null || true

# ---------------------------------------------------------
# 8) Final compile check
# ---------------------------------------------------------
echo "✅ Checking python syntax..."
python -m py_compile "$APP_PY" "$PROVIDERS_PY" "$INDEX_PY"

echo ""
echo "✅ FlashTM8 UPGRADE COMPLETE!"
echo "Run:"
echo "  cd $REPO"
echo "  set -a; source $ENVFILE; set +a"
echo "  PORT=5000 bash start_flashtm8.sh"
echo ""
