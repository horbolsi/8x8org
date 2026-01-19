# (#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------
# FlashTM8 Complete Repair + Autonomous Mode
# --------------------------------------------

REPO="${1:-/home/runner/workspace/repos/8x8org}"
APP="$REPO/apps/flashtm8"
BACK="$APP/backend"
RUNTIME="$APP/runtime"
ENVFILE="$APP/.env"
TEMPLATE="$APP/.env.template"

ts() { date +"%Y%m%d-%H%M%S"; }
say() { printf "\n✅ %s\n" "$*"; }
warn() { printf "\n⚠️ %s\n" "$*"; }

if [ ! -d "$REPO" ]; then
  echo "❌ Repo not found: $REPO"
  echo "Usage: bash fix_flashtm8_complete.sh /path/to/8x8org"
  exit 1
fi

say "Repo: $REPO"
mkdir -p "$BACK" "$RUNTIME"

# Backup existing backend files (safe)
BK="$APP/archive_backup_$(ts)"
mkdir -p "$BK"
cp -f "$BACK/app.py" "$BK/app.py.bak" 2>/dev/null || true
cp -f "$BACK/ai_providers.py" "$BK/ai_providers.py.bak" 2>/dev/null || true
cp -f "$BACK/workspace_index.py" "$BK/workspace_index.py.bak" 2>/dev/null || true
cp -f "$BACK/tools.py" "$BK/tools.py.bak" 2>/dev/null || true

say "Backup saved to: $BK"

# --------------------------------------------
# 1) Install minimal python deps (Termux safe)
# --------------------------------------------
say "Installing Python dependencies..."
python -m pip install --upgrade --user \
  flask requests python-dotenv \
  >/dev/null

# Fix bad old requests/urllib3 (Termux often ships ancient versions)
say "Fixing requests/urllib3/six compatibility..."
python -m pip install --upgrade --user --force-reinstall \
  "requests>=2.32.3" "urllib3>=2.2.0" "six>=1.17.0" >/dev/null

# --------------------------------------------
# 2) Write .env.template (BASH SAFE)
#    (YOU paste keys here after)
# --------------------------------------------
say "Writing .env template (safe quoting)..."
cat > "$TEMPLATE" <<'EOF'
# ==============================
# FlashTM8 Configuration (SAFE)
# Paste your keys here (quotes matter!)
# ==============================

# Provider mode:
# auto = offline→ollama→gemini→openai→deepseek→fallback
AI_PROVIDER="auto"

# Offline GGUF local model (optional)
# Example:
# LOCAL_MODEL_PATH="/sdcard/models/your-model.gguf"
LOCAL_MODEL_PATH=""

# Ollama (optional)
OLLAMA_BASE_URL="http://127.0.0.1:11434"
OLLAMA_MODEL="llama3"

# Cloud keys (optional)
OPENAI_API_KEY=""
OPENAI_MODEL="gpt-4o-mini"

GEMINI_API_KEY=""
GEMINI_MODEL="gemini-1.5-flash"

DEEPSEEK_API_KEY=""
DEEPSEEK_MODEL="deepseek-chat"
DEEPSEEK_BASE_URL="https://api.deepseek.com"

# Admin tools (dangerous – only enable if you want AI to edit files/run commands)
EXEC_ENABLED="0"
WRITE_ENABLED="0"

# Workspace root
WORKSPACE_ROOT="__REPO__"

# (Optional) Your project secrets (keep quoted!)
# SMTP_USER=""
# SMTP_PASS=""
# OWNER_ID=""
# TELEGRAM_BOT_TOKEN=""
