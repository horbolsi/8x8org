#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/runner/workspace/repos/8x8org"

GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RED="\033[0;31m"; NC="\033[0m"
say(){ echo -e "${GREEN}✅${NC} $*"; }
warn(){ echo -e "${YELLOW}⚠️${NC} $*"; }
err(){ echo -e "${RED}❌${NC} $*"; }

if [ ! -d "$ROOT" ]; then
  err "Repo not found: $ROOT"
  exit 1
fi

cd "$ROOT"
say "Repo detected at: $ROOT"

# ----------------------------
# 1) Fix python requests/urllib3/six (your previous error)
# ----------------------------
say "Fixing requests/urllib3/six (Termux compatibility)..."
python -m pip install --upgrade --force-reinstall "requests>=2.32.3" "urllib3>=2.2.0" six >/dev/null 2>&1 || {
  warn "pip quiet install failed, retrying with logs..."
  python -m pip install --upgrade --force-reinstall "requests>=2.32.3" "urllib3>=2.2.0" six
}
say "requests/urllib3 fixed."

# ----------------------------
# Helper: write KEY=VALUE safely (replace if exists)
# ----------------------------
set_kv () {
  local file="$1"
  local key="$2"
  local val="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

# ----------------------------
# Helper: prompt hidden (no echo)
# ----------------------------
ask_secret () {
  local var="$1"
  local label="$2"
  if [ -z "${!var:-}" ]; then
    echo
    echo "🔐 Paste ${label} (hidden input):"
    read -r -s tmp
    echo
    export "$var"="$tmp"
  fi
}

ask_normal () {
  local var="$1"
  local label="$2"
  if [ -z "${!var:-}" ]; then
    echo
    echo "✍️ Enter ${label}:"
    read -r tmp
    export "$var"="$tmp"
  fi
}

# ----------------------------
# 2) Ask for your secrets PRIVATELY (safe)
# ----------------------------
say "Now I will collect your secrets privately (nothing will be printed)."

ask_secret SESSION_SECRET "SESSION_SECRET"
ask_normal OWNER_ID "OWNER_ID (number like 1950324763)"

ask_normal SMTP_USER "SMTP_USER (email)"
ask_secret SMTP_PASS "SMTP_PASS (Gmail App Password)"

ask_secret CLICKUP_API_TOKEN "CLICKUP_API_TOKEN"

ask_secret TELEGRAM_BOT_TOKEN "TELEGRAM_BOT_TOKEN"
ask_secret APP8X8ORG_BOT_TOKEN "app8x8org_BOT_TOKEN"
ask_secret OUT8X8ORG_BOT_TOKEN "out8x8org_BOT_TOKEN"
ask_secret IN8X8ORG_BOT_TOKEN "in8x8org_bot"
ask_secret AIRDROP8X8ORG_BOT_TOKEN "airdrop8x8org_bot"
ask_secret WALLET8X8ORG_BOT_TOKEN "wallet8x8org_bot"

ask_secret OPENAI_API_KEY "OPENAI_API_KEY"
ask_secret GEMINI_API_KEY "GEMINI_API_KEY"
ask_secret DEEPSEEK_API_KEY "DEEPSEEK_API_KEY"
ask_secret CODERABBIT_API_KEY "CODERABBIT_API_KEY"
ask_secret WEAVIATE_API_KEY "WEAVIATE_API_KEY"
ask_secret GITHUB_TOKEN "GITHUB_TOKEN (classic)"

# Pick AI provider (default openai)
AI_PROVIDER="${AI_PROVIDER:-openai}"

say "Secrets loaded ✅"

# ----------------------------
# 3) Write FlashTM8 env
# ----------------------------
FLASH_ENV="$ROOT/apps/flashtm8/.env"
say "Writing FlashTM8 env: $FLASH_ENV"

set_kv "$FLASH_ENV" "FLASH_NAME" "FlashTM8"
set_kv "$FLASH_ENV" "WORKSPACE_ROOT" "$ROOT"
set_kv "$FLASH_ENV" "SESSION_SECRET" "$SESSION_SECRET"

# Enable admin tools (you requested full control)
set_kv "$FLASH_ENV" "ALLOW_EXEC" "1"
set_kv "$FLASH_ENV" "ALLOW_WRITE" "1"

# Provider selection
set_kv "$FLASH_ENV" "AI_PROVIDER" "$AI_PROVIDER"
set_kv "$FLASH_ENV" "OPENAI_API_KEY" "$OPENAI_API_KEY"
set_kv "$FLASH_ENV" "OPENAI_MODEL" "${OPENAI_MODEL:-gpt-4.1-mini}"

set_kv "$FLASH_ENV" "GEMINI_API_KEY" "$GEMINI_API_KEY"
set_kv "$FLASH_ENV" "DEEPSEEK_API_KEY" "$DEEPSEEK_API_KEY"
set_kv "$FLASH_ENV" "CODERABBIT_API_KEY" "$CODERABBIT_API_KEY"
set_kv "$FLASH_ENV" "WEAVIATE_API_KEY" "$WEAVIATE_API_KEY"

set_kv "$FLASH_ENV" "CLICKUP_API_TOKEN" "$CLICKUP_API_TOKEN"
set_kv "$FLASH_ENV" "GITHUB_TOKEN" "$GITHUB_TOKEN"

set_kv "$FLASH_ENV" "SMTP_USER" "$SMTP_USER"
set_kv "$FLASH_ENV" "SMTP_PASS" "$SMTP_PASS"

set_kv "$FLASH_ENV" "OWNER_ID" "$OWNER_ID"
set_kv "$FLASH_ENV" "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
set_kv "$FLASH_ENV" "APP8X8ORG_BOT_TOKEN" "$APP8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "OUT8X8ORG_BOT_TOKEN" "$OUT8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "IN8X8ORG_BOT_TOKEN" "$IN8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "AIRDROP8X8ORG_BOT_TOKEN" "$AIRDROP8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "WALLET8X8ORG_BOT_TOKEN" "$WALLET8X8ORG_BOT_TOKEN"

chmod 600 "$FLASH_ENV" || true
say "FlashTM8 .env ready."

# ----------------------------
# 4) Write bot env
# ----------------------------
BOT_ENV="$ROOT/services/bot/.env"
say "Writing Bot env: $BOT_ENV"

set_kv "$BOT_ENV" "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
set_kv "$BOT_ENV" "OWNER_ID" "$OWNER_ID"
set_kv "$BOT_ENV" "SMTP_USER" "$SMTP_USER"
set_kv "$BOT_ENV" "SMTP_PASS" "$SMTP_PASS"

chmod 600 "$BOT_ENV" || true
say "Bot .env ready."

# ----------------------------
# 5) Create start scripts
# ----------------------------
say "Creating start scripts..."

cat > "$ROOT/start_dashboard.sh" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/runner/workspace/repos/8x8org"
export PORT="${PORT:-5000}"
cd "$ROOT"
echo "✅ Starting Sovereign Dashboard on PORT=$PORT"
python sovereign_dashboard_full.py
SH

cat > "$ROOT/start_bot.sh" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/runner/workspace/repos/8x8org"
cd "$ROOT/services/bot"
echo "✅ Starting Telegram bot..."
python telegram_webapp_bot.py
SH

chmod 755 "$ROOT/start_dashboard.sh" "$ROOT/start_bot.sh" 2>/dev/null || true
chmod +x  "$ROOT/start_dashboard.sh" "$ROOT/start_bot.sh" 2>/dev/null || true

say "Start scripts created:"
ls -la "$ROOT/start_dashboard.sh" "$ROOT/start_bot.sh" || true

# ----------------------------
# 6) Start dashboard safely (bash always works)
# ----------------------------
echo
say "Starting dashboard now..."
bash "$ROOT/start_dashboard.sh"
