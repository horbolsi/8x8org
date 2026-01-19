#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/runner/workspace/repos/8x8org"
export PORT="${PORT:-5000}"
cd "$ROOT"
echo "✅ Starting Sovereign Dashboard on PORT=$PORT"
python sovereign_dashboard_full.py
