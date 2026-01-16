#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
import re

p = Path("apps/dashboard/server.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) Make SocketIO init quieter + termux-friendly
# Try to replace an existing SocketIO(...) assignment
pat = re.compile(r"(?m)^(socketio\s*=\s*SocketIO\()\s*app\s*(,.*)?\)\s*$")
m = pat.search(s)
if m:
    # Replace whole line with a known-good config
    s = pat.sub("socketio = SocketIO(app, async_mode='threading', cors_allowed_origins='*', logger=False, engineio_logger=False)", s, count=1)
else:
    # If no direct assignment found, try to find SocketIO(app...) anywhere
    s2 = re.sub(r"SocketIO\(\s*app\s*(,.*?)?\)",
                "SocketIO(app, async_mode='threading', cors_allowed_origins='*', logger=False, engineio_logger=False)",
                s, count=1, flags=re.DOTALL)
    s = s2

# 2) Ensure run() allows werkzeug + no reloader
def fix_run(match):
    inside = match.group(1)
    # force allow_unsafe_werkzeug=True
    if "allow_unsafe_werkzeug" in inside:
        inside = re.sub(r"allow_unsafe_werkzeug\s*=\s*(True|False)", "allow_unsafe_werkzeug=True", inside)
    else:
        inside = inside.rstrip() + ", allow_unsafe_werkzeug=True"
    # avoid double-starting
    if "use_reloader" not in inside:
        inside = inside.rstrip() + ", use_reloader=False"
    return f"socketio.run({inside})"

s = re.sub(r"socketio\.run\((.*?)\)", fix_run, s, count=1, flags=re.DOTALL)

p.write_text(s, encoding="utf-8")
print("✅ Patched apps/dashboard/server.py (SocketIO quieter + threading + allow_unsafe_werkzeug).")
PY

python -m py_compile apps/dashboard/server.py
echo "✅ fix040 done. Restart dashboard."
