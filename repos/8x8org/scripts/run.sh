#!/data/data/com.termux/files/usr/bin/bash
set -e
VENV="${HOME}/.venvs/8x8org"
if [ -f "$VENV/bin/activate" ]; then
  . "$VENV/bin/activate"
fi
cd "$(dirname "$0")/.."

set -Eeuo pipefail

export GIT_DISCOVERY_ACROSS_FILESYSTEM=1

REPO="$HOME/storage/shared/Workspace/repos/8x8org"
VENV="$HOME/.venvs/8x8org"

cd "$REPO"

if [ ! -d "$VENV" ]; then
  mkdir -p "$HOME/.venvs"
  python -m venv "$VENV"
fi

source "$VENV/bin/activate"
pip -q install -r requirements.txt

source scripts/env.sh
mkdir -p "$SOVEREIGN_WORKSPACE" "$SOVEREIGN_LOG_DIR"

python app/dashboard.py
