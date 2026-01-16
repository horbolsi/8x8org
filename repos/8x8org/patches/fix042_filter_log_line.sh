#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

needle = "Werkzeug appears to be used in a production deployment"
if needle in s:
    print("ℹ️ tools/dev already mentions the needle; skipping edit.")
    raise SystemExit(0)

# Replace direct redirect ">> dashboard.out" with a filter pipe into the file (no shell metacharacters in dashboard UI; this is tools/dev only)
s2 = s.replace(
    ">> \"$DASH_LOG\" 2>&1 &",
    "2>&1 | sed '/Werkzeug appears to be used in a production deployment/d' >> \"$DASH_LOG\" &"
)

if s2 == s:
    print("❌ Could not find the expected log redirection pattern in tools/dev.")
    print("   Search for: DASH_LOG or dashboard.out and paste that section here.")
    raise SystemExit(1)

p.write_text(s2, encoding="utf-8")
print("✅ Patched tools/dev: filtered the Werkzeug warning line from dashboard log.")
PY

sed -i 's/\r$//' tools/dev
chmod +x tools/dev 2>/dev/null || true
echo "✅ fix042 done. Restart dashboard."
