# 8x8org shortcuts (portable: Replit + Termux)
if [ -d "$HOME/storage/shared/Workspace" ]; then
  # Termux
  alias 8x='cd "$HOME/storage/shared/Workspace"'
  alias 8xr='cd "$HOME/storage/shared/Workspace/repos/8x8org"'
else
  # Replit
  alias 8x='cd /home/runner/workspace'
  alias 8xr='cd /home/runner/workspace/repos/8x8org'
fi
