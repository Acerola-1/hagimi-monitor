#!/bin/bash
set -euo pipefail

usage() {
  echo "用法: ./scripts/release.sh <版本号> [发布说明]"
  echo ""
  echo "示例:"
  echo "  ./scripts/release.sh 0.1.0"
  echo "  ./scripts/release.sh 0.8.0 \"自适应面板布局与显示器模块国际化\""
  echo "  ./scripts/release.sh 0.8.0 \"\$(cat notes.md)\""
  echo ""
  echo "前置条件:"
  echo "  - gh CLI 已安装并登录 (gh auth login)"
  echo "  - 工作区干净（仅允许版本号和发布说明变更）"
  echo ""
  echo "流程:"
  echo "  1. 更新 MARKETING_VERSION"
  echo "  2. 写入 RELEASE_NOTES.md"
  echo "  3. 提交到 release/<版本号> 分支"
  echo "  4. 推送分支，创建 PR 到 main"
  echo "  5. 自动合并 PR（squash）"
  echo "  6. 打 tag v<版本号> 并推送"
  echo "  7. 清理发布分支，切回 dev"
  echo "  8. GitHub Actions 自动构建并发布 Release"
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

VERSION="$1"
RELEASE_NOTES="${2:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误: 版本号格式不正确，应为 x.y.z (如 0.1.0)"
  exit 1
fi

# 检查 gh CLI
if ! command -v gh &>/dev/null; then
  echo "错误: gh CLI 未安装，请先安装: brew install gh"
  echo "然后登录: gh auth login"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "错误: gh CLI 未登录，请先执行: gh auth login"
  exit 1
fi

TAG="v${VERSION}"
ORIGIN_BRANCH=$(git branch --show-current)
RELEASE_BRANCH="release/${VERSION}"
PBXPROJ="hagimi-monitor.xcodeproj/project.pbxproj"
NOTES_FILE="RELEASE_NOTES.md"

echo "=== 发布 ${TAG} ==="

# 检查工作区（仅允许版本号和发布说明文件变更）
if [[ -n $(git status --porcelain | grep -vE "$PBXPROJ|$NOTES_FILE") ]]; then
  echo "错误: 工作区有未提交的更改，请先提交或暂存"
  git status --short | grep -vE "$PBXPROJ|$NOTES_FILE"
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

# 写入发布说明
if [[ -n "$RELEASE_NOTES" ]]; then
  echo ">>> 写入发布说明到 ${NOTES_FILE}..."
  cat > "$NOTES_FILE" <<EOF
## 更新内容

${RELEASE_NOTES}
EOF
else
  echo ">>> 未提供发布说明，写入占位（GitHub 仍会自动追加 commit 列表）"
  cat > "$NOTES_FILE" <<EOF
本次发布 ${TAG}。
EOF
fi

# 创建发布分支并提交
echo ">>> 创建发布分支 ${RELEASE_BRANCH}..."
git checkout -b "$RELEASE_BRANCH"

if [[ -n $(git status --porcelain) ]]; then
  echo ">>> 提交版本号变更..."
  git add "$PBXPROJ" "$NOTES_FILE"
  git commit -m "发布 ${TAG}"
fi

# 推送发布分支
echo ">>> 推送 ${RELEASE_BRANCH}..."
git push origin "$RELEASE_BRANCH"

# 创建 PR
echo ">>> 创建 Pull Request..."
PR_URL=$(gh pr create \
  --base main \
  --head "$RELEASE_BRANCH" \
  --title "发布 ${TAG}" \
  --body "$(cat "$NOTES_FILE")")

echo "PR 已创建: ${PR_URL}"

# 合并 PR（squash，保持 main 线性历史）
echo ">>> 合并 PR..."
gh pr merge --squash --delete-branch "$PR_URL"

# 拉取 main 并打 tag
echo ">>> 拉取 main 并打 tag..."
git checkout main
git pull origin main
git tag "$TAG"
git push origin "$TAG"

# 切回原分支并同步
echo ">>> 切回 ${ORIGIN_BRANCH} 并同步..."
git checkout "$ORIGIN_BRANCH"
git pull origin main --no-edit || true
git push origin "$ORIGIN_BRANCH"

echo ""
echo "=== 发布完成 ==="
echo "版本: ${VERSION}"
echo "tag: ${TAG}"
echo "PR: ${PR_URL}"
echo "Actions: https://github.com/Acerola-1/hagimi-monitor/actions"
echo "Releases: https://github.com/Acerola-1/hagimi-monitor/releases"
