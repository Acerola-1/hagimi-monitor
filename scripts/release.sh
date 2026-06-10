#!/bin/bash
set -euo pipefail

usage() {
  echo "用法: ./scripts/release.sh <版本号> [发布说明]"
  echo ""
  echo "示例:"
  echo "  ./scripts/release.sh 0.1.0"
  echo "  ./scripts/release.sh 0.7.0 \"降低系统要求到 macOS 26.0\""
  echo "  ./scripts/release.sh 0.7.0 \"\$(cat notes.md)\"   # 从文件读取多行说明"
  echo ""
  echo "功能:"
  echo "  1. 更新 MARKETING_VERSION 到指定版本号"
  echo "  2. 若提供发布说明，写入 RELEASE_NOTES.md"
  echo "  3. 提交版本号变更（含说明文件）"
  echo "  4. 合并 dev 到 main"
  echo "  5. 打 tag (v<版本号>)"
  echo "  6. 推送 main 和 tag"
  echo "  7. 切回 dev"
  echo "  8. GitHub Actions 自动构建并发布 Release"
  echo "     （自定义说明在上，自动生成的 commit 列表在下）"
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

TAG="v${VERSION}"
CURRENT_BRANCH=$(git branch --show-current)
PBXPROJ="hagimi-monitor.xcodeproj/project.pbxproj"
NOTES_FILE="RELEASE_NOTES.md"

echo "=== 发布 ${TAG} ==="

# 检查工作区（允许未提交的版本号和说明文件变更）
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

# 写入发布说明（始终生成文件，确保 workflow 的 body_path 不会找不到文件）
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

# 提交版本号变更
if [[ -n $(git status --porcelain) ]]; then
  echo ">>> 提交版本号变更..."
  git add "$PBXPROJ" "$NOTES_FILE"
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
