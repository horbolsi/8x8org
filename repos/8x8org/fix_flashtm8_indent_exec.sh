#!/usr/bin/env bash
set -euo pipefail

APP_PY="/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/app.py"
START="/home/runner/workspace/repos/8x8org/start_flashtm8.sh"

echo "✅ Fixing indentation issues in: $APP_PY"

# Backup first
cp -f "$APP_PY" "$APP_PY.bak_indent_$(date +%s)" || true

python - <<'PY'
from pathlib import Path
import re

p = Path("/home/runner/workspace/repos/8x8org/apps/flashtm8/backend/app.py")
lines = p.read_text(errors="ignore").splitlines(True)

fixed = []
for i, line in enumerate(lines):
    # Fix any accidental indentation before route decorators
    # Example: "    @app.post('/api/exec')" -> "@app.post('/api/exec')"
    if re.match(r"^\s+@app\.(get|post|put|delete|patch)\(", line):
        fixed.append(line.lstrip())
        continue

    # Fix accidental indentation before top-level defs
    # Example: "    def do_chat():" -> "def do_chat():"
    if re.match(r"^\s+def\s+[A-Za-z_]\w*\(", line):
        fixed.append(line.lstrip())
        continue

    # Fix accidental indentation before top-level imports
    if re.match(r"^\s+(import|from)\s+", line):
        # Only dedent imports if they look like top-level ones
        fixed.append(line.lstrip())
        continue

    fixed.append(line)

p.write_text("".join(fixed))
print("✅ Dedented @app.* routes + def blocks (safe patch)")
PY

echo "✅ Checking python compile..."
python -m py_compile "$APP_PY"

echo ""
echo "✅ FlashTM8 backend is now valid Python ✅"
echo ""

# Load env if exists
set -a
[ -f "/home/runner/workspace/repos/8x8org/apps/flashtm8/.env" ] && source "/home/runner/workspace/repos/8x8org/apps/flashtm8/.env" || true
set +a

echo "✅ Starting FlashTM8 on PORT=5000 ..."
PORT=5000 bash "$START"
