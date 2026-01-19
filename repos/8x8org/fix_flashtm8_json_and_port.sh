#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"

APP_PY="$BACK/app.py"
PROV_PY="$BACK/ai_providers.py"

START="$REPO/start_flashtm8.sh"
RUNSH="$APP/run_flashtm8.sh"

echo "✅ Repo: $REPO"

# -----------------------------
# 1) Force ai_providers.chat() to return a DICT (JSON-safe)
# -----------------------------
if [ ! -f "$PROV_PY" ]; then
  echo "❌ Missing: $PROV_PY"
  exit 1
fi

python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/ai_providers.py")
txt = p.read_text(errors="ignore")

# Remove any old chat() implementation (best-effort)
txt = re.sub(r"\n# -+\n# Compatibility wrapper:.*?def chat\([^\)]*\):.*?\n(?=\n\S|\Z)", "\n", txt, flags=re.S)

# Ensure generate_reply exists
if "def generate_reply(" not in txt:
    txt += """

def generate_reply(prompt: str):
    # fallback minimal generator if missing
    provider = "offline"
    return provider, f"(offline) I received: {prompt}"
"""

# Add the correct JSON-safe chat()
txt += """

# -------------------------------------------------
# JSON-safe chat() API
# Backend app.py expects a dict:
#   {"ok": bool, "provider": str, "reply": str}
# -------------------------------------------------
def chat(prompt: str, **kwargs):
    try:
        provider_used, reply = generate_reply(prompt)
        return {"ok": True, "provider": provider_used, "reply": str(reply)}
    except Exception as e:
        return {"ok": False, "provider": "error", "reply": f"Provider error: {e}"}
"""

p.write_text(txt)
print("✅ ai_providers.chat() now returns JSON dict")
PY


# -----------------------------
# 2) Patch backend app.py to tolerate string OR dict return (extra safe)
# -----------------------------
if [ ! -f "$APP_PY" ]; then
  echo "❌ Missing: $APP_PY"
  exit 1
fi

python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/app.py")
txt = p.read_text(errors="ignore")

# Safety patch inside /api/chat handler:
# if res is a string -> convert to dict
if "if isinstance(res, str):" not in txt:
    # Insert right after "res = ai_chat(" block (best-effort)
    txt = re.sub(
        r"(res\s*=\s*ai_chat\([^\n]*\)\s*)",
        r"\1\n        # AUTO-FIX: tolerate providers that return string\n        if isinstance(res, str):\n            res = {\"ok\": True, \"provider\": \"auto\", \"reply\": res}\n",
        txt,
        count=1
    )

# Also ensure jsonify response doesn't crash if res isn't dict
if 'res.get("ok")' in txt:
    txt = txt.replace('res.get("ok")', '(res.get("ok") if isinstance(res, dict) else True)')
if 'res.get("provider")' in txt:
    txt = txt.replace('res.get("provider")', '(res.get("provider") if isinstance(res, dict) else "auto")')
if 'res.get("reply")' in txt:
    txt = txt.replace('res.get("reply")', '(res.get("reply") if isinstance(res, dict) else str(res))')

p.write_text(txt)
print("✅ Patched app.py to prevent /api/chat crashing")
PY


# -----------------------------
# 3) Patch start scripts to respect PORT
# -----------------------------
patch_port_file () {
  local f="$1"
  if [ -f "$f" ]; then
    python - <<PY
from pathlib import Path
import re
p = Path("$f")
txt = p.read_text(errors="ignore")

# Replace hardcoded 5050 occurrences with env-based
txt = txt.replace("5050", '${PORT:-5050}')

# If file runs python directly, ensure PORT is defined
lines = txt.splitlines()
if lines and lines[0].startswith("#!"):
    # insert PORT default after shebang if not present
    if not any("PORT=" in l for l in lines[:5]):
        lines.insert(1, 'PORT="${PORT:-5050}"')
txt = "\n".join(lines) + "\n"

p.write_text(txt)
print("✅ Patched port in:", p)
PY
  fi
}

patch_port_file "$START"
patch_port_file "$RUNSH"

chmod +x "$START" 2>/dev/null || true
chmod +x "$RUNSH" 2>/dev/null || true

echo ""
echo "✅ FlashTM8 API + PORT FIX applied!"
echo "Now starting FlashTM8 on PORT=5000 ..."
echo ""

# -----------------------------
# 4) Start FlashTM8 correctly
# -----------------------------
set -a
[ -f "$APP/.env" ] && source "$APP/.env" || true
set +a

PORT=5000 bash "$START"
