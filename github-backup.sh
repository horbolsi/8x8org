#!/bin/bash
echo "========================================"
echo "🔄 GITHUB BACKUP: 8x8org"
echo "========================================"
echo "📅 $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Navigate to project
cd /home/runner/$REPL_SLUG || {
    echo "❌ Error: Cannot navigate to project directory"
    exit 1
}

# Check git status
echo "📊 Checking status..."
git status --short

# Count changes
CHANGES=$(git status --porcelain | wc -l)
echo "📈 Found $CHANGES changed files"

if [ $CHANGES -eq 0 ]; then
    echo "✅ No changes to commit"
    echo ""
    echo "========================================"
    echo "✅ Backup complete (no changes)"
    echo "========================================"
    exit 0
fi

# Add all changes
echo "➕ Staging changes..."
git add .

# Create commit
COMMIT_MSG="🔄 Backup: $(date '+%Y-%m-%d %H:%M:%S')"
echo "💾 Committing: $COMMIT_MSG"
git commit -m "$COMMIT_MSG"

# Push to GitHub
echo "🚀 Pushing to GitHub..."
if git push origin main; then
    echo ""
    echo "🎉 SUCCESSFULLY BACKED UP TO GITHUB!"
    echo ""
    echo "🌐 View repository: https://github.com/horbolsi/8x8org"
    echo "📊 Commit hash: $(git log --oneline -1 | cut -d' ' -f1)"
    echo "📅 Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
else
    echo ""
    echo "❌ FAILED TO PUSH TO GITHUB"
    exit 1
fi

echo "========================================"
