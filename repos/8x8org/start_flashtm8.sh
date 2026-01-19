#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
ENVFILE="$REPO/apps/flashtm8/.env"
PORT="${PORT:-5000}"

# Load env safely (quoted values required)
if [ -f "$ENVFILE" ]; then
  set -a
  . "$ENVFILE"
  set +a
fi

export PORT="$PORT"

echo "==============================================="
echo "⚡ FlashTM8 AI Dashboard"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "   Workspace: ${WORKSPACE_ROOT:-$REPO}"
echo "   URL: http://127.0.0.1:${PORT}"
echo "==============================================="

cd "$REPO/apps/flashtm8/backend"
python app.py
