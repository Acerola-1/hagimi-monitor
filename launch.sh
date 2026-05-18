#!/bin/bash
# 构建并启动指定分支的 HagimiMonitor
# 用法: ./launch.sh [分支名]
# 示例: ./launch.sh dev
#       ./launch.sh feature/liquid-glass-refactor

set -e

BRANCH="${1:-$(git branch --show-current)}"
CURRENT=$(git branch --show-current)
APP_NAME="HagimiMonitor"
PROJECT="hagimi-monitor.xcodeproj"
SCHEME="HagimiMonitor"
BUILD_DIR="/tmp/hagimi-builds"

mkdir -p "$BUILD_DIR"

# 切换分支
if [ "$BRANCH" != "$CURRENT" ]; then
    echo "切换分支: $CURRENT → $BRANCH"
    git checkout "$BRANCH"
fi

# 构建
echo "构建 $BRANCH 分支..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/$BRANCH" \
    build 2>&1 | grep -E "(BUILD|error:)" | tail -5

# 启动
APP_PATH="$BUILD_DIR/$BRANCH/$APP_NAME.app"
if [ -d "$APP_PATH" ]; then
    echo "启动 $BRANCH 版本: $APP_PATH"
    open "$APP_PATH"
else
    echo "错误: 找不到构建产物 $APP_PATH"
    exit 1
fi

# 切回原分支
if [ "$BRANCH" != "$CURRENT" ]; then
    git checkout "$CURRENT"
    echo "已切回 $CURRENT"
fi
