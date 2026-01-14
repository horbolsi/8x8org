#!/bin/bash
echo "🔄 GitHub Backup for 8x8org"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"

cd /home/runner/$REPL_SLUG || exit 1

echo "📊 Checking git status..."
git status --short

CHANGES=$(git status --porcelain | wc -l)
if [ $CHANGES -eq 0 ]; then
    echo "✅ No changes to commit"
    exit 0
fi

echo "➕ Staging $CHANGES files..."
git add .

COMMIT_MSG="Backup: $(date '+%Y-%m-%d %H:%M:%S')"
echo "💾 Committing..."
git commit -m "$COMMIT_MSG"

if git push origin main; then
    echo "🎉 Successfully pushed to GitHub!"
    echo "🌐 https://github.com/horbolsi/8x8org"
else
    echo "❌ Failed to push to GitHub"
    exit 1
fi
