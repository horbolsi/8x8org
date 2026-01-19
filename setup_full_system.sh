#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RED="\033[0;31m"; NC="\033[0m"
say(){ echo -e "${GREEN}✅${NC} $*"; }
warn(){ echo -e "${YELLOW}⚠️${NC} $*"; }
err(){ echo -e "${RED}❌${NC} $*"; }

# -----------------------------
# Detect repo root
# -----------------------------
ROOT="/home/runner/workspace/repos/8x8org"
if [ ! -d "$ROOT" ]; then
  err "Repo not found at $ROOT"
  echo "Fix by cd into correct folder then run again."
  exit 1
fi

say "Repo root: $ROOT"

# -----------------------------
# 1) Fix requests/urllib3 issue
# -----------------------------
say "Fixing Python networking libs (requests/urllib3/six)..."
python -m pip install --upgrade --force-reinstall "requests>=2.32.3" "urllib3>=2.2.0" six >/dev/null 2>&1 || {
  warn "pip had warnings. Re-running with output:"
  python -m pip install --upgrade --force-reinstall "requests>=2.32.3" "urllib3>=2.2.0" six
}
say "Python libs fixed."

# -----------------------------
# Helper: write KEY=VALUE to env file (replace if exists)
# -----------------------------
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

# -----------------------------
# Helper: secure prompt for secret if missing
# -----------------------------
need_secret () {
  local var="$1"
  local label="$2"
  if [ -z "${!var:-}" ]; then
    echo
    echo "🔐 Paste ${label} now (hidden input):"
    read -r -s tmp
    echo
    export "$var"="$tmp"
  fi
}

# -----------------------------
# 2) Collect secrets (secure)
# You can also export them before running script:
# export OPENAI_API_KEY="..."
# -----------------------------
need_secret SESSION_SECRET "SESSION_SECRET"
need_secret SMTP_USER "SMTP_USER"
need_secret SMTP_PASS "SMTP_PASS"
need_secret CLICKUP_API_TOKEN "CLICKUP_API_TOKEN"
need_secret OWNER_ID "OWNER_ID"

# Telegram bots
need_secret TELEGRAM_BOT_TOKEN "TELEGRAM_BOT_TOKEN"
need_secret APP8X8ORG_BOT_TOKEN "app8x8org_BOT_TOKEN"
need_secret OUT8X8ORG_BOT_TOKEN "out8x8org_BOT_TOKEN"
need_secret IN8X8ORG_BOT_TOKEN "in8x8org_bot"
need_secret AIRDROP8X8ORG_BOT_TOKEN "airdrop8x8org_bot"
need_secret WALLET8X8ORG_BOT_TOKEN "wallet8x8org_bot"

# Providers
need_secret OPENAI_API_KEY "OPENAI_API_KEY"
need_secret GEMINI_API_KEY "Google Gemini API Key"
need_secret DEEPSEEK_API_KEY "DeepSeek API Key"
need_secret CODERABBIT_API_KEY "CodeRabbit API Key"
need_secret WEAVIATE_API_KEY "Weaviate API Key"

# GitHub classic token
need_secret GITHUB_TOKEN "GitHub Token (classic)"

# Optional X / xAI (only if you want)
if [ "${ENABLE_X_KEYS:-0}" = "1" ]; then
  need_secret XAI_API_KEY "xAI API Key"
  need_secret XAI_API_SECRET "xAI API Secret"
  need_secret X_BEARER_TOKEN "X Bearer Token"
fi

say "Secrets loaded into environment (not printed)."

# -----------------------------
# 3) FlashTM8 dashboard .env
# -----------------------------
FLASH_ENV="$ROOT/apps/flashtm8/.env"
say "Writing FlashTM8 env: $FLASH_ENV"

# Base settings
set_kv "$FLASH_ENV" "FLASH_NAME" "FlashTM8"
set_kv "$FLASH_ENV" "WORKSPACE_ROOT" "$ROOT"
set_kv "$FLASH_ENV" "AI_PROVIDER" "${AI_PROVIDER:-openai}"

# Admin mode (enable your full “agent” power)
# You asked for full system: enable them.
set_kv "$FLASH_ENV" "ALLOW_EXEC" "1"
set_kv "$FLASH_ENV" "ALLOW_WRITE" "1"

# Session secret
set_kv "$FLASH_ENV" "SESSION_SECRET" "$SESSION_SECRET"

# Provider keys
set_kv "$FLASH_ENV" "OPENAI_API_KEY" "$OPENAI_API_KEY"
set_kv "$FLASH_ENV" "OPENAI_MODEL" "${OPENAI_MODEL:-gpt-4.1-mini}"

set_kv "$FLASH_ENV" "GEMINI_API_KEY" "$GEMINI_API_KEY"
set_kv "$FLASH_ENV" "DEEPSEEK_API_KEY" "$DEEPSEEK_API_KEY"
set_kv "$FLASH_ENV" "CODERABBIT_API_KEY" "$CODERABBIT_API_KEY"
set_kv "$FLASH_ENV" "WEAVIATE_API_KEY" "$WEAVIATE_API_KEY"

# Ops services
set_kv "$FLASH_ENV" "CLICKUP_API_TOKEN" "$CLICKUP_API_TOKEN"
set_kv "$FLASH_ENV" "GITHUB_TOKEN" "$GITHUB_TOKEN"

# Telegram ownership
set_kv "$FLASH_ENV" "OWNER_ID" "$OWNER_ID"

# Telegram bot tokens
set_kv "$FLASH_ENV" "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
set_kv "$FLASH_ENV" "APP8X8ORG_BOT_TOKEN" "$APP8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "OUT8X8ORG_BOT_TOKEN" "$OUT8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "IN8X8ORG_BOT_TOKEN" "$IN8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "AIRDROP8X8ORG_BOT_TOKEN" "$AIRDROP8X8ORG_BOT_TOKEN"
set_kv "$FLASH_ENV" "WALLET8X8ORG_BOT_TOKEN" "$WALLET8X8ORG_BOT_TOKEN"

# Email SMTP
set_kv "$FLASH_ENV" "SMTP_USER" "$SMTP_USER"
set_kv "$FLASH_ENV" "SMTP_PASS" "$SMTP_PASS"

# Optional X / xAI
if [ "${ENABLE_X_KEYS:-0}" = "1" ]; then
  set_kv "$FLASH_ENV" "XAI_API_KEY" "$XAI_API_KEY"
  set_kv "$FLASH_ENV" "XAI_API_SECRET" "$XAI_API_SECRET"
  set_kv "$FLASH_ENV" "X_BEARER_TOKEN" "$X_BEARER_TOKEN"
fi

chmod 600 "$FLASH_ENV"
say "FlashTM8 .env ready (chmod 600)."

# -----------------------------
# 4) Bot service .env (if needed)
# -----------------------------
BOT_ENV="$ROOT/services/bot/.env"
say "Writing bot env: $BOT_ENV"

set_kv "$BOT_ENV" "TELEGRAM_BOT_TOKEN" "$TELEGRAM_BOT_TOKEN"
set_kv "$BOT_ENV" "OWNER_ID" "$OWNER_ID"
set_kv "$BOT_ENV" "SMTP_USER" "$SMTP_USER"
set_kv "$BOT_ENV" "SMTP_PASS" "$SMTP_PASS"
chmod 600 "$BOT_ENV"

say "Bot .env ready (chmod 600)."

# -----------------------------
# 5) Create easy start scripts
# -----------------------------
START_DASH="$ROOT/start_dashboard.sh"
cat > "$START_DASH" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export PORT="${PORT:-5000}"
cd "$ROOT"
echo "✅ Starting Sovereign Dashboard on PORT=$PORT"
python sovereign_dashboard_full.py
SH
chmod +x "$START_DASH"
say "Dashboard starter created: $START_DASH"

START_BOT="$ROOT/start_bot.sh"
cat > "$START_BOT" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/services/bot"
echo "✅ Starting Telegram WebApp Bot..."
python telegram_webapp_bot.py
SH
chmod +x "$START_BOT"
say "Bot starter created: $START_BOT"

# -----------------------------
# 6) Optional: Create FlashTM8 fallback helper (safe)
# -----------------------------
FALLBACK="$ROOT/apps/flashtm8/backend/ai_fallback_patch.py"
mkdir -p "$(dirname "$FALLBACK")"
cat > "$FALLBACK" << 'PY'
def fallback_answer(user_msg: str, ctx=None) -> str:
    ctx = ctx or []
    out = []
    out.append("⚡ FlashTM8 (Fallback Mode)\n")
    out.append("AI provider failed, but workspace index is available.\n")
    if not ctx:
        out.append("No matches found. Try 'Index Workspace' again.")
    else:
        out.append("Top matches:\n")
        for i, c in enumerate(ctx[:10], 1):
            out.append(f"{i}) {c.get('path')} score={c.get('score')}")
            snip = (c.get('snippet') or "").strip()
            if snip:
                out.append(snip[:800])
            out.append("")
    return "\n".join(out)
PY
say "Fallback helper created: $FALLBACK"

# -----------------------------
# Done
# -----------------------------
echo
say "FULL SYSTEM READY ✅"
echo "--------------------------------------------"
echo "Run dashboard:"
echo "  $START_DASH"
echo
echo "Open in browser:"
echo "  http://127.0.0.1:5000"
echo
echo "Run bot:"
echo "  $START_BOT"
echo
echo "FlashTM8 env:"
echo "  $FLASH_ENV"
echo "--------------------------------------------"
