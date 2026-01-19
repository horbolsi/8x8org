#!/usr/bin/env bash
set -euo pipefail

# ================================
# FlashTM8 One-Shot Fix Script
# - fixes requests/urllib3 issue
# - configures AI provider (.env)
# - creates start script
# - adds optional fallback helper
# ================================

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

say() { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️${NC} $*"; }
err() { echo -e "${RED}❌${NC} $*"; }

# ----------------
# Locate repo root
# ----------------
ROOT_DEFAULT="/home/runner/workspace/repos/8x8org"

if [ -d "$ROOT_DEFAULT" ]; then
  ROOT="$ROOT_DEFAULT"
else
  # fallback: try to detect from current path
  ROOT="$(pwd)"
  if [ ! -f "$ROOT/sovereign_dashboard_full.py" ]; then
    # attempt: walk up to find sovereign_dashboard_full.py
    FOUND="$(python - << 'PY'
import os
p=os.getcwd()
for _ in range(8):
    if os.path.exists(os.path.join(p,"sovereign_dashboard_full.py")):
        print(p); break
    p=os.path.dirname(p)
PY
)"
    if [ -n "${FOUND:-}" ]; then
      ROOT="$FOUND"
    fi
  fi
fi

if [ ! -f "$ROOT/sovereign_dashboard_full.py" ]; then
  err "Cannot find sovereign_dashboard_full.py in: $ROOT"
  echo "Go to your repo folder then run this script again."
  echo "Example:"
  echo "  cd /home/runner/workspace/repos/8x8org"
  echo "  bash fix_flashtm8_ai.sh"
  exit 1
fi

say "Repo detected at: $ROOT"

# --------------------------------------
# 1) Fix broken requests/urllib3 on Termux
# --------------------------------------
say "Fixing requests/urllib3/six (Termux compatibility)..."
python -m pip install --upgrade --force-reinstall "requests>=2.32.3" "urllib3>=2.2.0" six >/dev/null 2>&1 || {
  warn "pip reinstall had a warning. Trying again with output..."
  python -m pip install --upgrade --force-reinstall "requests>=2.32.3" "urllib3>=2.2.0" six
}
say "requests/urllib3 fixed."

# -----------------------
# Helpers to edit .env file
# -----------------------
set_kv () {
  local file="$1"
  local key="$2"
  local val="$3"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  # If key exists -> replace, else append
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

# --------------------------------------
# 2) Create / update FlashTM8 .env
# --------------------------------------
# Adjust this path if you keep FlashTM8 somewhere else.
FLASH_ENV="$ROOT/apps/flashtm8/.env"

say "Creating/updating FlashTM8 env at: $FLASH_ENV"

# Defaults
set_kv "$FLASH_ENV" "FLASH_NAME" "FlashTM8"
set_kv "$FLASH_ENV" "FLASH_THEME" "sovereign_console"
set_kv "$FLASH_ENV" "WORKSPACE_ROOT" "$ROOT"
set_kv "$FLASH_ENV" "INDEX_MAX_FILES" "5000"
set_kv "$FLASH_ENV" "INDEX_MAX_BYTES_PER_FILE" "200000"
set_kv "$FLASH_ENV" "ALLOW_EXEC" "0"
set_kv "$FLASH_ENV" "ALLOW_WRITE" "0"

# Provider logic:
# - If user exported OPENAI_API_KEY before running the script, we auto-enable OpenAI
# - else keep Ollama as default (local or remote)
AI_PROVIDER="${AI_PROVIDER:-}"

if [ -n "${OPENAI_API_KEY:-}" ]; then
  AI_PROVIDER="openai"
fi

if [ -z "${AI_PROVIDER:-}" ]; then
  AI_PROVIDER="ollama"
fi

set_kv "$FLASH_ENV" "AI_PROVIDER" "$AI_PROVIDER"

if [ "$AI_PROVIDER" = "openai" ]; then
  set_kv "$FLASH_ENV" "OPENAI_API_KEY" "${OPENAI_API_KEY:-PASTE_YOUR_KEY_HERE}"
  set_kv "$FLASH_ENV" "OPENAI_MODEL" "${OPENAI_MODEL:-gpt-4.1-mini}"
  say "OpenAI enabled in .env"
else
  set_kv "$FLASH_ENV" "OLLAMA_BASE_URL" "${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"
  set_kv "$FLASH_ENV" "OLLAMA_MODEL" "${OLLAMA_MODEL:-llama3.1:8b}"
  say "Ollama enabled in .env"
fi

# --------------------------------------
# 3) Add a safe fallback helper (non-breaking)
# --------------------------------------
FALLBACK_FILE="$ROOT/apps/flashtm8/backend/ai_fallback_patch.py"
mkdir -p "$(dirname "$FALLBACK_FILE")"

cat > "$FALLBACK_FILE" << 'PY'
"""
FlashTM8 fallback helper:
- If your AI provider is OFF, you can still return results using workspace index context.
This file does NOT break anything by itself; it is safe.
"""
def fallback_answer(user_msg: str, ctx: list[dict] | None = None) -> str:
    ctx = ctx or []
    lines = []
    lines.append("⚡ FlashTM8 (Fallback Mode)\n")
    lines.append("AI provider is offline, but I can still help using indexed workspace results.\n")
    if not ctx:
        lines.append("No indexed matches found. Try using Search or click Index Workspace again.\n")
    else:
        lines.append("Top matching files/snippets:\n")
        for i, c in enumerate(ctx[:8], 1):
            path = c.get("path","(unknown)")
            score = c.get("score","?")
            snippet = (c.get("snippet","") or "").strip()
            lines.append(f"{i}) {path} (score={score})")
            if snippet:
                lines.append(snippet[:800])
            lines.append("")
    lines.append("✅ Tip: Ask things like: 'How do I run the dashboard and the bot?'")
    return "\n".join(lines)
PY

say "Fallback helper created: $FALLBACK_FILE"

# --------------------------------------
# 4) Create a clean start script for your dashboard
# --------------------------------------
START_SCRIPT="$ROOT/start_dashboard.sh"

cat > "$START_SCRIPT" << 'SH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Use PORT if provided, otherwise default 5000
export PORT="${PORT:-5000}"

echo "✅ Starting Sovereign Dashboard / FlashTM8 UI..."
echo "   ROOT=$ROOT"
echo "   PORT=$PORT"

cd "$ROOT"
python sovereign_dashboard_full.py
SH

chmod +x "$START_SCRIPT"
say "Start script created: $START_SCRIPT"

# --------------------------------------
# 5) Check Ollama availability if selected
# --------------------------------------
if [ "$AI_PROVIDER" = "ollama" ]; then
  OLLAMA_URL="$(grep -E '^OLLAMA_BASE_URL=' "$FLASH_ENV" | tail -n1 | cut -d= -f2-)"
  warn "AI_PROVIDER=ollama selected. Checking if Ollama is reachable..."
  if command -v curl >/dev/null 2>&1; then
    if curl -s "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
      say "Ollama is reachable at: $OLLAMA_URL"
    else
      warn "Ollama NOT reachable at: $OLLAMA_URL"
      echo "   Fix options:"
      echo "   1) Run locally (if supported):  ollama serve"
      echo "   2) Use remote server: export OLLAMA_BASE_URL=http://SERVER:11434 && re-run script"
      echo "   3) Use OpenAI instead: export OPENAI_API_KEY=xxxx && re-run script"
    fi
  else
    warn "curl not found; skipping Ollama connectivity check."
  fi
fi

# --------------------------------------
# DONE
# --------------------------------------
echo
say "All fixes applied successfully!"
echo "----------------------------------------"
echo "NEXT STEPS:"
echo
echo "1) If you want OpenAI replies, run this BEFORE starting:"
echo "   export OPENAI_API_KEY='YOUR_KEY_HERE'"
echo "   export AI_PROVIDER=openai"
echo
echo "2) Start the dashboard:"
echo "   $ROOT/start_dashboard.sh"
echo
echo "3) Open in browser (same phone):"
echo "   http://127.0.0.1:5000"
echo
echo "4) Index Workspace and chat with FlashTM8 ⚡"
echo
echo "Your FlashTM8 env file is here:"
echo "   $FLASH_ENV"
echo "----------------------------------------"
