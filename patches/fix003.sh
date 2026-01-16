#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

T="templates/sovereign_full.html"

if [ ! -f "$T" ]; then
  echo "❌ Missing $T"
  exit 1
fi

python - <<'PY'
from pathlib import Path
p = Path("templates/sovereign_full.html")
s = p.read_text(encoding="utf-8", errors="ignore")

# Replace websocket-only with polling (safe in Termux/Werkzeug)
s2 = s.replace("const socket = io({transports: ['websocket']});",
               "const socket = io({transports: ['polling'], upgrade: false});")

# If it wasn't found (maybe different formatting), do a softer fallback:
if s2 == s:
    s2 = s.replace("const socket = io({transports: ['websocket']})",
                   "const socket = io({transports: ['polling'], upgrade: false})")

# If still unchanged, just remove transports forcing entirely
if s2 == s:
    s2 = s.replace("const socket = io({transports: ['websocket']});",
                   "const socket = io();")

p.write_text(s2, encoding="utf-8")
print("✅ Patched Socket.IO client to polling (no websocket-only).")
PY

echo "✅ fix003 done. Restart server."
