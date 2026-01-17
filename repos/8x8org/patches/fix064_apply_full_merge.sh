#!/usr/bin/env bash
set -euo pipefail

# Patch064: Full merge installer (safe + idempotent)
# - Installs frontend source + built dist (template+assets)
# - Patches apps/dashboard/server.py to serve / and /assets/*

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

ZIP="$ROOT/patches/patch064_full_merge.zip"
[ -f "$ZIP" ] || ZIP="$HERE/patch064_full_merge.zip"
if [ ! -f "$ZIP" ]; then
  echo "❌ patch064 zip not found (expected in patches/patch064_full_merge.zip)"
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="$ROOT/archive/patch_backups/064_full_merge_${TS}"
mkdir -p "$BK"

echo "✅ Repo:   $ROOT"
echo "✅ Patch:  $ZIP"
echo "✅ Backup: $BK"

mkdir -p "$BK/apps/dashboard" "$BK/apps/dashboard/templates" "$BK/apps/dashboard/static" "$BK/apps/dashboard/frontend"
[ -f "$ROOT/apps/dashboard/server.py" ] && cp -f "$ROOT/apps/dashboard/server.py" "$BK/apps/dashboard/server.py.bak" || true
[ -d "$ROOT/apps/dashboard/templates" ] && cp -a "$ROOT/apps/dashboard/templates/." "$BK/apps/dashboard/templates/" 2>/dev/null || true
[ -d "$ROOT/apps/dashboard/static" ] && cp -a "$ROOT/apps/dashboard/static/." "$BK/apps/dashboard/static/" 2>/dev/null || true
[ -d "$ROOT/apps/dashboard/frontend" ] && cp -a "$ROOT/apps/dashboard/frontend/." "$BK/apps/dashboard/frontend/" 2>/dev/null || true

TMPBASE="${TMPDIR:-}"
if [ -z "$TMPBASE" ]; then
  if [ -d "/data/data/com.termux/files/usr/tmp" ]; then
    TMPBASE="/data/data/com.termux/files/usr/tmp"
  else
    TMPBASE="/tmp"
  fi
fi
mkdir -p "$TMPBASE"
TMP="$(mktemp -d "$TMPBASE/patch064_XXXXXX")"
cleanup(){ rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT

echo "✅ Extracting patch into temp..."
python - <<PY
import zipfile, pathlib
z = pathlib.Path(r"$ZIP")
out = pathlib.Path(r"$TMP")
with zipfile.ZipFile(z) as zz:
    zz.extractall(out)
print("ok")
PY

echo "✅ Installing files into repo (overwrite)..."
( cd "$TMP" && tar -cf - . ) | ( cd "$ROOT" && tar -xvf - >/dev/null )

# Fix template asset paths if needed
if [ -f "$ROOT/apps/dashboard/templates/sovereign_full.html" ]; then
  sed -i 's|/assets/assets/|/assets/|g' "$ROOT/apps/dashboard/templates/sovereign_full.html" || true
fi

# Patch server.py safely (routes helper + attach to app if possible)
if [ -f "$ROOT/apps/dashboard/server.py" ]; then
python - <<'PY'
from pathlib import Path
import re

p = Path("apps/dashboard/server.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# ensure flask imports include render_template + send_from_directory
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)\n", txt, flags=re.M)
if m:
    imports = [x.strip() for x in m.group(1).split(",")]
    changed = False
    for needed in ("render_template", "send_from_directory"):
        if needed not in imports:
            imports.append(needed)
            changed = True
    if changed:
        txt = txt[:m.start()] + "from flask import " + ", ".join(imports) + "\n" + txt[m.end():]
else:
    txt = "from flask import render_template, send_from_directory\n" + txt

helper_name = "register_patch064_routes"
if helper_name not in txt:
    helper = (
        "\n\n# --- PATCH064: routes helper (idempotent) ---\n"
        "def register_patch064_routes(app):\n"
        "    \"\"\"Ensure root and /assets for the SPA without breaking existing routes.\"\"\"\n"
        "    from pathlib import Path\n"
        "    assets_dir = Path(__file__).resolve().parent / 'static' / 'assets'\n\n"
        "    has_assets = any(r.rule.startswith('/assets/') for r in app.url_map.iter_rules())\n"
        "    if not has_assets:\n"
        "        @app.get('/assets/<path:filename>')\n"
        "        def patch064_assets(filename):\n"
        "            return send_from_directory(str(assets_dir), filename)\n\n"
        "    has_root = any(r.rule == '/' for r in app.url_map.iter_rules())\n"
        "    if not has_root:\n"
        "        @app.get('/')\n"
        "        def patch064_root():\n"
        "            return render_template('sovereign_full.html')\n"
    )
    txt += helper + "\n"

call = f"{helper_name}(app)"
if call not in txt:
    m2 = re.search(r"^(\s*)app\s*=\s*Flask\s*\(.*\)\s*$", txt, flags=re.M)
    if m2:
        insert = m2.end()
        indent = m2.group(1)
        txt = txt[:insert] + f"\n{indent}{call}\n" + txt[insert:]

p.write_text(txt, encoding="utf-8")
print("✅ Patched server.py (routes/assets helper)")
PY
else
  echo "⚠️ apps/dashboard/server.py not found; skipped server patch."
fi

echo ""
echo "✅ Patch064 applied successfully."
echo "➡️ Next: python sovereign_dashboard_full.py"
echo "   Backup: $BK"
