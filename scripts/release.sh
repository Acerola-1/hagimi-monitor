#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法: ./scripts/release.sh <版本号> [选项...]

发布说明分类（每个选项可重复，按出现顺序追加；空小节自动隐藏）:
  -n, --new   <文本>   新功能
  -f, --fix   <文本>   修复
  -o, --opt   <文本>   优化与体验
  -c, --code  <文本>   代码质量
  -m, --raw   <文本>   原样追加（兼容旧用法，未分类）

示例:
  ./scripts/release.sh 0.8.3 -o "优化内存排行算法，显示更精准"
  ./scripts/release.sh 0.9.0 \
      -n "新增电池循环次数显示" \
      -f "修复 WiFi 切以太网后网络模块无反应" \
      -o "重写负载聚合逻辑，改用 softmax" \
      -c "删除残留测试代码"
  ./scripts/release.sh 0.8.3                          # 不写说明，仅占位
  ./scripts/release.sh 0.8.3 -m "$(cat notes.md)"     # 整段原样写入

前置条件:
  - gh CLI 已安装并登录 (gh auth login)
  - 工作区干净（仅允许版本号和发布说明变更）

流程:
  1. 更新 MARKETING_VERSION
  2. 写入 RELEASE_NOTES.md（按分类生成结构化模板）
  3. 提交到 release/<版本号> 分支
  4. 推送分支，创建 PR 到 main
  5. 自动合并 PR（squash）
  6. 打 tag v<版本号> 并推送
  7. 清理发布分支，切回 dev
  8. GitHub Actions 自动构建并发布 Release
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

VERSION="$1"
shift

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误: 版本号格式不正确，应为 x.y.z (如 0.1.0)"
  exit 1
fi

# 收集分类条目
NEW_ITEMS=()
FIX_ITEMS=()
OPT_ITEMS=()
CODE_ITEMS=()
RAW_BLOCKS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--new)
      [[ $# -lt 2 ]] && { echo "错误: $1 需要一个文本参数"; exit 1; }
      NEW_ITEMS+=("$2"); shift 2 ;;
    -f|--fix)
      [[ $# -lt 2 ]] && { echo "错误: $1 需要一个文本参数"; exit 1; }
      FIX_ITEMS+=("$2"); shift 2 ;;
    -o|--opt)
      [[ $# -lt 2 ]] && { echo "错误: $1 需要一个文本参数"; exit 1; }
      OPT_ITEMS+=("$2"); shift 2 ;;
    -c|--code)
      [[ $# -lt 2 ]] && { echo "错误: $1 需要一个文本参数"; exit 1; }
      CODE_ITEMS+=("$2"); shift 2 ;;
    -m|--raw)
      [[ $# -lt 2 ]] && { echo "错误: $1 需要一个文本参数"; exit 1; }
      RAW_BLOCKS+=("$2"); shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      echo "错误: 未知选项 $1"; usage; exit 1 ;;
    *)
      # 兼容旧用法：第二个位置参数被视为整段原文
      RAW_BLOCKS+=("$1"); shift ;;
  esac
done

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

# ===== 组装发布说明 =====
HAS_CONTENT=0
if [[ ${#NEW_ITEMS[@]} -gt 0 || ${#FIX_ITEMS[@]} -gt 0 \
   || ${#OPT_ITEMS[@]} -gt 0 || ${#CODE_ITEMS[@]} -gt 0 \
   || ${#RAW_BLOCKS[@]} -gt 0 ]]; then
  HAS_CONTENT=1
fi

# 渲染单个分类（小节标题 + 列表项），空数组直接跳过
render_section() {
  local title="$1"; shift
  local -a items=("$@")
  [[ ${#items[@]} -eq 0 ]] && return 0
  echo "### ${title}"
  echo ""
  for item in "${items[@]}"; do
    echo "- ${item}"
  done
  echo ""
}

# 安装说明（中英双语）尾部
INSTALL_FOOTER=$(cat <<'FOOTER'
---

## 安装说明 / Installation

HagimiMonitor 尚未通过 Apple 公证（notarization），macOS 首次启动时可能会阻止运行。将 HagimiMonitor 安装到 `/Applications` 后，请执行以下命令：

```bash
sudo xattr -rd com.apple.quarantine /Applications/HagimiMonitor.app
```

HagimiMonitor is not notarized by Apple. macOS may block it on first launch. After installing to `/Applications`, run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/HagimiMonitor.app
```
FOOTER
)

if [[ $HAS_CONTENT -eq 1 ]]; then
  echo ">>> 写入发布说明到 ${NOTES_FILE}..."
  {
    echo "## 更新内容"
    echo ""
    render_section "新功能"     "${NEW_ITEMS[@]+"${NEW_ITEMS[@]}"}"
    render_section "修复"       "${FIX_ITEMS[@]+"${FIX_ITEMS[@]}"}"
    render_section "优化与体验" "${OPT_ITEMS[@]+"${OPT_ITEMS[@]}"}"
    render_section "代码质量"   "${CODE_ITEMS[@]+"${CODE_ITEMS[@]}"}"
    if [[ ${#RAW_BLOCKS[@]} -gt 0 ]]; then
      for block in "${RAW_BLOCKS[@]}"; do
        echo "${block}"
        echo ""
      done
    fi
    echo "${INSTALL_FOOTER}"
  } > "$NOTES_FILE"
else
  echo ">>> 未提供发布说明，写入占位（GitHub 仍会自动追加 commit 列表）"
  {
    echo "本次发布 ${TAG}。"
    echo ""
    echo "${INSTALL_FOOTER}"
  } > "$NOTES_FILE"
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
