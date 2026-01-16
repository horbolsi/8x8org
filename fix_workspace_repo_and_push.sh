#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

WS="$HOME/storage/shared/Workspace"
cd "$WS"

echo "== Workspace repo hygiene =="

# 0) Fix "dubious ownership" (Android shared storage sometimes triggers this)
git config --global --add safe.directory "/storage/emulated/0/Workspace" >/dev/null 2>&1 || true
git config --global --add safe.directory "$WS" >/dev/null 2>&1 || true

# 1) Ensure we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Not a git repo here: $WS"
  echo "   Run 'git init' and add your remote first."
  exit 1
fi

# 2) Ensure .gitignore exists
touch .gitignore

# 3) Add recommended ignore rules (only if missing)
add_ignore () {
  local line="$1"
  grep -qxF "$line" .gitignore 2>/dev/null || echo "$line" >> .gitignore
}

# Local helper scripts (keep local, don't push)
add_ignore "_push_workspace.sh"
add_ignore "fix_workspace_repo_and_push.sh"

# Never push nested git internals/backups
add_ignore "archive/_git_backup/"

# Don't push logs/runtime/venvs/databases in Workspace mirror
add_ignore "logs/"
add_ignore "projects/"
add_ignore "**/*.log"
add_ignore "**/*.db"
add_ignore "**/*.sqlite"
add_ignore "**/.venv/"
add_ignore "**/.venvs/"
add_ignore "**/__pycache__/"
add_ignore "**/*.pyc"

# Don't push secrets / ssh keys
add_ignore "**/.env"
add_ignore "**/*token*"
add_ignore "**/*secret*"
add_ignore "**/*key*"
add_ignore "**/id_ed25519*"
add_ignore "**/known_hosts"

# 4) If any of these were already committed, untrack them (keep files locally)
untrack_if_tracked () {
  local path="$1"
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    echo "→ Untracking from git index: $path"
    git rm -r --cached --ignore-unmatch "$path" >/dev/null 2>&1 || true
  fi
}

untrack_if_tracked "_push_workspace.sh"
untrack_if_tracked "fix_workspace_repo_and_push.sh"
untrack_if_tracked "archive/_git_backup"
untrack_if_tracked "logs"
untrack_if_tracked "projects"

# 5) Stage all changes (respects .gitignore)
git add -A

# 6) Commit only if needed
if git diff --cached --quiet; then
  echo "✅ Nothing to commit."
else
  msg="${1:-Workspace hygiene + update $(date '+%Y-%m-%d %H:%M:%S')}"
  git commit -m "$msg"
  echo "✅ Committed."
fi

# 7) Push
git push
echo "✅ Pushed to origin."
