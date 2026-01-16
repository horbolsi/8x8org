#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

CRON_EXPR="${1:-0 * * * *}"  # default: hourly
ROOT="$(git rev-parse --show-toplevel)"
BACKUP_SH="$ROOT/scripts/backup_workspace.sh"
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/backup-cron.log"
mkdir -p "$LOG_DIR"

pkg install -y cronie >/dev/null 2>&1 || true

# Start crond if not running
pgrep -f crond >/dev/null 2>&1 || crond

# Install/update cron line (idempotent)
tmp="$(mktemp)"
crontab -l 2>/dev/null | grep -v "scripts/backup_workspace.sh" > "$tmp" || true
echo "$CRON_EXPR /data/data/com.termux/files/usr/bin/bash '$BACKUP_SH' >> '$LOG_FILE' 2>&1" >> "$tmp"
crontab "$tmp"
rm -f "$tmp"

echo "✅ Installed cron backup"
echo " - schedule: $CRON_EXPR"
echo " - cmd:      $BACKUP_SH"
echo " - log:      $LOG_FILE"
echo
echo "Check:"
echo "  crontab -l"
echo "  pgrep -f crond || echo 'crond not running'"
