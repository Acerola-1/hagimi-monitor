#!/bin/bash
# 构建并启动指定分支的 HagimiMonitor
# 用法: ./launch.sh [分支名] [版本]
#       ./launch.sh -p          构建并打包到项目 build/ 目录
# 示例: ./launch.sh dev
#       ./launch.sh dev direct
#       ./launch.sh -p

set -e

# 解析 -p 标志
PACKAGE=false
REVEAL=false
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--package)
            PACKAGE=true
            shift
            ;;
        -r|--reveal)
            REVEAL=true
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

BRANCH="${1:-$(git branch --show-current)}"
VERSION="${2:-direct}"
CURRENT=$(git branch --show-current)
PROJECT="hagimi-monitor.xcodeproj"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/tmp/builds"
PACKAGE_DIR="$ROOT_DIR/build"

case "$VERSION" in
    direct|full|pro)
        SCHEME="HagimiMonitorDirect"
        # Direct target 产物名已改为 HagimiMonitorDirect(消除与沙盒 target 同名冲突)
        APP_NAME="HagimiMonitorDirect"
        ;;
    appstore|store|sandbox)
        SCHEME="HagimiMonitor"
        APP_NAME="HagimiMonitor"
        ;;
    *)
        SCHEME="HagimiMonitorDirect"
        APP_NAME="HagimiMonitorDirect"
        ;;
esac

mkdir -p "$BUILD_DIR/$BRANCH"

# 切换分支
if [ "$BRANCH" != "$CURRENT" ]; then
    echo "切换分支: $CURRENT → $BRANCH"
    git checkout "$BRANCH"
    # 任何退出路径(构建失败、产物缺失、set -e 中断)都切回原分支,
    # 避免把仓库遗留在非预期的检出状态。
    trap 'if [ -n "$CURRENT" ] && [ "$(git branch --show-current)" = "$BRANCH" ]; then git checkout "$CURRENT" >/dev/null 2>&1; fi' EXIT
fi

# 构建
echo "构建 $BRANCH 分支 ($SCHEME)..."
BUILD_LOG="$BUILD_DIR/$BRANCH/xcodebuild.log"
DERIVED_DATA_DIR="$BUILD_DIR/$BRANCH/DerivedData"

if xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    build >"$BUILD_LOG" 2>&1; then
    grep -E "\\*\\* BUILD SUCCEEDED \\*\\*" "$BUILD_LOG" | tail -1
else
    echo "构建失败，最近日志如下: $BUILD_LOG"
    tail -80 "$BUILD_LOG"
    exit 1
fi

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
APP_PATH="$BUILD_DIR/$BRANCH/$APP_NAME.app"

# 产物缺失立即报错:静默跳过复制会接着检查 APP_PATH,把上一次的旧构建
# 当成新构建启动,排查问题时极具迷惑性。
if [ ! -d "$BUILT_APP" ]; then
    echo "错误: 构建产物不存在: $BUILT_APP"
    exit 1
fi
rm -rf "$APP_PATH"
ditto "$BUILT_APP" "$APP_PATH"

# 启动
if [ -d "$APP_PATH" ]; then
    echo ""
    echo "================================================================"
    echo "  App 路径 (用于系统设置授权):"
    echo "  $APP_PATH"
    echo "================================================================"
    echo ""
    echo "启动 $BRANCH 版本 ($SCHEME)..."
    echo "关闭正在运行的 HagimiMonitor 实例..."
    killall HagimiMonitor >/dev/null 2>&1 || true
    killall HagimiMonitorDirect >/dev/null 2>&1 || true
    
    # 优雅等待旧进程完全退出
    for _ in {1..20}; do
        if ! pgrep -x HagimiMonitor >/dev/null 2>&1 && ! pgrep -x HagimiMonitorDirect >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done

    open "$APP_PATH"

    # 启动健康检查
    sleep 0.6
    if pgrep -f "$APP_PATH/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "✅ $APP_NAME 启动成功并在后台运行！"
    else
        echo "⚠️ 提示: 未在活动进程中检测到 $APP_NAME，可能正在初始化或需要权限确认。"
    fi

    # 仅当传入 -r/--reveal 时在 Finder 中显示,方便拖到系统设置授权列表
    if $REVEAL; then
        open -R "$APP_PATH"
    fi
else
    echo "错误: 找不到构建产物 $APP_PATH"
    exit 1
fi

# 切回原分支(此后 trap 不再重复切换,见下)
if [ "$BRANCH" != "$CURRENT" ]; then
    git checkout "$CURRENT"
    echo "已切回 $CURRENT"
    trap - EXIT
fi

# 异步打包到 build/ 目录
if $PACKAGE; then
    (
        mkdir -p "$PACKAGE_DIR"
        # 用 $BRANCH 而不是现查 git:此时已切回 $CURRENT,现查会抓错分支名。
        ZIP_NAME="HagimiMonitor-$BRANCH-$(date +%Y%m%d%H%M%S).zip"
        ZIP_PATH="$PACKAGE_DIR/$ZIP_NAME"
        cd "$BUILD_DIR/$BRANCH"
        zip -r -q "$ZIP_PATH" "$APP_NAME.app"
        echo "已打包: $ZIP_PATH"
    ) &
    echo "后台打包中..."
fi
