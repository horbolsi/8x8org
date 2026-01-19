#!/usr/bin/env bash
PORT="${PORT:-5000}"
export PORT
echo "✅ Using PORT=$PORT"
set -euo pipefail

# Always run from repo root (works on Replit + Termux)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Use PORT if provided (Replit sets this)
export HOST="${HOST:-0.0.0.0}"

echo "✅ Repo: $ROOT"
echo "✅ Starting dashboard on $HOST:$PORT"
echo "➡️  http://$HOST:$PORT"

python sovereign_dashboard_full.py
