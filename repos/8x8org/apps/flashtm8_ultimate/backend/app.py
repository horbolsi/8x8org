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
