#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

# Add -u to python runs so logs flush immediately
s2 = s.replace("python apps/dashboard/server.py", "python -u apps/dashboard/server.py")

if s2 == s:
    print("ℹ️ No change needed (already unbuffered or different command).")
else:
    p.write_text(s2, encoding="utf-8")
    print("✅ Patched tools/dev: python -u for immediate logs.")
PY

sed -i 's/\r$//' tools/dev
chmod +x tools/dev 2>/dev/null || true
echo "✅ fix043 done. Restart dashboard."
