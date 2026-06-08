#!/bin/bash
# 构建并启动指定分支的 HagimiMonitor
# 用法: ./launch.sh [分支名] [版本]
# 示例: ./launch.sh dev
#       ./launch.sh dev direct
#       ./launch.sh feature/liquid-glass-refactor

set -e

BRANCH="${1:-$(git branch --show-current)}"
VERSION="${2:-direct}"
CURRENT=$(git branch --show-current)
PROJECT="hagimi-monitor.xcodeproj"
BUILD_DIR="/tmp/hagimi-builds"

case "$VERSION" in
  direct|full|pro)
    SCHEME="HagimiMonitorDirect"
    APP_NAME="HagimiMonitor"
    ;;
  appstore|store|sandbox)
    SCHEME="HagimiMonitor"
    APP_NAME="HagimiMonitor"
    ;;
  *)
    SCHEME="HagimiMonitorDirect"
    APP_NAME="HagimiMonitor"
    ;;
esac

mkdir -p "$BUILD_DIR/$BRANCH"

# 切换分支
if [ "$BRANCH" != "$CURRENT" ]; then
    echo "切换分支: $CURRENT → $BRANCH"
    git checkout "$BRANCH"
fi

# 构建
echo "构建 $BRANCH 分支 ($SCHEME)..."
BUILD_LOG="$BUILD_DIR/$BRANCH/xcodebuild.log"
if xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/$BRANCH" \
    -derivedDataPath "$BUILD_DIR/$BRANCH/DerivedData" \
    build >"$BUILD_LOG" 2>&1; then
    grep -E "\\*\\* BUILD SUCCEEDED \\*\\*" "$BUILD_LOG" | tail -1
else
    echo "构建失败，最近日志如下: $BUILD_LOG"
    tail -80 "$BUILD_LOG"
    exit 1
fi

# 启动
APP_PATH="$BUILD_DIR/$BRANCH/$APP_NAME.app"
if [ -d "$APP_PATH" ]; then
    echo "启动 $BRANCH 版本 ($SCHEME): $APP_PATH"
    echo "关闭正在运行的 HagimiMonitor 实例..."
    killall HagimiMonitor >/dev/null 2>&1 || true
    killall HagimiMonitorDirect >/dev/null 2>&1 || true
    sleep 0.3
    open -n "$APP_PATH"
else
    echo "错误: 找不到构建产物 $APP_PATH"
    exit 1
fi

# 切回原分支
if [ "$BRANCH" != "$CURRENT" ]; then
    git checkout "$CURRENT"
    echo "已切回 $CURRENT"
fi
