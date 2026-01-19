#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP_DIR="$REPO/apps/flashtm8/backend"
APP_PY="$APP_DIR/app.py"
START="$REPO/start_flashtm8.sh"
RUNNER="$REPO/apps/flashtm8/run_flashtm8.sh"

echo "✅ Repo: $REPO"
echo "✅ Rebuilding FlashTM8 backend app.py with clean indentation..."

mkdir -p "$APP_DIR"

# Backup old file if exists
if [ -f "$APP_PY" ]; then
  cp -f "$APP_PY" "$APP_PY.bak_rebuild_$(date +%s)" || true
fi

# --- Write a clean, stable Flask backend ---
cat <<'PY' > "$APP_PY"
import os
import json
import traceback
from flask import Flask, request, jsonify, render_template

# Optional: workspace tools/index
try:
    from tools import safe_exec_command  # type: ignore
except Exception:
    safe_exec_command = None

try:
    import workspace_index  # type: ignore
except Exception:
    workspace_index = None

# Optional: AI providers
try:
    import ai_providers  # type: ignore
except Exception:
    ai_providers = None


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def _repo_root() -> str:
    # repo root should be .../repos/8x8org
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def _call_ai(message: str, context: dict | None = None) -> dict:
    """
    Always return JSON dict:
      { ok: bool, provider: str, reply: str }
    """
    provider = _env("AI_PROVIDER", "auto").strip().lower() or "auto"
    context = context or {}

    # If ai_providers has generate_reply() returning (provider_used, reply)
    if ai_providers is not None and hasattr(ai_providers, "generate_reply"):
        try:
            provider_used, reply = ai_providers.generate_reply(message, context=context)  # type: ignore
            return {"ok": True, "provider": str(provider_used), "reply": str(reply)}
        except Exception as e:
            return {"ok": False, "provider": provider, "reply": f"AI error(generate_reply): {e}"}

    # If ai_providers has chat() returning dict or string
    if ai_providers is not None and hasattr(ai_providers, "chat"):
        try:
            res = ai_providers.chat(message, context=context)  # type: ignore
            if isinstance(res, dict):
                # normalize
                return {
                    "ok": bool(res.get("ok", True)),
                    "provider": str(res.get("provider", provider)),
                    "reply": str(res.get("reply", "")),
                }
            return {"ok": True, "provider": provider, "reply": str(res)}
        except Exception as e:
            return {"ok": False, "provider": provider, "reply": f"AI error(chat): {e}"}

    # Hard fallback
    return {
        "ok": True,
        "provider": "fallback",
        "reply": (
            "FlashTM8 is running ✅\n\n"
            "But AI provider is not available right now.\n"
            "You can still Index/Search workspace from the Tools panel."
        ),
    }


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
        return jsonify(
            {
                "ok": True,
                "name": "FlashTM8",
                "provider": _env("AI_PROVIDER", "auto"),
                "workspace": _env("WORKSPACE_ROOT", _repo_root()),
            }
        )

    @app.post("/api/index")
    def api_index():
        root = _env("WORKSPACE_ROOT", _repo_root())
        if workspace_index is None:
            return jsonify({"ok": False, "error": "workspace_index module not found"}), 500

        try:
            # best-effort: support different function names
            if hasattr(workspace_index, "index_workspace"):
                out = workspace_index.index_workspace(root)  # type: ignore
            elif hasattr(workspace_index, "build_index"):
                out = workspace_index.build_index(root)  # type: ignore
            else:
                return jsonify({"ok": False, "error": "No index function found"}), 500

            if isinstance(out, dict):
                return jsonify({"ok": True, **out})

            return jsonify({"ok": True, "result": str(out)})
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
            # best-effort: support different function names
            if hasattr(workspace_index, "search"):
                results = workspace_index.search(q, root=root)  # type: ignore
            elif hasattr(workspace_index, "search_index"):
                results = workspace_index.search_index(q, root=root)  # type: ignore
            else:
                return jsonify({"ok": False, "error": "No search function found"}), 500

            return jsonify({"ok": True, "query": q, "results": results})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)}), 500

    @app.post("/api/chat")
    def api_chat():
        data = request.get_json(silent=True) or {}
        message = (data.get("message") or "").strip()
        context = data.get("context") or {}

        if not message:
            return jsonify({"ok": False, "error": "message is empty"}), 400

        try:
            res = _call_ai(message, context=context)
            return jsonify(res)
        except Exception as e:
            return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500

    @app.post("/api/exec")
    def api_exec():
        """
        This is OFF by default for safety.
        Enable by setting:
          ENABLE_EXEC=1
        """
        if _env("ENABLE_EXEC", "0") != "1":
            return jsonify({"ok": False, "error": "Exec disabled. Set ENABLE_EXEC=1 in .env"}), 403

        if safe_exec_command is None:
            return jsonify({"ok": False, "error": "safe_exec_command not available"}), 500

        data = request.get_json(silent=True) or {}
        cmd = data.get("cmd") or ""
        cmd = cmd.strip()
        if not cmd:
            return jsonify({"ok": False, "error": "cmd is empty"}), 400

        try:
            out = safe_exec_command(cmd)  # type: ignore
            return jsonify({"ok": True, "cmd": cmd, "output": out})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)}), 500

    return app


def main():
    app = create_app()
    host = _env("HOST", "0.0.0.0")
    port = int(_env("PORT", "5000"))
    app.run(host=host, port=port, debug=False)


if __name__ == "__main__":
    main()
PY

echo "✅ app.py rebuilt."

# Fix start scripts to be Termux-safe + always bash-run
if [ -f "$START" ]; then
  cp -f "$START" "$START.bak_rebuild_$(date +%s)" || true
  # Ensure it uses bash + respects PORT
  cat <<'SH' > "$START"
#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
ENVFILE="$REPO/apps/flashtm8/.env"
RUNNER="$REPO/apps/flashtm8/run_flashtm8.sh"

chmod +x "$RUNNER" 2>/dev/null || true

# load env if exists
set -a
[ -f "$ENVFILE" ] && source "$ENVFILE" || true
set +a

PORT="${PORT:-5000}"
export PORT

echo "==============================================="
echo "⚡ FlashTM8 AI Dashboard"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "   Workspace: ${WORKSPACE_ROOT:-$REPO}"
echo "   URL: http://127.0.0.1:${PORT}"
echo "==============================================="

exec bash "$RUNNER"
SH
fi

# Fix runner script to launch backend/app.py
if [ -f "$RUNNER" ]; then
  cp -f "$RUNNER" "$RUNNER.bak_rebuild_$(date +%s)" || true
fi

cat <<'SH' > "$RUNNER"
#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP_DIR="$REPO/apps/flashtm8/backend"
APP_PY="$APP_DIR/app.py"

cd "$APP_DIR"

# If env exists, load it
ENVFILE="$REPO/apps/flashtm8/.env"
set -a
[ -f "$ENVFILE" ] && source "$ENVFILE" || true
set +a

PORT="${PORT:-5000}"
export PORT

python "$APP_PY"
SH

chmod +x "$START" "$RUNNER" 2>/dev/null || true

echo "✅ Scripts rebuilt: start_flashtm8.sh + run_flashtm8.sh"

echo "✅ Checking python compile..."
python -m py_compile "$APP_PY"

echo ""
echo "✅ FlashTM8 backend is VALID ✅"
echo ""
echo "✅ Starting FlashTM8 now on PORT=5000 ..."
PORT=5000 bash "$START"
