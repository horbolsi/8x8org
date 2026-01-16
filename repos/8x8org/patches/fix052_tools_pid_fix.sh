#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
import re

p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) Fix start: remove the background pipe-to-sed so $! is Python (not sed)
# Replace: 2>&1 | sed '/Werkzeug .../d' >> "$DASH_LOG" &
s2 = re.sub(
    r'2>&1\s*\|\s*sed\s+[^>]*>>\s*"\$DASH_LOG"\s*&',
    r'>> "$DASH_LOG" 2>&1 &',
    s
)

# 2) Filter the noisy Werkzeug line only when tailing (safe, no pid issues)
# Replace a plain tail with tail | sed filter if present
needle = "Werkzeug appears to be used in a production deployment"
if "dash:tail" in s2:
    s3 = re.sub(
        r'(?m)^(.*tail\s+-n\s+\$\{LINES:-\d+\}\s+"\$DASH_LOG"\s*)$',
        rf"\1 | sed '/{needle}/d'",
        s2
    )
    s2 = s3

p.write_text(s2, encoding="utf-8")
print("✅ Patched tools/dev: correct PID tracking + filter warning only in tail.")
PY

sed -i 's/\r$//' tools/dev
chmod +x tools/dev 2>/dev/null || true
echo "✅ fix052 done."
