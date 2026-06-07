## Why

HagimiMonitor 当前没有自动更新机制，用户需要手动检查 GitHub Release 下载新版本。对于菜单栏常驻应用，用户往往不会主动关注版本更新，导致长期运行旧版本。需要实现应用内检测更新、下载、安装并重启的完整自动更新流程。

## What Changes

- 集成 Sparkle 2.x 框架作为 SPM 依赖，实现 macOS 应用内自动更新
- 在 App 入口（HagimiMonitorApp）初始化 SPUStandardUpdaterController
- 创建 UpdaterBridge（@Observable）桥接 Sparkle 与 SwiftUI
- 在菜单栏面板和 App 菜单中添加"检查更新"入口
- 修复 SettingsView 中硬编码的版本号，改为读取 Bundle.main
- 为沙盒 target 创建 entitlements 文件，添加 Sparkle XPC 所需的 mach-lookup 例外
- 配置 Info.plist 中的 SUFeedURL、SUPublicEDKey、SUEnableInstallerLauncherService
- 创建 appcast.xml 模板，下载 URL 指向 GitHub Release assets
- 搭建 GitHub Actions workflow：build → sign → notarize → generate_appcast → create release

## Capabilities

### New Capabilities
- `sparkle-updater`: Sparkle 2 框架集成，包含 UpdaterBridge、SPUStandardUpdaterController 初始化、SwiftUI 环境注入、检查更新 UI 入口
- `appcast-feed`: appcast.xml 生成与托管方案，GitHub Release 作为下载源，EdDSA 签名流程
- `release-ci`: GitHub Actions 自动化发布 workflow，包含 Apple 代码签名、公证、appcast 生成与上传
- `sandbox-entitlements`: 沙盒 target 的 entitlements 配置，包含 Sparkle XPC mach-lookup 例外和网络访问权限

### Modified Capabilities
<!-- 无现有 specs，无需修改 -->

## Impact

- **新增依赖**: Sparkle 2.x（SPM），项目首个第三方依赖
- **修改文件**: HagimiMonitorApp.swift（注入 updater）、SettingsView.swift（修复硬编码版本号）、AppMenuCommands（添加检查更新菜单项）
- **新增文件**: UpdaterBridge.swift、entitlements 文件（沙盒 target）、appcast.xml、GitHub Actions workflow
- **构建配置**: Xcode project 需添加 Sparkle SPM、Info.plist 需添加 Sparkle 相关 key、entitlements 需添加 XPC 例外
- **两个 target**: HagimiMonitor（沙盒）需完整 XPC 配置；HagimiMonitorDirect（非沙盒）配置更简单
- **CI/CD**: 需要 Apple Developer ID 证书和 notarytool API 密钥配置到 GitHub Secrets
