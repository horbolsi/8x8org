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

app = FastAPI(title="Sovereign Console")

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
    res = tools.index_workspace()
    return JSONResponse(res)

@app.get("/api/search")
async def do_search(q: str = ""):
    return JSONResponse(tools.search_workspace(q))

@app.get("/api/read")
async def do_read(path: str = ""):
    return JSONResponse(tools.read_file(path))

@app.post("/api/exec")
async def do_exec(req: Request):
    data = await req.json()
    cmd = data.get("cmd", "")
    return JSONResponse(tools.exec_cmd(cmd))

@app.post("/api/write")
async def do_write(req: Request):
    data = await req.json()
    path = data.get("path", "")
    content = data.get("content", "")
    return JSONResponse(tools.write_file(path, content))

@app.get("/api/metrics")
async def do_metrics():
    return JSONResponse(tools.metrics())

@app.post("/api/chat")
async def do_chat(req: Request):
    data = await req.json()
    msg = (data.get("message") or "").strip()
    if not msg:
        return JSONResponse({"ok": False, "error": "Empty message"})
    res = generate_reply(msg)
    return JSONResponse(res)

@app.post("/api/save_keys")
async def save_keys(req: Request):
    """
    Saves keys to apps/sovereign_console/.env (simple & local)
    """
    payload = await req.json()
    env_path = (APP_ROOT.parent / ".env").resolve()

    # Read existing lines
    lines = env_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    kv = {}
    for ln in lines:
        if "=" in ln and not ln.strip().startswith("#"):
            k, v = ln.split("=", 1)
            kv[k.strip()] = v.strip()

    # Apply updates (only known keys)
    allowed = [
        "AI_PROVIDER","LLAMA_CPP_URL","OLLAMA_BASE_URL",
        "OPENAI_API_KEY","GEMINI_API_KEY","DEEPSEEK_API_KEY",
        "EXEC_ENABLED","WRITE_ENABLED","WORKSPACE_ROOT","PORT",
        "SESSION_SECRET"
    ]
    for k in allowed:
        if k in payload:
            kv[k] = str(payload[k]).strip()

    # Rebuild file
    out = []
    for ln in lines:
        if "=" in ln and not ln.strip().startswith("#"):
            k = ln.split("=",1)[0].strip()
            if k in kv:
                out.append(f"{k}={kv[k]}")
            else:
                out.append(ln)
        else:
            out.append(ln)

    # Ensure keys exist even if missing
    for k in allowed:
        if k not in [l.split("=",1)[0].strip() for l in out if "=" in l and not l.strip().startswith("#")]:
            out.append(f"{k}={kv.get(k,'')}")
    env_path.write_text("\n".join(out) + "\n", encoding="utf-8", errors="ignore")

    return JSONResponse({"ok": True, "saved": True, "env": str(env_path)})
