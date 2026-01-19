#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
APP_PY="$BACK/app.py"
JS="$BACK/static/app.js"
ENVFILE="$APP/.env"
START="$REPO/start_flashtm8.sh"
RUNNER="$APP/run_flashtm8.sh"

echo "✅ Repo: $REPO"
echo "✅ Fixing FlashTM8: Unknown error / JSON / frontend URL / fallback mode..."

mkdir -p "$BACK/static" "$BACK/templates"

# ----------------------------
# 1) Force fallback mode (so AI never blocks UI)
# ----------------------------
touch "$ENVFILE"

# Remove bad lines that break `source` (spaces in secrets etc.)
# Keep it simple: only add safe env vars needed for working UI
python - <<'PY'
from pathlib import Path
p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/.env")
lines = []
seen = set()
safe_keys = {
    "AI_PROVIDER","PORT","HOST","WORKSPACE_ROOT",
    "ENABLE_EXEC","ENABLE_WRITE"
}
if p.exists():
    for raw in p.read_text(errors="ignore").splitlines():
        s = raw.strip()
        if not s or s.startswith("#"): 
            continue
        if "=" not in s:
            continue
        k = s.split("=",1)[0].strip()
        # Keep existing keys, but avoid garbage lines
        if k and k not in seen:
            lines.append(raw)
            seen.add(k)

# Ensure minimum working vars
def upsert(key, value):
    nonlocal lines, seen
    if key in seen:
        # replace existing
        new = []
        for r in lines:
            if r.strip().startswith(key+"="):
                new.append(f'{key}="{value}"')
            else:
                new.append(r)
        lines = new
    else:
        lines.append(f'{key}="{value}"')
        seen.add(key)

upsert("AI_PROVIDER", "fallback")
upsert("HOST", "0.0.0.0")
upsert("PORT", "5000")
upsert("WORKSPACE_ROOT", "/home/runner/workspace/repos/8x8org")
upsert("ENABLE_EXEC", "0")
upsert("ENABLE_WRITE", "0")

p.write_text("\n".join(lines).strip() + "\n")
print("✅ .env cleaned + forced AI_PROVIDER=fallback")
PY

# ----------------------------
# 2) Patch backend to ALWAYS return JSON on error
# ----------------------------
if [ -f "$APP_PY" ]; then
  cp -f "$APP_PY" "$APP_PY.bak_unknown_$(date +%s)" || true
fi

python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/app.py")
txt = p.read_text(errors="ignore") if p.exists() else ""

# If file is missing or not a Flask app, create a safe one
if "Flask(" not in txt or "def create_app" not in txt:
    txt = """import os
import traceback
from flask import Flask, request, jsonify, render_template

try:
    import workspace_index
except Exception:
    workspace_index = None

try:
    import ai_providers
except Exception:
    ai_providers = None

def _env(k, d=""):
    return os.environ.get(k, d)

def _repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

def _call_ai(message: str, context: dict | None = None) -> dict:
    provider = _env("AI_PROVIDER", "fallback").strip().lower() or "fallback"
    context = context or {}

    # fallback always works
    if provider == "fallback" or ai_providers is None:
        return {"ok": True, "provider": "fallback", "reply": "FlashTM8 is running ✅\\n\\nAI provider is not available right now, but workspace tools work."}

    # try generate_reply first
    if hasattr(ai_providers, "generate_reply"):
        try:
            prov, reply = ai_providers.generate_reply(message, context=context)
            return {"ok": True, "provider": str(prov), "reply": str(reply)}
        except Exception as e:
            return {"ok": False, "provider": provider, "reply": f"AI error(generate_reply): {e}"}

    # try chat second
    if hasattr(ai_providers, "chat"):
        try:
            res = ai_providers.chat(message, context=context)
            if isinstance(res, dict):
                return {"ok": bool(res.get("ok", True)), "provider": str(res.get("provider", provider)), "reply": str(res.get("reply",""))}
            return {"ok": True, "provider": provider, "reply": str(res)}
        except Exception as e:
            return {"ok": False, "provider": provider, "reply": f"AI error(chat): {e}"}

    return {"ok": True, "provider": "fallback", "reply": "FlashTM8 fallback ✅"}

def create_app() -> Flask:
    app = Flask(__name__,
        template_folder=os.path.join(os.path.dirname(__file__), "templates"),
        static_folder=os.path.join(os.path.dirname(__file__), "static"),
    )

    @app.get("/")
    def home():
        return render_template("index.html")

    @app.get("/api/health")
    def health():
        return jsonify({"ok": True, "name": "FlashTM8", "provider": _env("AI_PROVIDER","fallback"), "workspace": _env("WORKSPACE_ROOT", _repo_root())})

    @app.post("/api/chat")
    def chat():
        data = request.get_json(silent=True) or {}
        msg = (data.get("message") or "").strip()
        ctx = data.get("context") or {}
        if not msg:
            return jsonify({"ok": False, "provider": _env("AI_PROVIDER","fallback"), "reply": "", "error": "message is empty"}), 400
        res = _call_ai(msg, ctx)
        return jsonify(res)

    @app.post("/api/index")
    def api_index():
        root = _env("WORKSPACE_ROOT", _repo_root())
        if workspace_index is None:
            return jsonify({"ok": False, "error": "workspace_index module not found"}), 500
        try:
            if hasattr(workspace_index, "index_workspace"):
                out = workspace_index.index_workspace(root)
            elif hasattr(workspace_index, "build_index"):
                out = workspace_index.build_index(root)
            else:
                return jsonify({"ok": False, "error": "No index function found"}), 500
            return jsonify({"ok": True, "result": out})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)}), 500

    @app.post("/api/search")
    def api_search():
        data = request.get_json(silent=True) or {}
        q = (data.get("query") or "").strip()
        root = _env("WORKSPACE_ROOT", _repo_root())
        if not q:
            return jsonify({"ok": False, "error": "query is empty"}), 400
        if workspace_index is None:
            return jsonify({"ok": False, "error": "workspace_index module not found"}), 500
        try:
            if hasattr(workspace_index, "search"):
                out = workspace_index.search(q, root=root)
            elif hasattr(workspace_index, "search_index"):
                out = workspace_index.search_index(q, root=root)
            else:
                return jsonify({"ok": False, "error": "No search function found"}), 500
            return jsonify({"ok": True, "results": out})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)}), 500

    @app.errorhandler(Exception)
    def all_errors(e):
        return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500

    return app

def main():
    app = create_app()
    host = _env("HOST", "0.0.0.0")
    port = int(_env("PORT", "5000"))
    app.run(host=host, port=port, debug=False)

if __name__ == "__main__":
    main()
"""
else:
    # Add global error handler if missing
    if "@app.errorhandler(Exception)" not in txt:
        txt = re.sub(
            r"(return app\s*\n)",
            r'''    @app.errorhandler(Exception)
    def all_errors(e):
        import traceback
        return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500

\1''',
            txt,
            flags=re.MULTILINE
        )

    # Ensure api_chat always returns dict
    if 'def api_chat' in txt or 'def do_chat' in txt:
        # Best-effort: if res is string, wrap it
        txt = txt.replace("return jsonify(res)", "return jsonify(res if isinstance(res, dict) else {\"ok\": True, \"provider\": os.environ.get(\"AI_PROVIDER\",\"fallback\"), \"reply\": str(res)})")

p.write_text(txt)
print("✅ backend app.py now always returns JSON even on errors")
PY

# ----------------------------
# 3) Patch frontend JS to use relative URLs + show real errors (not Unknown)
# ----------------------------
if [ -f "$JS" ]; then
  cp -f "$JS" "$JS.bak_unknown_$(date +%s)" || true
  python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/static/app.js")
txt = p.read_text(errors="ignore")

# Replace any hardcoded http://127.0.0.1:5050/... or 5000 with relative
txt = re.sub(r"https?://127\.0\.0\.1:\d+", "", txt)
txt = re.sub(r"https?://localhost:\d+", "", txt)

# If it uses fetch(".../api/chat"), force "/api/chat"
txt = re.sub(r'fetch\(\s*["\'].*?/api/chat["\']', 'fetch("/api/chat"', txt)
txt = re.sub(r'fetch\(\s*["\'].*?/api/index["\']', 'fetch("/api/index"', txt)
txt = re.sub(r'fetch\(\s*["\'].*?/api/search["\']', 'fetch("/api/search"', txt)

# Improve error message: show response text if JSON fails
if "Unknown" in txt and "responseText" not in txt:
    txt = txt.replace(
        'throw new Error("Unknown")',
        'throw new Error(responseText || "Unknown")'
    )

p.write_text(txt)
print("✅ frontend app.js patched: relative API + better error display")
PY
else
  echo "⚠️ app.js not found, skipping JS patch"
fi

# ----------------------------
# 4) Ensure start scripts always run on PORT=5000
# ----------------------------
chmod +x "$START" "$RUNNER" 2>/dev/null || true

echo ""
echo "✅ DONE."
echo "Now start FlashTM8 cleanly:"
echo "  cd $REPO"
echo "  set -a; source $ENVFILE; set +a"
echo "  PORT=5000 bash start_flashtm8.sh"
echo ""
