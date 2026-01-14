#!/bin/bash
echo "🚀 PUSH: Replit → GitHub"
echo "========================"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"

# Add everything
git add --all .

# Check for changes
CHANGES=$(git status --porcelain | wc -l)
if [ $CHANGES -eq 0 ]; then
    echo "✅ No changes to push"
    exit 0
fi

echo "📦 Changes detected: $CHANGES files"

# Show what's changing
echo "Modified files:"
git status --porcelain | head -10
[ $CHANGES -gt 10 ] && echo "... and $((CHANGES-10)) more"

# Commit
COMMIT_MSG="Replit → GitHub: $(date '+%Y-%m-%d %H:%M:%S') - $CHANGES files"
git commit -m "$COMMIT_MSG"

# Push
echo "🚀 Pushing to GitHub..."
git push origin main

echo ""
echo "✅ Push complete!"
echo "🌐 GitHub: https://github.com/horbolsi/8x8org"
echo "========================"
