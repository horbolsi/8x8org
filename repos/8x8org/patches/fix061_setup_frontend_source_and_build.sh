#!/usr/bin/env bash
set -euo pipefail

# One-shot setup:
# - Extract patch zip (this zip) into repo root
# - Build frontend and install into Flask template/assets
# Safe to re-run.

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

ZIP="patches/patch061_dashboard_source.zip"

if [ ! -f "$ZIP" ]; then
  echo "❌ Missing $ZIP"
  echo "Put it here: $ROOT/$ZIP"
  exit 1
fi

echo "✅ Repo: $ROOT"
echo "✅ Using: $ZIP"

python3 - <<'PY'
import zipfile, pathlib, shutil

root = pathlib.Path(".").resolve()
zip_path = root / "patches/patch061_dashboard_source.zip"

with zipfile.ZipFile(zip_path) as z:
    extracted = 0
    for n in z.namelist():
        if not (n.startswith("apps/") or n.startswith("scripts/") or n.startswith("patches/")):
            continue
        out = root / n
        out.parent.mkdir(parents=True, exist_ok=True)
        with z.open(n) as src, open(out, "wb") as dst:
            shutil.copyfileobj(src, dst)
        extracted += 1
print(f"✅ Extracted {extracted} files")
PY

# ensure scripts executable (Termux shared storage may be noexec, so users can still run with bash)
chmod +x scripts/build_frontend.sh patches/fix061_setup_frontend_source_and_build.sh || true

echo "✅ Building + installing frontend into Flask..."
bash scripts/build_frontend.sh

echo ""
echo "✅ Done."
echo "Run dashboard: python sovereign_dashboard_full.py"
