#!/bin/bash
echo "========================================"
echo "🔄 GITHUB BACKUP: 8x8org"
echo "========================================"
echo "📅 $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Navigate to project
cd /home/runner/$REPL_SLUG || {
    echo -e "${RED}❌ Error: Cannot navigate to project directory${NC}"
    exit 1
}

# Check git status
echo -e "${BLUE}📊 Checking status...${NC}"
git status --short

# Count changes
CHANGES=$(git status --porcelain | wc -l)
echo -e "${YELLOW}📈 Found $CHANGES changed files${NC}"

if [ $CHANGES -eq 0 ]; then
    echo -e "${GREEN}✅ No changes to commit${NC}"
    echo ""
    echo "========================================"
    echo "✅ Backup complete (no changes)"
    echo "========================================"
    exit 0
fi

# Add all changes
echo -e "${BLUE}➕ Staging changes...${NC}"
git add .

# Create commit
COMMIT_MSG="🔄 Backup: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}💾 Committing: $COMMIT_MSG${NC}"
git commit -m "$COMMIT_MSG"

# Push to GitHub
echo -e "${BLUE}🚀 Pushing to GitHub...${NC}"
if git push origin main; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 SUCCESSFULLY BACKED UP TO GITHUB!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "🌐 View repository: ${BLUE}https://github.com/horbolsi/8x8org${NC}"
    echo -e "📊 Commit hash: $(git log --oneline -1 | cut -d' ' -f1)"
    echo -e "📅 Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ FAILED TO PUSH TO GITHUB${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi

echo "========================================"
