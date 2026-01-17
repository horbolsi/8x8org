#!/usr/bin/env bash
set -euo pipefail

# --- fix060_apply_youware_frontend.sh ---
# Applies patches/patch060_youware_frontend.zip to THIS repo (8x8org)
# Works even if your workspace root is a separate git repo.

# Repo root = parent of this script's folder (patches/..)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ZIP="patches/patch060_youware_frontend.zip"
if [ ! -f "$ZIP" ]; then
  echo "❌ Missing: $ZIP"
  echo "   Put the zip here: $REPO_ROOT/$ZIP"
  exit 1
fi

# Sanity check: required files exist in THIS repo
[ -f "apps/dashboard/server.py" ] || { echo "❌ apps/dashboard/server.py not found in $REPO_ROOT"; exit 1; }
[ -d "apps/dashboard/templates" ] || { echo "❌ apps/dashboard/templates/ not found in $REPO_ROOT"; exit 1; }

TS="$(date +%Y%m%d-%H%M%S)"
BKDIR="archive/patch_backups/060_youware_frontend_$TS"
mkdir -p "$BKDIR"

echo "✅ Repo: $REPO_ROOT"
echo "✅ Patch: $ZIP"
echo "✅ Backup dir: $BKDIR"

# Backups
cp -f "apps/dashboard/server.py" "$BKDIR/server.py.bak"
if [ -f "apps/dashboard/templates/sovereign_full.html" ]; then
  cp -f "apps/dashboard/templates/sovereign_full.html" "$BKDIR/sovereign_full.html.bak"
fi
if [ -d "apps/dashboard/static/assets" ]; then
  mkdir -p "$BKDIR/static_assets"
  cp -a "apps/dashboard/static/assets" "$BKDIR/static_assets/assets.bak"
fi

# Extract patch (python so we don't depend on unzip)
python3 - <<'PY'
import zipfile, pathlib, shutil, sys

zip_path = pathlib.Path("patches/patch060_youware_frontend.zip")
root = pathlib.Path(".").resolve()

with zipfile.ZipFile(zip_path) as z:
    names = z.namelist()
    # Extract only apps/dashboard/*
    extracted = 0
    for n in names:
        if not n.startswith("apps/dashboard/"):
            continue
        out = root / n
        out.parent.mkdir(parents=True, exist_ok=True)
        with z.open(n) as src, open(out, "wb") as dst:
            shutil.copyfileobj(src, dst)
        extracted += 1

print(f"✅ Extracted {extracted} files into repo")
PY

# Patch server.py to serve /assets/* (idempotent)
python3 - <<'PY'
import re, pathlib

p = pathlib.Path("apps/dashboard/server.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Ensure flask import includes send_from_directory
if "send_from_directory" not in txt:
    m = re.search(r"from\s+flask\s+import\s+([^\n]+)\n", txt)
    if m:
        imports = m.group(1).strip()
        if "send_from_directory" not in imports:
            txt = txt[:m.start()] + f"from flask import {imports}, send_from_directory\n" + txt[m.end():]
    else:
        txt = "from flask import send_from_directory\n" + txt

# Ensure os is imported (for ASSETS_DIR)
if not re.search(r"^\s*import\s+os\s*$", txt, flags=re.M):
    # insert near top
    txt = "import os\n" + txt

# Ensure ASSETS_DIR exists
if "ASSETS_DIR" not in txt:
    # place after import block
    insert_at = 0
    for m in re.finditer(r"^(from|import)\s+.+$", txt, flags=re.M):
        insert_at = m.end()
    txt = txt[:insert_at] + "\n\n# Vite/YouWare build assets\nASSETS_DIR = os.path.join(os.path.dirname(__file__), 'static', 'assets')\n" + txt[insert_at:]

# Ensure route exists
route_sig = r"@app\.(get|route)\(\s*['\"]\/assets\/<path:filename>['\"]"
if not re.search(route_sig, txt):
    m = re.search(r"^.*app\s*=\s*Flask\s*\(.*\)\s*$", txt, flags=re.M)
    insert_at = m.end() if m else 0
    snippet = """

# Serve Vite-style assets at /assets/*
@app.get("/assets/<path:filename>")
def serve_assets(filename):
    return send_from_directory(ASSETS_DIR, filename)
"""
    txt = txt[:insert_at] + snippet + txt[insert_at:]

p.write_text(txt, encoding="utf-8")
print("✅ Patched server.py for /assets/* (idempotent)")
PY

echo "✅ Patch applied."
echo "➡️  Now run: python sovereign_dashboard_full.py"
echo "   Backup saved at: $BKDIR"
