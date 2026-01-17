#!/usr/bin/env bash
set -euo pipefail

# Build the Vite frontend safely on Termux by building in an internal temp dir
# to avoid permission/symlink issues on shared storage (/storage/shared/...).

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FRONTEND="$ROOT/apps/dashboard/frontend"
OUT_TPL="$ROOT/apps/dashboard/templates/sovereign_full.html"
OUT_ASSETS="$ROOT/apps/dashboard/static/assets"
OUT_STATIC="$ROOT/apps/dashboard/static"

if [ ! -d "$FRONTEND" ]; then
  echo "❌ Frontend folder not found: $FRONTEND"
  exit 1
fi

command -v npm >/dev/null 2>&1 || { echo "❌ npm not found"; exit 1; }

TMPBASE="${TMPDIR:-}"
if [ -z "$TMPBASE" ]; then
  if [ -d "/data/data/com.termux/files/usr/tmp" ]; then
    TMPBASE="/data/data/com.termux/files/usr/tmp"
  else
    TMPBASE="/tmp"
  fi
fi
mkdir -p "$TMPBASE"
DIST_TMP="$(mktemp -d "$TMPBASE/sovereign_frontend_build_XXXXXX")"

cleanup() { rm -rf "$DIST_TMP" 2>/dev/null || true; }
trap cleanup EXIT

echo "✅ Building in temp: $DIST_TMP"
cp -a "$FRONTEND/." "$DIST_TMP/"

cd "$DIST_TMP"
if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi
npm run build

mkdir -p "$(dirname "$OUT_TPL")" "$OUT_ASSETS" "$OUT_STATIC"

if [ ! -f "dist/index.html" ]; then
  echo "❌ Build produced no dist/index.html"
  exit 1
fi

sed 's|/assets/assets/|/assets/|g' "dist/index.html" > "$OUT_TPL"

if [ -d "dist/assets" ]; then
  rm -f "$OUT_ASSETS"/* 2>/dev/null || true
  cp -a "dist/assets/." "$OUT_ASSETS/"
fi

if [ -f "dist/yw_manifest.json" ]; then
  cp -f "dist/yw_manifest.json" "$OUT_STATIC/yw_manifest.json"
fi

echo "✅ Frontend build installed:"
echo "   Template: $OUT_TPL"
echo "   Assets:   $OUT_ASSETS"
