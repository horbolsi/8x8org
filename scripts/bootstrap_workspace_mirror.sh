#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# 8x8org Workspace Mirror Bootstrap
# - Creates/updates:
#   - docs/HOW_TO_INSTALL.md
#   - README.md
#   - bin/wsync
#   - scripts/backup_workspace.sh
#   - scripts/install_termux_cron_backup.sh
#   - scripts/replit_backup_loop.sh
#   - .gitignore
# ============================================================

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT:-}" ]]; then
  echo "❌ Not inside a git repo. cd into the repo root and re-run."
  exit 1
fi
cd "$ROOT"

mkdir -p docs bin scripts logs archive/auto

cat > "$ROOT/.gitignore" <<'GITIGNORE'
# ==========================
# Workspace mirror ignores
# ==========================

projects/
logs/
runtime/
*.log

*.db
*.sqlite
*.sqlite3

.env
.env.*
**/*secret*
**/*token*
**/*key*
!docs/**

__pycache__/
*.py[cod]
.venv/
venv/
.envrc
.pytest_cache/
.mypy_cache/

node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

.replit
replit.nix
.tools/

*.bak.*
*.backup
*.tmp
*.swp
*~

archive/
!archive/README.md

repos/8x8org/archive/
GITIGNORE

mkdir -p "$ROOT/archive"
cat > "$ROOT/archive/README.md" <<'ARCH'
# archive/ (local-only)

This folder is for **local backups and cleanup snapshots**.

- It is intentionally **NOT tracked by git** (see `.gitignore`).
- Termux backups go to: `archive/auto/` as tar.gz files.
ARCH

cat > "$ROOT/scripts/backup_workspace.sh" <<'BACKUP'
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
BACKUP
chmod +x "$ROOT/scripts/backup_workspace.sh"

cat > "$ROOT/scripts/install_termux_cron_backup.sh" <<'CRON'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

CRON_EXPR="${1:-0 * * * *}"
ROOT="$(git rev-parse --show-toplevel)"
BACKUP_SH="$ROOT/scripts/backup_workspace.sh"
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/backup-cron.log"

mkdir -p "$LOG_DIR"
: > "$LOG_FILE" 2>/dev/null || true

pkg install -y cronie >/dev/null 2>&1 || true
pgrep -f crond >/dev/null 2>&1 || crond

tmp="$(mktemp)"
crontab -l 2>/dev/null | grep -v "scripts/backup_workspace.sh" > "$tmp" || true
echo "$CRON_EXPR /data/data/com.termux/files/usr/bin/bash '$BACKUP_SH' >> '$LOG_FILE' 2>&1" >> "$tmp"
crontab "$tmp"
rm -f "$tmp"

echo "✅ Installed Termux cron backup: $CRON_EXPR"
echo "log: $LOG_FILE"
CRON
chmod +x "$ROOT/scripts/install_termux_cron_backup.sh"

cat > "$ROOT/scripts/replit_backup_loop.sh" <<'RLOOP'
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
RLOOP
chmod +x "$ROOT/scripts/replit_backup_loop.sh"

cat > "$ROOT/bin/wsync" <<'WSYNC'
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(git rev-parse --show-toplevel)"

ts(){ date '+%Y-%m-%d %H:%M:%S'; }

FLAG_DIR="${TMPDIR:-$HOME/.cache}"
mkdir -p "$FLAG_DIR"
FLAG_FILE="$FLAG_DIR/wsync_stashed.flag"

status_clean(){ [[ -z "$(git status --porcelain)" ]]; }

auto_stash_begin() {
  if status_clean; then echo "✅ clean"; echo "0" > "$FLAG_FILE"; return 0; fi
  echo "ℹ️ stashing changes"
  git stash push -u -m "wsync auto-stash $(ts)" >/dev/null
  echo "1" > "$FLAG_FILE"
}

auto_stash_end() {
  if [[ "$(cat "$FLAG_FILE" 2>/dev/null || echo 0)" == "1" ]]; then
    echo "ℹ️ restoring stash"
    git stash pop >/dev/null || { echo "⚠️ stash pop conflict"; exit 1; }
  fi
}

ensure_on_branch() {
  git symbolic-ref -q HEAD >/dev/null 2>&1 || { echo "⚠️ DETACHED HEAD → run: bash bin/wsync rescue:main"; exit 2; }
}

pull_cmd() {
  auto_stash_begin
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    git pull --rebase
  else
    git pull --rebase origin main
  fi
  auto_stash_end
}

push_cmd() {
  ensure_on_branch
  git add -A
  git commit -m "workspace sync $(ts)" >/dev/null 2>&1 || true
  git push
}

rescue_main() {
  git fetch origin --prune
  CURRENT="$(git rev-parse HEAD)"
  git checkout -B main origin/main
  git merge-base --is-ancestor "$CURRENT" HEAD >/dev/null 2>&1 || git cherry-pick "$CURRENT"
  git log --oneline --decorate -5
}

case "${1:-}" in
  pull) pull_cmd ;;
  push) push_cmd ;;
  sync) pull_cmd; push_cmd ;;
  backup) KEEP_BACKUPS="${KEEP_BACKUPS:-72}" bash scripts/backup_workspace.sh ;;
  doctor) echo "root: $(pwd)"; echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo DETACHED)"; git remote -v; git status --porcelain; crontab -l 2>/dev/null || echo "(no crontab)";;
  rescue:main) rescue_main ;;
  *) echo "Usage: bash bin/wsync {pull|push|sync|backup|doctor|rescue:main}"; exit 2;;
esac
WSYNC
chmod +x "$ROOT/bin/wsync"

# NOTE: Full HOW_TO_INSTALL content is written by your bootstrap script
# (your full version can be pasted into bootstrap later without terminal issues).
# For now, we create placeholder that bootstrap can overwrite.
cat > "$ROOT/docs/HOW_TO_INSTALL.md" <<'DOC'
# HOW_TO_INSTALL.md

This file will be written/updated by:
  bash scripts/bootstrap_workspace_mirror.sh

If you are reading this, run:
  bash scripts/bootstrap_workspace_mirror.sh
DOC

cat > "$ROOT/README.md" <<'README'
# 8x8org Workspace Mirror

Run:
  bash scripts/bootstrap_workspace_mirror.sh

Then:
  bash bin/wsync sync
README

echo "✅ bootstrap script written: scripts/bootstrap_workspace_mirror.sh"
echo "Next:"
echo "  bash scripts/bootstrap_workspace_mirror.sh"
