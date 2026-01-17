# Replit terminal rcfile (repo-controlled)

# Try to source Replit's default bashrc if available (path varies)
for f in /nix/store/*-replit-bashrc*/bashrc /nix/store/*replit-bashrc*/bashrc; do
  if [ -f "$f" ]; then
    . "$f"
    break
  fi
done

# Ensure aliases work even in weird shell modes
shopt -s expand_aliases 2>/dev/null || true

# Load our shortcuts
if [ -f "/home/runner/workspace/repos/8x8org/scripts/shellrc.sh" ]; then
  . "/home/runner/workspace/repos/8x8org/scripts/shellrc.sh"
fi
