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
