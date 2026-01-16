#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

OUT_DIR="${BACKUP_DIR:-$ROOT/archive/auto}"
mkdir -p "$OUT_DIR"

STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT="$OUT_DIR/workspace-backup-$STAMP.tar.gz"

tar -czf "$OUT" \
  --exclude=".git" \
  --exclude="projects" \
  --exclude="logs" \
  --exclude="runtime" \
  --exclude="archive" \
  --exclude="**/node_modules" \
  --exclude="**/dist" \
  --exclude="**/.venv" \
  --exclude="**/__pycache__" \
  .

echo "✅ Backup written: $OUT"

# Keep only last N backups (default: 72). Override with: export KEEP_BACKUPS=168
KEEP="${KEEP_BACKUPS:-72}"
ls -1t "$OUT_DIR"/workspace-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP+1))" | xargs -r rm -f
