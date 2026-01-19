#!/usr/bin/env bash
set -euo pipefail

REPO="/home/runner/workspace/repos/8x8org"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
PROV="$BACK/ai_providers.py"
START="$REPO/start_flashtm8.sh"

echo "✅ Repo: $REPO"

# -----------------------------
# 1) Ensure ai_providers.py has chat()
# -----------------------------
if [ ! -f "$PROV" ]; then
  echo "❌ Missing: $PROV"
  exit 1
fi

# Add chat() wrapper if missing
if ! grep -q "def chat(" "$PROV"; then
  cat <<'PY' >> "$PROV"

# -------------------------------------------------
# Compatibility wrapper:
# app.py expects: from ai_providers import chat as ai_chat
# -------------------------------------------------
def chat(prompt: str, **kwargs):
    """
    Returns ONLY the text reply (string),
    compatible with existing app.py import.
    """
    provider_used, text = generate_reply(prompt)
    return text
PY
  echo "✅ Added chat() wrapper to ai_providers.py"
else
  echo "✅ chat() already exists in ai_providers.py"
fi

# -----------------------------
# 2) Fix start_flashtm8.sh to respect PORT env var
# -----------------------------
if [ -f "$START" ]; then
  # If script hardcodes 5050, patch it
  # We force it to use: PORT="${PORT:-5050}"
  if ! grep -q 'PORT="\${PORT:-' "$START"; then
    python - <<'PY'
from pathlib import Path
p = Path("/home/runner/workspace/repos/8x8org/start_flashtm8.sh")
txt = p.read_text(errors="ignore").splitlines()

out=[]
port_line_added=False

for line in txt:
    # remove any old hardcoded PORT assignment lines (best effort)
    if line.strip().startswith("PORT=") and ("5050" in line or "5000" in line):
        continue
    out.append(line)

# insert PORT default near top after shebang
new=[]
for i,line in enumerate(out):
    new.append(line)
    if i==0 and line.startswith("#!"):
        new.append('PORT="${PORT:-5050}"')
        port_line_added=True

# If no shebang found, just prepend
if not port_line_added:
    new = ['PORT="${PORT:-5050}"'] + new

p.write_text("\n".join(new) + "\n")
print("✅ Patched start_flashtm8.sh to use PORT env")
PY
  else
    echo "✅ start_flashtm8.sh already respects PORT env"
  fi
else
  echo "⚠️ Missing: $START (skipping PORT patch)"
fi

# -----------------------------
# 3) Make executable
# -----------------------------
chmod +x "$REPO/start_flashtm8.sh" 2>/dev/null || true
chmod +x "$APP/run_flashtm8.sh" 2>/dev/null || true
chmod +x "$REPO/start_dashboard.sh" 2>/dev/null || true

echo ""
echo "✅ FIX DONE!"
echo "Now start FlashTM8 using PORT=5000:"
echo "  cd $REPO"
echo "  set -a; source $APP/.env; set +a"
echo "  PORT=5000 bash start_flashtm8.sh"
echo ""
