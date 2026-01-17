# 8x8org shortcuts (portable)
alias 8x='cd /home/runner/workspace 2>/dev/null || cd "$HOME/storage/shared/Workspace"'
alias 8xr='cd /home/runner/workspace/repos/8x8org 2>/dev/null || cd "$HOME/storage/shared/Workspace/repos/8x8org"'

alias gstatus='(8xr >/dev/null 2>&1 || true; git status)'
alias glog='(8xr >/dev/null 2>&1 || true; git --no-pager log --oneline -n 12)'
alias gsync='(8xr >/dev/null 2>&1 || true; git pull --ff-only)'
