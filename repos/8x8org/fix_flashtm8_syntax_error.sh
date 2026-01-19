#!/usr/bin/env bash
set -euo pipefail

APP_PY="/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/app.py"
START="/home/runner/workspace/repos/8x8org/start_flashtm8.sh"
RUNSH="/home/runner/workspace/repos/8x8org/apps/flashtm8/run_flashtm8.sh"

echo "✅ Fixing syntax error in: $APP_PY"

python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/app.py")
txt = p.read_text(errors="ignore")

# Fix the broken escaped dict (\"...\")
txt = txt.replace(
    r'res = {\"ok\": True, \"provider\": \"auto\", \"reply\": res}',
    'res = {"ok": True, "provider": "auto", "reply": res}'
)

# Also fix any other accidental escaped quotes inside dict blocks
txt = txt.replace(r'{\"ok\"', '{"ok"').replace(r'\"provider\"', '"provider"').replace(r'\"reply\"', '"reply"')
txt = txt.replace(r'\"auto\"', '"auto"')

p.write_text(txt)
print("✅ app.py syntax fixed")
PY

# Make sure scripts executable
chmod +x "$START" "$RUNSH" 2>/dev/null || true

echo ""
echo "✅ Restarting FlashTM8 on PORT=5000..."
echo ""

# load env if exists
set -a
[ -f "/home/runner/workspace/repos/8x8org/apps/flashtm8/.env" ] && source "/home/runner/workspace/repos/8x8org/apps/flashtm8/.env" || true
set +a

PORT=5000 bash "$START"
