#!/bin/bash
echo "🚀 Pushing changes to GitHub for Termux..."

cd /home/runner/$REPL_SLUG
git add .
git commit -m "Replit → GitHub → Termux: $(date '+%H:%M:%S')"
git push origin main

echo "✅ Pushed! Termux can now pull these changes."
