#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
import re

p = Path("apps/dashboard/server.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Ensure os is imported
if not re.search(r'(?m)^\s*import\s+os\s*$', s):
    # Insert import os near the top after other imports
    s = re.sub(r'(?m)^(import\s+[^\n]+\n)', r'\1import os\n', s, count=1)

# Replace/insert DEFAULT_PORT to respect $PORT
# Try common patterns first
replaced = False

# Pattern A: DEFAULT_PORT = 5000 (or any int)
s2, n = re.subn(r'(?m)^DEFAULT_PORT\s*=\s*\d+\s*$',
                "DEFAULT_PORT = int(os.environ.get('PORT', os.environ.get('DASH_PORT', '5000')))",
                s, count=1)
if n:
    s = s2
    replaced = True

# Pattern B: DEFAULT_PORT = int(...)
if not replaced:
    s2, n = re.subn(r'(?m)^DEFAULT_PORT\s*=\s*int\([^\n]*\)\s*$',
                    "DEFAULT_PORT = int(os.environ.get('PORT', os.environ.get('DASH_PORT', '5000')))",
                    s, count=1)
    if n:
        s = s2
        replaced = True

# If no DEFAULT_PORT exists, add one near DEFAULT_HOST or near top config area
if not replaced:
    if "DEFAULT_HOST" in s:
        s = re.sub(r'(?m)^DEFAULT_HOST\s*=\s*([^\n]+)\s*$',
                   r"DEFAULT_HOST = \1\nDEFAULT_PORT = int(os.environ.get('PORT', os.environ.get('DASH_PORT', '5000')))",
                   s, count=1)
        replaced = True
    else:
        # Put near top after imports
        s = re.sub(r'(?s)\A(.*?\n)(\s*#|\s*def|\s*class)',
                   r"\1DEFAULT_PORT = int(os.environ.get('PORT', os.environ.get('DASH_PORT', '5000')))\n\2",
                   s, count=1)
        replaced = True

p.write_text(s, encoding="utf-8")
print("✅ Patched apps/dashboard/server.py to respect $PORT (and $DASH_PORT fallback).")
PY

python -m py_compile apps/dashboard/server.py
echo "✅ fix051 done."
