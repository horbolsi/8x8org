# 8x8org shortcuts (Replit + Termux friendly)
# NOTE: alias names can be digits, bash function names cannot.

# Always prepend repo + workspace bins (so 8x/8xr work even if aliases don't)
export PATH="/home/runner/workspace/repos/8x8org/bin:/home/runner/workspace/bin:$PATH"

# Aliases (nice in interactive shells)
alias 8x='cd /home/runner/workspace'
alias 8xr='cd /home/runner/workspace/repos/8x8org'

# Optional git helpers
alias gstatus='(cd /home/runner/workspace/repos/8x8org 2>/dev/null && git status)'
alias glog='(cd /home/runner/workspace/repos/8x8org 2>/dev/null && git --no-pager log --oneline -n 12)'
alias gsync='(cd /home/runner/workspace/repos/8x8org 2>/dev/null && git pull --ff-only)'
