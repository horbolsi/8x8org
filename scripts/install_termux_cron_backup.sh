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
