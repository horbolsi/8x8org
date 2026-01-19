#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
ENVFILE="$REPO/apps/flashtm8_ultimate/.env"
PORT="${PORT:-5000}"

set -a
[ -f "$ENVFILE" ] && . "$ENVFILE"
set +a

export PORT="$PORT"

echo "==============================================="
echo "⚡ FlashTM8 ULTIMATE"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "   Workspace: ${WORKSPACE_ROOT:-$REPO}"
echo "   URL: http://127.0.0.1:${PORT}"
echo "==============================================="

cd "$REPO/apps/flashtm8_ultimate/backend"
python app.py
