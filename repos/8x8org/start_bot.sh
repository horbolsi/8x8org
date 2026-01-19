#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/runner/workspace/repos/8x8org"
cd "$ROOT/services/bot"
echo "✅ Starting Telegram bot..."
python telegram_webapp_bot.py
