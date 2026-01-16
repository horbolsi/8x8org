#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

HOME_DIR="${HOME}"
STAMP="$(date '+%Y%m%d-%H%M%S')"
ARCHIVE_DIR="${HOME_DIR}/archive_home_cleanup_${STAMP}"

mkdir -p "$ARCHIVE_DIR"

say(){ echo "• $*"; }

# Never touch these
PROTECT_NAMES=(
  ".ssh" ".termux" ".config" ".cache"
  "storage" "bin"
)

is_protected() {
  local name="$1"
  for p in "${PROTECT_NAMES[@]}"; do
    [[ "$name" == "$p" ]] && return 0
  done
  return 1
}

# Things we consider "project-related junk" in ~ (safe to move)
PATTERNS=(
  "8x8org"
  "8x8org-backup-*"
  "termux-backup*"
  "termux-save-*"
  "node_modules"
  "*.log"
  "*.out"
  "*.tar.gz"
  "*.zip"
)

say "Home: $HOME_DIR"
say "Archive target: $ARCHIVE_DIR"
say "Moving matching items from ~ into archive (no deletions)."

shopt -s nullglob dotglob

moved=0
for pat in "${PATTERNS[@]}"; do
  for path in "$HOME_DIR"/$pat; do
    name="$(basename "$path")"
    [[ -e "$path" ]] || continue
    if is_protected "$name"; then
      say "SKIP protected: $name"
      continue
    fi
    say "MOVE: $name"
    mv -f "$path" "$ARCHIVE_DIR"/
    moved=$((moved+1))
  done
done

say "Done. Moved: $moved item(s)."
say "Review archive:"
say "  ls -la \"$ARCHIVE_DIR\" | head"
say "If everything is good, you can delete the archive later:"
say "  rm -rf \"$ARCHIVE_DIR\""
