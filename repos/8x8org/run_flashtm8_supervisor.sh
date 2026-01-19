#!/usr/bin/env bash
set -euo pipefail
cd "/home/runner/workspace/repos/8x8org"

# Self-healing loop: restart if crash
while true; do
  echo "⚡ Supervisor: starting FlashTM8..."
  bash start_flashtm8.sh || true
  echo "⚠️ FlashTM8 stopped/crashed. Restarting in 2s..."
  sleep 2
done
