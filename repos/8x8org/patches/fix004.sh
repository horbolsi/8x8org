#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# --- 1) Patch the HTML Socket.IO client to always start fresh
python - <<'PY'
from pathlib import Path
import re

p = Path("templates/sovereign_full.html")
s = p.read_text(encoding="utf-8", errors="ignore")

# Replace FIRST socket init line with a "fresh session" polling config
# (forceNew prevents reusing old sid across reloads/restarts)
s2 = re.sub(
    r"const\s+socket\s*=\s*io\([^;]*\);",
    "const socket = io({transports: ['polling'], upgrade: false, withCredentials: true, forceNew: true});",
    s,
    count=1
)

p.write_text(s2, encoding="utf-8")
print("✅ HTML: socket init set to polling + forceNew.")
PY

# --- 2) Patch Python SocketIO init to silence engine.io/socket.io logs
python - <<'PY'
from pathlib import Path
import re

p = Path("sovereign_dashboard_full.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Ensure SocketIO(...) has logger flags
def patch_socketio_line(text: str) -> str:
    # replace the first "socketio = SocketIO(...)" call
    pat = re.compile(r"^socketio\s*=\s*SocketIO\((.*)\)\s*$", re.M)
    m = pat.search(text)
    if not m:
        return text
    inside = m.group(1)

    # If already patched, skip
    if "engineio_logger" in inside or "logger=" in inside:
        return text

    # Add logger flags near end
    new_inside = inside.rstrip()
    if new_inside.endswith(","):
        new_inside += " "
    else:
        new_inside += ", "

    new_inside += "logger=False, engineio_logger=False"
    return text[:m.start()] + f"socketio = SocketIO({new_inside})" + text[m.end():]

s2 = patch_socketio_line(s)

# Add import logging if missing
if "import logging" not in s2:
    # insert after `import json` if present, else after first import block
    if "import json\n" in s2:
        s2 = s2.replace("import json\n", "import json\nimport logging\n", 1)
    else:
        s2 = "import logging\n" + s2

# Silence engineio/socketio logging inside main() before socketio.run(...)
if "logging.getLogger(\"engineio\")" not in s2:
    s2 = re.sub(
        r"(print\(f\"   URL: http://\{DEFAULT_HOST\}:\{DEFAULT_PORT\}\"\)\n)",
        r"\1    logging.getLogger('engineio').setLevel(logging.ERROR)\n    logging.getLogger('socketio').setLevel(logging.ERROR)\n",
        s2,
        count=1
    )

p.write_text(s2, encoding="utf-8")
print("✅ Python: SocketIO logger disabled + engineio/socketio log level set to ERROR.")
PY

echo "✅ fix004 done. Restart the server."
