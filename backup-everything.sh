#!/bin/bash
echo "📦 COMPLETE BACKUP - Replit → GitHub"
echo "========================================"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# List all files being backed up
echo "📁 Files to backup:"
echo "=================="
find . -type f -name "*" ! -path "./.git/*" ! -name "*.log" | head -30
echo "..."

# Get total count
TOTAL_FILES=$(find . -type f -name "*" ! -path "./.git/*" ! -name "*.log" | wc -l)
echo "Total files: $TOTAL_FILES"
echo ""

# Backup process
echo "🔄 Starting backup..."
git add --all .

# Check if there are changes
if git diff --cached --quiet; then
    echo "✅ No changes to commit (already up to date)"
else
    # Commit with timestamp
    COMMIT_MSG="📦 Complete Backup: $(date '+%Y-%m-%d %H:%M:%S') - $TOTAL_FILES files"
    echo "💾 Committing: $COMMIT_MSG"
    git commit -m "$COMMIT_MSG"
    
    # Push to GitHub
    echo "🚀 Pushing to GitHub..."
    if git push origin main; then
        echo ""
        echo "🎉 SUCCESS! Everything pushed to GitHub!"
        echo "🌐 Repository: https://github.com/horbolsi/8x8org"
        echo "📊 Commit: $(git log --oneline -1 | cut -d' ' -f1)"
        echo "📦 Files: $TOTAL_FILES"
        echo ""
    else
        echo "❌ Failed to push to GitHub"
        exit 1
    fi
fi

echo "✅ Backup completed at $(date '+%H:%M:%S')"
echo "========================================"
