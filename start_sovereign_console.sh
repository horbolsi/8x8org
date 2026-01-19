#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
APP="$REPO/apps/sovereign_console"
ENVFILE="$APP/.env"

# load env
set -a
source "$ENVFILE"
set +a

PORT="${PORT:-5000}"

# venv
if [[ -f "$HOME/.venvs/sovereign-ai/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.venvs/sovereign-ai/bin/activate"
fi

cd "$APP/backend"
echo "==============================================="
echo "⚡ Sovereign Console Running"
echo "   URL: http://127.0.0.1:${PORT}"
echo "   Provider: ${AI_PROVIDER:-auto}"
echo "==============================================="
python -m uvicorn app:app --host 0.0.0.0 --port "$PORT"
