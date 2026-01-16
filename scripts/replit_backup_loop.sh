#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
INTERVAL="${1:-3600}"

mkdir -p "$ROOT/logs"
LOG="$ROOT/logs/replit-backup-loop.log"

echo "✅ Replit backup loop starting (interval=${INTERVAL}s)" | tee -a "$LOG"

while true; do
  ( cd "$ROOT" && KEEP_BACKUPS="${KEEP_BACKUPS:-72}" bash "$ROOT/scripts/backup_workspace.sh" ) >> "$LOG" 2>&1 || true
  sleep "$INTERVAL"
done
