#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="$HERE/runtime"

kill_pid() {
  local f="$1"
  if [ -f "$f" ]; then
    local pid
    pid="$(cat "$f" || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping PID $pid"
      kill "$pid" || true
    fi
    rm -f "$f"
  fi
}

kill_pid "$RUNTIME/backend.pid"
kill_pid "$RUNTIME/frontend.pid"

echo "✅ Sovereign Console v2 stopped"
