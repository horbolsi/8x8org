#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
f="${1:-}"
if [ -z "$f" ]; then
  echo "Usage: patches/run_patch.sh patches/fixXXX.sh"
  exit 1
fi
# normalize Windows CRLF if needed
sed -i 's/\r$//' "$f" || true
bash "$f"
