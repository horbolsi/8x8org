# 8x8org shortcuts (Replit + Termux safe)

# Add bin directories to PATH if they exist
if [ -d "$HOME/workspace/bin" ]; then
  export PATH="$HOME/workspace/bin:$PATH"
fi
if [ -d "$HOME/workspace/repos/8x8org/bin" ]; then
  export PATH="$HOME/workspace/repos/8x8org/bin:$PATH"
fi

alias 8x='cd /home/runner/workspace'
alias 8xr='cd /home/runner/workspace/repos/8x8org'

# optional helpers
alias gstatus='(cd /home/runner/workspace/repos/8x8org 2>/dev/null && git status)'
alias glog='(cd /home/runner/workspace/repos/8x8org 2>/dev/null && git --no-pager log --oneline -n 12)'
