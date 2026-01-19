#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$HERE/backend"
FRONTEND="$HERE/frontend"
RUNTIME="$HERE/runtime"
LOGS="$RUNTIME/logs"

mkdir -p "$LOGS"

echo "==> Starting Sovereign Console v2"

# Backend
echo "==> Installing backend deps (if needed)"
cd "$BACKEND"
if [ ! -d node_modules ]; then
  npm install
fi

echo "==> Starting backend on PORT=${PORT:-6060}"
( PORT="${PORT:-6060}" REPLIT="${REPLIT:-}" npm run dev > "$LOGS/backend.out" 2>&1 & echo $! > "$RUNTIME/backend.pid" )

# Frontend
echo "==> Installing frontend deps (if needed)"
cd "$FRONTEND"
if [ ! -d node_modules ]; then
  npm install
fi

echo "==> Starting frontend on http://127.0.0.1:5173"
( npm run dev > "$LOGS/frontend.out" 2>&1 & echo $! > "$RUNTIME/frontend.pid" )

echo ""
echo "✅ Backend:  http://127.0.0.1:${PORT:-6060}"
echo "✅ Frontend: http://127.0.0.1:5173"
echo ""
echo "Logs:"
echo "  $LOGS/backend.out"
echo "  $LOGS/frontend.out"
