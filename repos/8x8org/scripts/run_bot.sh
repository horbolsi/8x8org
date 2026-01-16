#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

# IMPORTANT: do NOT hardcode tokens in code. Put them in env or .env (not committed).
# export TELEGRAM_BOT_TOKEN="..."
# export DASHBOARD_URL="https://8x8org.youware.app"

python -m pip show python-telegram-bot >/dev/null 2>&1 || python -m pip install -U python-telegram-bot==21.6
python bot/telegram_webapp_bot.py
