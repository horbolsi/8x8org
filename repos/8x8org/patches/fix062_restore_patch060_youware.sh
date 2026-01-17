#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

ZIP="patches/patch060_youware_frontend.zip"
[ -f "$ZIP" ] || { echo "❌ Missing $ZIP"; exit 1; }

TS="$(date +%Y%m%d-%H%M%S)"
BK="archive/patch_backups/062_restore_patch060_$TS"
mkdir -p "$BK"

echo "✅ Backup -> $BK"
cp -f apps/dashboard/server.py "$BK/server.py.bak" 2>/dev/null || true
cp -f apps/dashboard/templates/sovereign_full.html "$BK/sovereign_full.html.bak" 2>/dev/null || true
if [ -d apps/dashboard/static/assets ]; then
  mkdir -p "$BK/assets"
  cp -a apps/dashboard/static/assets "$BK/assets/assets.bak" 2>/dev/null || true
fi

echo "✅ Restoring patch060 template + assets..."
python3 - <<'PY'
import zipfile, pathlib, shutil, sys, os

zip_path = pathlib.Path("patches/patch060_youware_frontend.zip")
root = pathlib.Path(".").resolve()

tpl = root / "apps/dashboard/templates/sovereign_full.html"
assets_dir = root / "apps/dashboard/static/assets"
assets_dir.mkdir(parents=True, exist_ok=True)

# wipe old hashed assets so we don't accumulate junk
for p in assets_dir.glob("index-*.js"):
    p.unlink()
for p in assets_dir.glob("index-*.css"):
    p.unlink()

with zipfile.ZipFile(zip_path) as z:
    names = z.namelist()

    # extract template
    if "apps/dashboard/templates/sovereign_full.html" not in names:
        print("❌ patch060 zip doesn't contain apps/dashboard/templates/sovereign_full.html")
        sys.exit(1)
    tpl.parent.mkdir(parents=True, exist_ok=True)
    with z.open("apps/dashboard/templates/sovereign_full.html") as src, open(tpl, "wb") as dst:
        shutil.copyfileobj(src, dst)

    # extract all assets inside apps/dashboard/static/assets/
    extracted_assets = 0
    for n in names:
        if n.startswith("apps/dashboard/static/assets/") and not n.endswith("/"):
            out = root / n
            out.parent.mkdir(parents=True, exist_ok=True)
            with z.open(n) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst)
            extracted_assets += 1

print(f"✅ Restored template + {extracted_assets} asset files from patch060")
PY

echo "✅ Patching server.py to always serve / and /assets/* (safe, idempotent)..."
python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/dashboard/server.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Ensure os import exists
if not re.search(r"^\s*import\s+os\s*$", txt, flags=re.M):
    txt = "import os\n" + txt

# Add helper register function if missing
if "_register_youware_routes" not in txt:
    helper = r"""

def _register_youware_routes(app):
    \"\"\"Register routes AFTER app exists (safe for create_app patterns).\"\"\"
    if getattr(app, "_youware_routes_registered", False):
        return
    app._youware_routes_registered = True

    from flask import send_from_directory, render_template

    assets_dir = os.path.join(os.path.dirname(__file__), "static", "assets")

    @app.get("/assets/<path:filename>")
    def _youware_assets(filename):
        return send_from_directory(assets_dir, filename)

    @app.get("/")
    def _youware_home():
        return render_template("sovereign_full.html")
"""
    # insert after imports block
    insert_at = 0
    for m in re.finditer(r"^(from|import)\s+.+$", txt, flags=re.M):
        insert_at = m.end()
    txt = txt[:insert_at] + helper + txt[insert_at:]

# Ensure main() calls it after app is created
m_main = re.search(r"^def\s+main\s*\(", txt, flags=re.M)
if not m_main:
    raise SystemExit("❌ Couldn't find def main() in server.py")

# If already called, do nothing
if "_register_youware_routes(app)" not in txt:
    # Find the line inside main where app is created/unpacked
    # common patterns: app, socketio = create_app() OR app = create_app()
    pat = r"(app\s*,\s*socketio\s*=\s*create_app\s*\(\s*\)|app\s*=\s*create_app\s*\(\s*\))"
    mm = re.search(pat, txt[m_main.start():], flags=re.M)
    if not mm:
        # fallback: find first assignment to app in main
        mm = re.search(r"^\s*app\s*=", txt[m_main.start():], flags=re.M)
    if not mm:
        raise SystemExit("❌ Couldn't find where 'app' is assigned in main().")

    # compute insertion point right AFTER that assignment line
    start = m_main.start() + mm.end()
    # indent: detect indentation from the matched line
    line_start = txt.rfind("\n", 0, start) + 1
    indent = re.match(r"(\s*)", txt[line_start:start]).group(1) or "    "
    insert = f"\n{indent}_register_youware_routes(app)\n"
    txt = txt[:start] + insert + txt[start:]

p.write_text(txt, encoding="utf-8")
print("✅ server.py patched for / + /assets/* (patch060)")
PY

echo ""
echo "✅ Done. Start dashboard:"
echo "   python sovereign_dashboard_full.py"
echo ""
echo "Backup saved at: $BK"
