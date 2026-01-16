#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

echo "== patch apps/dashboard/server.py to avoid noisy Werkzeug prod warning =="

python - <<'PY'
from pathlib import Path
import re

p = Path("apps/dashboard/server.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) Ensure socketio.run uses allow_unsafe_werkzeug=True (Termux/Werkzeug needs it),
# but also avoid Flask-SocketIO raising a RuntimeError.
# We'll force allow_unsafe_werkzeug=True and quiet Werkzeug prod warning via env.
s2 = s

# force allow_unsafe_werkzeug=True if present
s2 = re.sub(
    r"socketio\.run\((.*?allow_unsafe_werkzeug\s*=\s*)False(.*?\)\s*)",
    r"socketio.run(\1True\2",
    s2,
    flags=re.DOTALL
)

# if allow_unsafe_werkzeug not present, add it (best effort)
if "socketio.run(" in s2 and "allow_unsafe_werkzeug" not in s2:
    s2 = re.sub(r"socketio\.run\((.*?)\)",
                r"socketio.run(\1, allow_unsafe_werkzeug=True)",
                s2, count=1, flags=re.DOTALL)

# 2) Add a tiny env-based quieting for Werkzeug warning line (harmless).
# We'll set WERKZEUG_RUN_MAIN guard / and a flag to reduce warnings output.
inject = "\n# Termux note: Werkzeug is used for local dev. We silence the noisy production warning.\nos.environ.setdefault('WERKZEUG_PROD_WARNING', '0')\n"
if "WERKZEUG_PROD_WARNING" not in s2:
    # insert after imports (after 'import os' if possible)
    if "import os" in s2:
        s2 = s2.replace("import os", "import os" + inject, 1)
    else:
        s2 = inject + s2

p.write_text(s2, encoding="utf-8")
print("✅ Patched server.py (allow_unsafe_werkzeug=True + quiet flag)")
PY

echo "== patch tools/dev to always start correct app =="

python - <<'PY'
from pathlib import Path
p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

# Prefer wrapper for stable entrypoint
s = s.replace("python apps/dashboard/server.py", "python sovereign_dashboard_full.py")
# keep bot path canonical
s = s.replace("python bot/telegram_webapp_bot.py", "python services/bot/telegram_webapp_bot.py")

p.write_text(s, encoding="utf-8")
print("✅ Patched tools/dev to use sovereign_dashboard_full.py wrapper")
PY

echo "== compile check =="
python -m py_compile apps/dashboard/server.py
python -m py_compile sovereign_dashboard_full.py

echo "✅ fix021 complete. Restart dashboard."
