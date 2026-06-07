## Why

HagimiMonitor 当前没有更新提示机制，用户需要主动打开 GitHub Release 页面确认是否有新版本。完整 Sparkle 自动更新需要 EdDSA 更新签名、Developer ID 签名、公证和更复杂的发布流水线；这些前置条件当前尚未准备好。

本变更先实现轻量更新检查：应用内查询 GitHub Releases，发现新版本后引导用户手动下载并安装。该方案不自动替换 app bundle，不引入 Sparkle，也不要求 Apple Developer ID、公证或 Sparkle 私钥。

## What Changes

- 在 About 页面显示真实 Bundle 版本号，替换硬编码版本文本
- 增加“检查更新”入口，手动触发 GitHub Release 检查
- 请求 GitHub latest release API，解析最新版本、发布时间、说明和下载地址
- 将当前 `CFBundleShortVersionString` 与最新 release tag/version 比较
- 有新版本时展示版本信息，并提供“下载更新”按钮
- 下载按钮打开 GitHub Release 页面或 release asset 下载链接，由用户手动安装
- 网络失败、无 release、版本解析失败时展示清晰状态
- 为沙盒 target 增加 outbound network entitlement

## Capabilities

### New Capabilities

- `github-release-update-check`: 从 GitHub Releases 检查最新版本，比较当前版本，并展示可下载更新
- `manual-update-download`: 打开 GitHub Release 页面或下载链接，由用户自行下载并安装
- `update-network-entitlement`: 为沙盒 target 配置网络访问权限

### Modified Capabilities

- `settings-about`: About 页面读取 Bundle 版本号，并提供更新检查入口

## Impact

- **不新增第三方依赖**: 不使用 Sparkle
- **不需要发布私钥**: 不需要 Sparkle EdDSA key
- **不需要 Apple 公证链路**: 本变更不负责自动安装和 app bundle 替换
- **修改文件**: `SettingsView.swift`、可能新增 `UpdateChecker`/`UpdateModels` 等轻量服务
- **构建配置**: HagimiMonitor 沙盒 target 需要 `com.apple.security.network.client = true`
- **后续升级路径**: 未来准备好 Developer ID、公证和 CI secrets 后，可新建 Sparkle 自动更新变更
