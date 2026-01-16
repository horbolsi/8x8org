#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
TS="$(date '+%Y%m%d-%H%M%S')"

OUT_DIR="$ROOT/archive/auto"
mkdir -p "$OUT_DIR"

OUT="$OUT_DIR/workspace-backup-$TS.tar.gz"

tar \
  --exclude='./.git' \
  --exclude='./projects' \
  --exclude='./logs' \
  --exclude='./runtime' \
  --exclude='./archive' \
  --exclude='./**/__pycache__' \
  --exclude='./**/*.db' \
  --exclude='./**/*.sqlite' \
  --exclude='./**/*.sqlite3' \
  --exclude='./**/node_modules' \
  --exclude='./.venv' \
  --exclude='./venv' \
  --exclude='./.tools' \
  -czf "$OUT" .

echo "✅ Backup written: $OUT"

KEEP="${KEEP_BACKUPS:-72}"
ls -1t "$OUT_DIR"/workspace-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP+1))" | xargs -r rm -f
