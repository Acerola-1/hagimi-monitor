#!/bin/bash

# Exit on error
set -e

# Get version number
VERSION=$(grep 'MARKETING_VERSION' hagimi-monitor.xcodeproj/project.pbxproj | head -1 | awk -F'=' '{print $2}' | tr -d ' ";')

if [ -z "$VERSION" ]; then
    echo "❌ 无法获取版本号"
    exit 1
fi

echo "📦 准备发布版本: v$VERSION"

# Check and commit uncommitted changes
echo "🔍 检查工作区状态..."
if [ -n "$(git status --porcelain)" ]; then
    echo "📝 发现未提交的修改，正在提交..."
    git add -A
    git commit -m "[发布] v$VERSION"
fi

# Push current branch (dev)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "⬆️  推送 $CURRENT_BRANCH 分支..."
git push origin "$CURRENT_BRANCH"

# Create PR and squash merge
echo "🔀 创建 PR: $CURRENT_BRANCH → main..."
PR_URL=$(gh pr create \
    --base main \
    --head "$CURRENT_BRANCH" \
    --title "[发布] v$VERSION" \
    --body "Release v$VERSION" \
    --assignee @me)

echo "✅ PR 已创建: $PR_URL"

echo "🔄 Squash merge PR..."
gh pr merge --squash --delete-branch

# Wait for merge to complete
echo "⏳ 等待合并完成..."
sleep 3

# Switch to main and pull
echo "📥 切换到 main 分支..."
git checkout main
git pull origin main

# Create tag
echo "🏷️  创建标签 v$VERSION..."
git tag "v$VERSION"

# Push tag (this will trigger release build)
echo "⬆️  推送标签..."
git push origin "v$VERSION"

# Switch back to dev and sync
echo "🔄 同步 dev 分支..."
git checkout dev
git merge main
git push origin dev

echo "✅ 发布完成！GitHub Actions 将自动构建 Release"
echo "🔗 查看构建状态: https://github.com/Acerola-1/hagimi-monitor/actions"
