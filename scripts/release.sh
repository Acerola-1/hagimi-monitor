#!/bin/bash
set -euo pipefail

usage() {
  echo "用法: ./scripts/release.sh <版本号>"
  echo ""
  echo "示例:"
  echo "  ./scripts/release.sh 0.1.0"
  echo "  ./scripts/release.sh 1.0.0"
  echo ""
  echo "功能:"
  echo "  1. 更新 MARKETING_VERSION 到指定版本号"
  echo "  2. 提交版本号变更"
  echo "  3. 合并 dev 到 main"
  echo "  4. 打 tag (v<版本号>)"
  echo "  5. 推送 main 和 tag"
  echo "  6. 切回 dev"
  echo "  7. GitHub Actions 自动构建并发布 Release"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

VERSION="$1"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误: 版本号格式不正确，应为 x.y.z (如 0.1.0)"
  exit 1
fi

TAG="v${VERSION}"
CURRENT_BRANCH=$(git branch --show-current)
PBXPROJ="hagimi-monitor.xcodeproj/project.pbxproj"

echo "=== 发布 ${TAG} ==="

# 检查工作区（允许未提交的版本号变更）
if [[ -n $(git status --porcelain | grep -v "$PBXPROJ") ]]; then
  echo "错误: 工作区有未提交的更改，请先提交或暂存"
  git status --short | grep -v "$PBXPROJ"
  exit 1
fi

# 检查 tag 是否已存在
if git tag -l "$TAG" | grep -q "$TAG"; then
  echo "错误: tag ${TAG} 已存在"
  echo "如需重新发布，请先删除: git tag -d ${TAG} && git push origin --delete ${TAG}"
  exit 1
fi

# 更新 MARKETING_VERSION
echo ">>> 更新 MARKETING_VERSION 为 ${VERSION}..."
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"

# 提交版本号变更
if [[ -n $(git status --porcelain) ]]; then
  echo ">>> 提交版本号变更..."
  git add "$PBXPROJ"
  git commit -m "发布 ${TAG}"
fi

# 推送当前分支
echo ">>> 推送 ${CURRENT_BRANCH}..."
git push origin "$CURRENT_BRANCH"

# 切到 main 并合并
echo ">>> 切到 main 并合并 ${CURRENT_BRANCH}..."
git checkout main
git merge "$CURRENT_BRANCH"
git push origin main

# 打 tag 并推送
echo ">>> 打 tag ${TAG} 并推送..."
git tag "$TAG"
git push origin "$TAG"

# 切回原分支
echo ">>> 切回 ${CURRENT_BRANCH}..."
git checkout "$CURRENT_BRANCH"

echo ""
echo "=== 发布完成 ==="
echo "版本: ${VERSION}"
echo "tag: ${TAG}"
echo "Actions: https://github.com/Acerola-1/hagimi-monitor/actions"
echo "Releases: https://github.com/Acerola-1/hagimi-monitor/releases"
