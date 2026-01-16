#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(pwd)"

# 0) normalize CRLF in scripts/patches
sed -i 's/\r$//' scripts/*.sh 2>/dev/null || true
sed -i 's/\r$//' patches/*.sh 2>/dev/null || true

# 1) remove the weird templates^M folder if exists
rm -rf $'templates\r' 2>/dev/null || true
rm -rf $'templates\015' 2>/dev/null || true

# 2) create clean structure (non-breaking, additive)
mkdir -p \
  apps/dashboard \
  apps/web \
  services/bot \
  infra/env \
  infra/systemd \
  runtime/logs \
  runtime/db \
  runtime/workspace \
  tools \
  docs \
  archive

# 3) keep canonical templates in one place
mkdir -p apps/dashboard/templates
if [ -f templates/sovereign_full.html ]; then
  cp -f templates/sovereign_full.html apps/dashboard/templates/sovereign_full.html
fi
if [ -f templates/dashboard.html ]; then
  cp -f templates/dashboard.html apps/dashboard/templates/dashboard.html
fi

# 4) move noisy files into archive (safe, non-destructive)
for f in \
  auto-sync-daemon.log background.log \
  AutoSync_Test*.md Cron_AutoSync_Test.md Daemon_Sync_Test.md FINAL_SYNC_OK.md \
  REplit_to_Termux_Test.md SYNC_TEST*.md Sync_Fix_Test.md Termux_AutoSync_Test.md \
  test-*.sh quick-test.sh zipFile.zip
do
  if [ -e "$f" ]; then
    mkdir -p archive/termux_tests
    mv -f "$f" archive/termux_tests/ || true
  fi
done

# 5) unify python dashboard entrypoint (copy for now, keep original working file)
#    We'll later refactor sovereign_dashboard_full.py into a package; for now just import/run it.
cat > apps/dashboard/server.py <<'PY'
#!/usr/bin/env python3
"""
apps/dashboard/server.py

Canonical entrypoint for the Sovereign Dashboard.
Keeps backward compatibility by importing the current monolith.

Run:
  source scripts/env.sh
  python apps/dashboard/server.py
"""
from __future__ import annotations
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

# Ensure Flask templates point at apps/dashboard/templates first
os.environ.setdefault("SOVEREIGN_TEMPLATES_DIR", str(ROOT / "apps" / "dashboard" / "templates"))

import sovereign_dashboard_full  # noqa: E402

if __name__ == "__main__":
    sovereign_dashboard_full.main()
PY
chmod +x apps/dashboard/server.py

# 6) make bot location canonical (copy only)
if [ -f bot/telegram_webapp_bot.py ]; then
  cp -f bot/telegram_webapp_bot.py services/bot/telegram_webapp_bot.py
fi

# 7) add a single dev command wrapper
cat > tools/dev <<'BASH'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${VENV:-$HOME/.venvs/8x8org}"

dash_pid_file="$ROOT/runtime/dashboard.pid"
bot_pid_file="$ROOT/runtime/bot.pid"

activate() {
  if [ -f "$VENV/bin/activate" ]; then
    # shellcheck disable=SC1090
    source "$VENV/bin/activate"
  fi
}

dash_start() {
  activate
  cd "$ROOT"
  mkdir -p runtime
  if [ -f "$dash_pid_file" ] && kill -0 "$(cat "$dash_pid_file")" 2>/dev/null; then
    echo "Dashboard already running (pid=$(cat "$dash_pid_file"))"
    exit 0
  fi
  nohup python apps/dashboard/server.py > runtime/dashboard.out 2>&1 &
  echo $! > "$dash_pid_file"
  echo "✅ Dashboard started pid=$! (log: runtime/dashboard.out)"
}

dash_stop() {
  if [ -f "$dash_pid_file" ]; then
    pid="$(cat "$dash_pid_file")"
    kill "$pid" 2>/dev/null || true
    rm -f "$dash_pid_file"
    echo "✅ Dashboard stopped"
  else
    echo "Dashboard not running"
  fi
}

bot_start() {
  activate
  cd "$ROOT"
  mkdir -p runtime
  if [ -f "$bot_pid_file" ] && kill -0 "$(cat "$bot_pid_file")" 2>/dev/null; then
    echo "Bot already running (pid=$(cat "$bot_pid_file"))"
    exit 0
  fi
  if [ ! -f services/bot/telegram_webapp_bot.py ]; then
    echo "❌ services/bot/telegram_webapp_bot.py missing"
    exit 1
  fi
  nohup python services/bot/telegram_webapp_bot.py > runtime/bot.out 2>&1 &
  echo $! > "$bot_pid_file"
  echo "✅ Bot started pid=$! (log: runtime/bot.out)"
}

bot_stop() {
  if [ -f "$bot_pid_file" ]; then
    pid="$(cat "$bot_pid_file")"
    kill "$pid" 2>/dev/null || true
    rm -f "$bot_pid_file"
    echo "✅ Bot stopped"
  else
    echo "Bot not running"
  fi
}

status() {
  echo "--- status ---"
  if [ -f "$dash_pid_file" ] && kill -0 "$(cat "$dash_pid_file")" 2>/dev/null; then
    echo "dashboard: RUNNING pid=$(cat "$dash_pid_file")"
  else
    echo "dashboard: stopped"
  fi
  if [ -f "$bot_pid_file" ] && kill -0 "$(cat "$bot_pid_file")" 2>/dev/null; then
    echo "bot: RUNNING pid=$(cat "$bot_pid_file")"
  else
    echo "bot: stopped"
  fi
  echo "logs:"
  echo "  runtime/dashboard.out"
  echo "  runtime/bot.out"
}

case "${1:-}" in
  dash:start) dash_start ;;
  dash:stop)  dash_stop ;;
  bot:start)  bot_start ;;
  bot:stop)   bot_stop ;;
  status)     status ;;
  *)
    cat <<USAGE
Usage:
  tools/dev status
  tools/dev dash:start
  tools/dev dash:stop
  tools/dev bot:start
  tools/dev bot:stop
USAGE
    ;;
esac
BASH
chmod +x tools/dev

# 8) write workflow docs
cat > docs/WORKFLOW.md <<'MD'
# 8x8org Workflow (Termux-first)

## Canonical entrypoints
- Dashboard: `python apps/dashboard/server.py`
- Bot: `python services/bot/telegram_webapp_bot.py`

## One command dev tool
- `./tools/dev status`
- `./tools/dev dash:start` (runs in background, log in `runtime/dashboard.out`)
- `./tools/dev dash:stop`
- `./tools/dev bot:start`
- `./tools/dev bot:stop`

## Editing on phone
Your repo lives in:
`/storage/emulated/0/Workspace/repos/8x8org`

Use Samsung Files to edit, then restart:
`./tools/dev dash:stop && ./tools/dev dash:start`

## Notes
- Keep runtime outputs in `runtime/`
- Keep old experiments in `archive/`
MD

echo "✅ Restructure complete."
echo "Next:"
echo "  ./tools/dev status"
echo "  ./tools/dev dash:start"
