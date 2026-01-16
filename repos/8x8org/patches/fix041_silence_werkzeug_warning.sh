#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

DEV="tools/dev"
[ -f "$DEV" ] || { echo "❌ missing tools/dev"; exit 1; }

python - <<'PY'
from pathlib import Path
p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

# Inject env vars only for dash:start/restart
# We'll add these exports near the top, after set -Eeuo pipefail if present.
if "FLASK_ENV=development" not in s:
    lines = s.splitlines()
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if (not inserted) and ("set -Eeuo pipefail" in line):
            out.append("")
            out.append("# Termux dev mode: silence Flask-SocketIO werkzeug production warning")
            out.append("export FLASK_ENV=development")
            out.append("export FLASK_DEBUG=0")
            inserted = True
    s = "\n".join(out) + ("\n" if not s.endswith("\n") else "")
    p.write_text(s, encoding="utf-8")
    print("✅ Patched tools/dev: set FLASK_ENV=development for dashboard runs.")
else:
    print("ℹ️ tools/dev already has FLASK_ENV=development")
PY

sed -i 's/\r$//' tools/dev
chmod +x tools/dev 2>/dev/null || true

echo "✅ fix041 done. Restart dashboard."
