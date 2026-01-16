#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
import re

p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

# We will:
# 1) define DASH_PORT default=5000
# 2) if PORT already set, use it
# 3) if 5000 busy, switch to 5001
# 4) export PORT so server uses it

if "AUTO_PORT_PICK" in s:
    print("ℹ️ tools/dev already patched for auto port.")
    raise SystemExit(0)

# Insert port logic after DASH_LOG is defined (safe anchor)
anchor = "DASH_LOG="
m = re.search(r"(?m)^(DASH_LOG=.*)$", s)
if not m:
    raise SystemExit("❌ Couldn't find DASH_LOG= in tools/dev")

insert = r"""
# AUTO_PORT_PICK
DASH_PORT="${PORT:-5000}"
if command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"$DASH_PORT" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
    echo "ℹ️ Port $DASH_PORT busy; switching to 5001"
    DASH_PORT=5001
  fi
fi
export PORT="$DASH_PORT"
"""

s2 = s[:m.end()] + insert + s[m.end():]

p.write_text(s2, encoding="utf-8")
print("✅ Patched tools/dev: auto-pick PORT (5000 -> 5001 if busy).")
PY

sed -i 's/\r$//' tools/dev
chmod +x tools/dev 2>/dev/null || true
echo "✅ fix050 done."
