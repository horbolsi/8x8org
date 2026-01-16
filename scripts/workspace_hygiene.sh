#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

WS="/storage/emulated/0/Workspace"

mkdir -p "$WS"/{repos,projects,logs,docs,archive,bin,scripts}

# Ensure Git safe.directory (Android shared storage quirk)
git config --global --add safe.directory /storage/emulated/0/Workspace || true
git config --global --add safe.directory "$HOME/storage/shared/Workspace" || true

# Ensure ignore rules exist (idempotent append)
touch "$WS/.gitignore"

append_once() {
  local line="$1"
  grep -qxF "$line" "$WS/.gitignore" 2>/dev/null || echo "$line" >> "$WS/.gitignore"
}

# Replit-only
append_once ""
append_once "# Replit-only"
append_once ".replit"
append_once "replit.nix"

# Backups/junk
append_once ""
append_once "# Backups/junk"
append_once "*.bak.*"
append_once "*.backup"

# Runtime + big dirs
append_once ""
append_once "# Runtime + big dirs"
append_once "projects/"
append_once "logs/"
append_once "runtime/"
append_once "archive/"
append_once "**/node_modules/"
append_once "**/dist/"
append_once "**/.venv/"
append_once "**/__pycache__/"

echo "✅ Workspace hygiene done: $WS"
echo "Repo root:"
git -C "$WS" rev-parse --show-toplevel
