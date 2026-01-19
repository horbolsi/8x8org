import os, json
from pathlib import Path
from flask import Flask, request, jsonify, render_template, send_from_directory

from dotenv import load_dotenv

# local imports
from workspace_index import index_workspace, search as search_index
from ai_providers import generate_reply
from tools import safe_exec, safe_write

HERE = Path(__file__).resolve().parent
APPROOT = HERE.parent
ENVFILE = APPROOT / ".env"
RUNTIME = APPROOT / "runtime"
DBPATH = RUNTIME / "index.db"

load_dotenv(ENVFILE)

def env(k, d=""):
    return os.getenv(k, d)

def _mask(v: str):
    if not v:
        return ""
    if len(v) <= 8:
        return "****"
    return v[:4] + "…" + v[-4:]

def create_app():
    app = Flask(
        __name__,
        template_folder=str(HERE / "templates"),
        static_folder=str(HERE / "static"),
    )

    @app.get("/")
    def home():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        return jsonify({
            "ok": True,
            "provider": env("AI_PROVIDER","auto"),
            "workspace_root": env("WORKSPACE_ROOT",""),
            "db": str(DBPATH),
            "indexed_exists": DBPATH.exists()
        })

    @app.post("/api/index")
    def api_index():
        root = env("WORKSPACE_ROOT", str(Path.cwd()))
        count = index_workspace(root, str(DBPATH))
        return jsonify({"ok": True, "indexed_files": count})

    @app.post("/api/search")
    def api_search():
        q = (request.json or {}).get("q","").strip()
        if not q:
            return jsonify({"ok": False, "error": "missing q"}), 400
        hits = search_index(str(DBPATH), q, limit=12)
        return jsonify({"ok": True, "hits": hits})

    @app.post("/api/chat")
    def api_chat():
        data = request.json or {}
        msg = (data.get("message") or "").strip()
        if not msg:
            return jsonify({"ok": False, "error": "missing message"}), 400

        provider_used, res = generate_reply(msg)
        # res is dict {"ok":bool, "provider":str, "reply":str} or {"error":...}
        if isinstance(res, str):
            res = {"ok": True, "provider": provider_used, "reply": res}

        ok = bool(res.get("ok", False))
        if not ok:
            return jsonify({"ok": False, "provider": provider_used, "error": res.get("error","unknown")}), 200

        return jsonify({
            "ok": True,
            "provider": provider_used,
            "reply": res.get("reply","")
        })

    @app.get("/api/config")
    def api_get_config():
        # send masked keys for UI
        cfg = {
            "AI_PROVIDER": env("AI_PROVIDER","auto"),
            "LOCAL_MODEL_PATH": env("LOCAL_MODEL_PATH",""),
            "OLLAMA_BASE_URL": env("OLLAMA_BASE_URL","http://127.0.0.1:11434"),
            "OPENAI_API_KEY": _mask(env("OPENAI_API_KEY","")),
            "GEMINI_API_KEY": _mask(env("GEMINI_API_KEY","")),
            "DEEPSEEK_API_KEY": _mask(env("DEEPSEEK_API_KEY","")),
            "EXEC_ENABLED": env("EXEC_ENABLED","0"),
            "WRITE_ENABLED": env("WRITE_ENABLED","0"),
        }
        return jsonify({"ok": True, "config": cfg})

    @app.post("/api/config")
    def api_set_config():
        data = request.json or {}

        # Allowed keys to write back into .env
        allowed = {
            "AI_PROVIDER","LOCAL_MODEL_PATH","OLLAMA_BASE_URL","OLLAMA_MODEL",
            "OPENAI_API_KEY","OPENAI_MODEL",
            "GEMINI_API_KEY","GEMINI_MODEL",
            "DEEPSEEK_API_KEY","DEEPSEEK_MODEL","DEEPSEEK_BASE_URL",
            "EXEC_ENABLED","WRITE_ENABLED",
        }

        # Read existing .env
        lines = []
        if ENVFILE.exists():
            lines = ENVFILE.read_text(errors="ignore").splitlines()

        kv = {}
        for ln in lines:
            if not ln.strip() or ln.strip().startswith("#") or "=" not in ln:
                continue
            k, v = ln.split("=", 1)
            kv[k.strip()] = v.strip().strip('"').strip("'")

        for k, v in data.items():
            if k in allowed:
                kv[k] = str(v)

        # Rewrite .env with quotes always
        out = []
        out.append('# FlashTM8 .env (auto-written)')
        out.append(f'WORKSPACE_ROOT="{env("WORKSPACE_ROOT","")}"')
        for k in sorted(kv.keys()):
            if k == "WORKSPACE_ROOT":
                continue
            val = kv[k].replace('"','\\"')
            out.append(f'{k}="{val}"')

        ENVFILE.write_text("\n".join(out) + "\n")

        # reload env immediately
        load_dotenv(ENVFILE, override=True)

        return jsonify({"ok": True, "saved": True})

    @app.post("/api/exec")
    def api_exec():
        data = request.json or {}
        cmd = (data.get("cmd") or "").strip()
        root = env("WORKSPACE_ROOT", str(Path.cwd()))
        res = safe_exec(cmd, root)
        return jsonify(res)

    @app.post("/api/write")
    def api_write():
        data = request.json or {}
        path = (data.get("path") or "").strip()
        content = data.get("content") or ""
        root = env("WORKSPACE_ROOT", str(Path.cwd()))
        res = safe_write(path, content, root)
        return jsonify(res)

    return app

if __name__ == "__main__":
    app = create_app()
    port = int(os.getenv("PORT", "5000"))
    app.run(host="0.0.0.0", port=port, debug=False)
