#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
import re

p = Path("tools/dev")
s = p.read_text(encoding="utf-8", errors="ignore")

needle = "Werkzeug appears to be used in a production deployment"

# 1) FIX: remove any bad pipe that got appended after ";;" in the case statement
s = re.sub(
    r'(\bdash:tail\)\s*tail_logs\s*"\$DASH_LOG"\s*;;)\s*\|\s*sed[^\n]*',
    r"\1",
    s
)
s = re.sub(
    r'(;;)\s*\|\s*sed\s*/\s*Werkzeug\s+appears.*?/d\s*',
    r"\1",
    s
)

# 2) Add filtering INSIDE tail_logs (safe, keeps correct PID tracking)
# Replace tail commands in the tail_logs function (only once each)
def patch_tail_cmd(cmd: str) -> str:
    if "| sed" in cmd:
        return cmd
    # use -u to stream (works in GNU sed)
    return cmd + " | sed -u '/" + needle.replace("/", r"\/") + "/d'"

# Find tail_logs function block and patch within it
m = re.search(r"(?ms)^tail_logs\(\)\s*\{.*?^\}\s*$", s)
if not m:
    raise SystemExit("❌ Couldn't find tail_logs() function in tools/dev")

block = m.group(0)

# Patch first tail -n ... and first tail -f ... inside that function
block2 = block
block2, n1 = re.subn(r"(?m)^(\s*tail\s+-n\s+.*)$", lambda mm: patch_tail_cmd(mm.group(1)), block2, count=1)
block2, n2 = re.subn(r"(?m)^(\s*tail\s+-f\s+.*)$", lambda mm: patch_tail_cmd(mm.group(1)), block2, count=1)

# If no tail -n/-f matched, fallback to patch any "tail " line in that function
if n1 == 0 and n2 == 0:
    block2, _ = re.subn(r"(?m)^(\s*tail\s+.*)$", lambda mm: patch_tail_cmd(mm.group(1)), block2, count=1)

s = s[:m.start()] + block2 + s[m.end():]

# 3) Make `open` print the actual port (PORT already exported by tools/dev)
s = s.replace("URL: http://127.0.0.1:5000", "URL: http://127.0.0.1:${PORT:-5000}")

p.write_text(s, encoding="utf-8")
print("✅ Fixed tools/dev: removed bad case pipe, added safe tail filter, open uses $PORT")
PY

sed -i 's/\r$//' tools/dev
chmod +x tools/dev 2>/dev/null || true

# sanity check: bash syntax must be clean
bash -n tools/dev

echo "✅ fix054 done."
