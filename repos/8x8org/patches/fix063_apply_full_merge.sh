#!/usr/bin/env bash
set -euo pipefail

# Apply merged patch:
# - Restore legacy dashboard (patch060) as the default at /
# - Keep SPA source (patch061) and add /spa route + /spa_assets static
# - Fix server.py routing safely

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -f "apps/dashboard/server.py" ]; then
  echo "❌ Can't find apps/dashboard/server.py from: $ROOT"
  echo "Run this from the repo root."
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="archive/patch_backups/063_merge_${TS}"
mkdir -p "$BK"

echo "✅ Backup -> $BK"
cp -f apps/dashboard/server.py "$BK/server.py.bak" || true
cp -f apps/dashboard/templates/sovereign_full.html "$BK/sovereign_full.html.bak" 2>/dev/null || true
mkdir -p "$BK/assets" || true
cp -f apps/dashboard/static/assets/index-*.js "$BK/assets/" 2>/dev/null || true
cp -f apps/dashboard/static/assets/index-*.css "$BK/assets/" 2>/dev/null || true

echo "✅ Restoring legacy dashboard template + assets (patch060)..."
# These files are included in this patch zip at the same paths.
# If you extracted this patch into the repo root, they are already present.
test -f apps/dashboard/templates/sovereign_full.html || { echo "❌ Missing templates/sovereign_full.html"; exit 1; }
test -f apps/dashboard/static/assets/ || true

echo "✅ Patching server.py (routes + static for legacy + SPA)..."
python3 - <<'PY'
from pathlib import Path
import re

p = Path("apps/dashboard/server.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# --- clean previous broken legacy injections (defensive) ---
txt = re.sub(r"\n# Legacy full dashboard.*?\n@app\.(get|route)\(\s*[\"\']\/legacy[\"\'].*?\n(?:def\s+legacy_dashboard\(.*?\):\n(?:[ \t].*\n)+)","\n",txt,flags=re.S)

# Ensure imports
def ensure_import(name):
    global txt
    m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", txt, flags=re.M)
    if m:
        imports = m.group(1)
        if name not in imports:
            new = imports.rstrip() + ", " + name
            txt = txt[:m.start(1)] + new + txt[m.end(1):]
    else:
        # add at top
        txt = f"from flask import {name}\n" + txt

for imp in ("render_template","send_from_directory"):
    ensure_import(imp)

# Helper: add code block after app creation inside create_app, else after module-level app creation.
def insert_after_app_creation(block: str):
    global txt
    # 1) factory pattern
    m = re.search(r"^def\s+create_app\b[\s\S]*?:\n", txt, flags=re.M)
    if m:
        start = m.end()
        body = txt[start:]
        # Find first "app = Flask(" inside create_app
        am = re.search(r"^(?P<indent>[ \t]+)app\s*=\s*Flask\s*\(.*\)\s*$", body, flags=re.M)
        if am:
            indent = am.group("indent")
            insert_at = start + am.end()
            ins = "\n" + "\n".join(indent + line if line else "" for line in block.splitlines()) + "\n"
            txt = txt[:insert_at] + ins + txt[insert_at:]
            return True
    # 2) module-level app
    am = re.search(r"^(?P<indent>[ \t]*)app\s*=\s*Flask\s*\(.*\)\s*$", txt, flags=re.M)
    if am:
        indent = am.group("indent")
        insert_at = am.end()
        ins = "\n" + "\n".join(indent + line if line else "" for line in block.splitlines()) + "\n"
        txt = txt[:insert_at] + ins + txt[insert_at:]
        return True
    return False

# Patch/ensure "/" route returns legacy template
# If there's already a route for "/", rewrite its return to render_template("sovereign_full.html")
def patch_root_route():
    global txt
    # match a function with @app.route('/') or @app.get('/')
    pat = re.compile(r"(?P<decor>^@app\.(?:route|get)\(\s*[\"\']\/\/?[\"\'].*?\)\s*$\n)(?P<def>^def\s+([a-zA-Z_][\w]*)\s*\([^\)]*\)\s*:\s*$)(?P<body>(?:\n[ \t]+.*)+)", re.M)
    m = pat.search(txt)
    if not m:
        return False
    body = m.group("body")
    # Preserve indent
    indent_m = re.search(r"\n([ \t]+)\S", body)
    indent = indent_m.group(1) if indent_m else "    "
    new_body = "\n" + indent + 'return render_template("sovereign_full.html")\n'
    txt = txt[:m.start("body")] + new_body + txt[m.end("body"):]
    return True

patched = patch_root_route()

# If no existing "/" route, inject one.
if not patched:
    block = '''
# Default: legacy full dashboard
@app.get("/")
def dashboard_home():
    return render_template("sovereign_full.html")
'''
    ok = insert_after_app_creation(block)
    if not ok:
        # fallback: append at end
        txt += "\n" + block + "\n"

# Ensure /spa route
if "/spa" not in txt:
    block = '''
@app.get("/spa")
def dashboard_spa():
    return render_template("sovereign_spa.html")
'''
    ok = insert_after_app_creation(block)
    if not ok:
        txt += "\n" + block + "\n"

# Ensure /assets and /spa_assets serving
def ensure_static_route(path_prefix, folder):
    global txt
    if path_prefix in txt:
        return
    block = f'''
@app.get("{path_prefix}/<path:filename>")
def _static_{path_prefix.strip("/").replace("-","_")}(filename):
    # Serve static files from apps/dashboard/static/{folder}
    base = Path(__file__).resolve().parent / "static" / "{folder}"
    return send_from_directory(base, filename)
'''
    ok = insert_after_app_creation(block)
    if not ok:
        txt += "\n" + block + "\n"

ensure_static_route("/assets", "assets")
ensure_static_route("/spa_assets", "spa_assets")

p.write_text(txt, encoding="utf-8")
print("✅ server.py patched successfully")
PY

echo "✅ Done."
echo ""
echo "Next steps:"
echo "  1) Build the SPA frontend (optional but recommended):"
echo "     bash scripts/build_spa_frontend.sh"
echo ""
echo "  2) Start server:"
echo "     python sovereign_dashboard_full.py"
echo ""
echo "Open:"
echo "  /     (legacy full dashboard)"
echo "  /spa  (new SPA)"
