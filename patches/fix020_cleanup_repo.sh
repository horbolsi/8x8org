#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
ARCH="archive/cleanup_${TS}"
mkdir -p "$ARCH"

echo "== stopping services (best effort) =="
bash tools/dev dash:stop >/dev/null 2>&1 || true
bash tools/dev bot:stop  >/dev/null 2>&1 || true

echo "== ensure canonical app locations exist =="
mkdir -p apps/dashboard/templates
mkdir -p services/bot

# Choose the currently working dashboard code as source.
# Prefer root sovereign_dashboard_full.py if it exists, else apps/dashboard/server.py.
SRC=""
if [ -f sovereign_dashboard_full.py ]; then
  SRC="sovereign_dashboard_full.py"
elif [ -f apps/dashboard/server.py ]; then
  SRC="apps/dashboard/server.py"
else
  echo "❌ No dashboard python entrypoint found"
  exit 1
fi

echo "== move working dashboard into apps/dashboard/server.py =="
cp -f "$SRC" apps/dashboard/server.py

echo "== move template into apps/dashboard/templates/sovereign_full.html =="
if [ -f templates/sovereign_full.html ]; then
  cp -f templates/sovereign_full.html apps/dashboard/templates/sovereign_full.html
elif [ -f apps/dashboard/templates/sovereign_full.html ]; then
  true
else
  echo "❌ Missing sovereign_full.html template (templates/sovereign_full.html not found)"
  exit 1
fi

echo "== patch apps/dashboard/server.py to use its own templates folder =="
python - <<'PY'
from pathlib import Path
import re

p = Path("apps/dashboard/server.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# ensure Path is imported
if "from pathlib import Path" not in s:
    # add after other imports near top
    s = re.sub(r"(import\s+os\s*\n)", r"\1from pathlib import Path\n", s, count=1)

# insert BASE_DIR definition once
if "BASE_DIR = Path(__file__)" not in s:
    # place after HOME = Path.home() if present, else near top after imports
    if "HOME = Path.home()" in s:
        s = s.replace("HOME = Path.home()", "HOME = Path.home()\nBASE_DIR = Path(__file__).resolve().parent")
    else:
        # fallback: add after imports block
        s = re.sub(r"(from flask import[\s\S]*?\)\n)", r"\1\n\nBASE_DIR = Path(__file__).resolve().parent\n", s, count=1)

# patch Flask app creation to include template_folder
s = re.sub(
    r"app\s*=\s*Flask\(__name__\)",
    "app = Flask(__name__, template_folder=str(BASE_DIR / 'templates'))",
    s
)

p.write_text(s, encoding="utf-8")
print("✅ server.py now uses apps/dashboard/templates")
PY

echo "== create root wrapper (keeps old command working) =="
cat > sovereign_dashboard_full.py <<'PY'
#!/usr/bin/env python3
from apps.dashboard.server import main

if __name__ == "__main__":
    main()
PY
chmod +x sovereign_dashboard_full.py || true

echo "== canonical bot location =="
if [ -f services/bot/telegram_webapp_bot.py ]; then
  true
elif [ -f bot/telegram_webapp_bot.py ]; then
  cp -f bot/telegram_webapp_bot.py services/bot/telegram_webapp_bot.py
else
  echo "⚠️ Bot file not found in bot/ or services/bot/ (skipping)"
fi

echo "== patch tools/dev to use canonical paths =="
python - <<'PY'
from pathlib import Path
p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

# Start dashboard via root wrapper (stable) OR direct server.py. We'll use wrapper.
s = s.replace("python sovereign_dashboard_full.py", "python sovereign_dashboard_full.py")
# If tools/dev references apps/dashboard/server.py already, keep it.
# Ensure bot runs from services/bot
s = s.replace("python bot/telegram_webapp_bot.py", "python services/bot/telegram_webapp_bot.py")
s = s.replace("python ./bot/telegram_webapp_bot.py", "python services/bot/telegram_webapp_bot.py")

p.write_text(s, encoding="utf-8")
print("✅ tools/dev patched for canonical bot path")
PY

echo "== archive non-essential / legacy folders (NOT deleting) =="

move_if_exists () {
  local path="$1"
  if [ -e "$path" ]; then
    echo " - archiving: $path"
    mv "$path" "$ARCH/" || true
  fi
}

# old/duplicate python dashboard bits
move_if_exists app
move_if_exists templates
move_if_exists static

# old duplicate bot folder (we keep services/bot)
move_if_exists bot

# frontend / node / build artifacts (can restore from archive anytime)
move_if_exists backend
move_if_exists src
move_if_exists components
move_if_exists dist
move_if_exists public
move_if_exists lib
move_if_exists store
move_if_exists index.html
move_if_exists package.json
move_if_exists package-lock.json
move_if_exists postcss.config.js
move_if_exists tailwind.config.js
move_if_exists vite.config.ts
move_if_exists tsconfig.json
move_if_exists tsconfig.app.json
move_if_exists tsconfig.node.json
move_if_exists yw_manifest.json
move_if_exists App.tsx.backup

# installer / backup / misc scripts (keep only if you really use them)
move_if_exists install-ollama.sh
move_if_exists install-ollama-proper.sh
move_if_exists install-deepseek.sh
move_if_exists install-ai-fallback.sh
move_if_exists setup-ai-assistant.sh
move_if_exists setup-all.sh
move_if_exists fix-ollama.sh
move_if_exists fix-ollama2.sh
move_if_exists backup-everything.sh
move_if_exists backup-server.js
move_if_exists backup-server.mjs
move_if_exists github-backup.sh
move_if_exists push-to-github.sh
move_if_exists push-to-termux.sh
move_if_exists test-backup.mjs
move_if_exists replit.md
move_if_exists YOUWARE.md
move_if_exists assets

# remove caches (safe)
rm -rf __pycache__ apps/dashboard/__pycache__ services/bot/__pycache__ 2>/dev/null || true

# remove weird CR folder if present
rm -rf $'templates\r' 2>/dev/null || true

echo "== ensure .gitignore sane =="
grep -q '^runtime/' .gitignore 2>/dev/null || cat >> .gitignore <<'TXT'

# runtime
runtime/
__pycache__/
*.pyc
*.log

# local secrets
.env
TXT

echo "== compile check =="
python -m py_compile apps/dashboard/server.py
python -m py_compile sovereign_dashboard_full.py

echo
echo "✅ CLEANUP DONE"
echo "Archived to: $ARCH"
echo
echo "Next:"
echo "  8x8 status"
echo "  : > runtime/dashboard.out"
echo "  8x8 dash:restart"
echo "  8x8 dash:tail"
