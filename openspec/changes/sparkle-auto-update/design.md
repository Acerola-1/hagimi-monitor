## Context

HagimiMonitor 是一个 macOS 26+ 菜单栏系统监控应用，使用 SwiftUI 构建，当前无任何第三方依赖。项目有两个 build target：
- **HagimiMonitor**（沙盒，`ENABLE_APP_SANDBOX = YES`，Bundle ID: `com.acerola.hagimi-monitor`）
- **HagimiMonitorDirect**（非沙盒，Bundle ID: `com.acerola.hagimi-monitor.direct`）

当前没有任何更新机制，SettingsView 中版本号硬编码为 `"版本 1.0.0"`。项目无 entitlements 文件，无 Info.plist 文件（自动生成），无 SPM/CocoaPods 依赖。

## Goals / Non-Goals

**Goals:**
- 用户可在应用内一键检查更新、下载、安装并自动重启到新版本
- 通过 GitHub Release 分发更新，appcast.xml 作为 Sparkle 的更新源
- 沙盒 target 完整支持（通过 Sparkle XPC 辅助进程替换 app bundle）
- GitHub Actions 自动化：tag push → build → sign → notarize → generate_appcast → create release
- 遵循项目现有代码风格（@Observable、4 空格缩进、Swift API Design Guidelines）

**Non-Goals:**
- 不做增量更新（delta updates），初版只用全量 zip
- 不做更新频道（beta/nightly），初版只用 stable channel
- 不做 Mac App Store 分发（App Store 有自己的更新机制）
- 不做后台自动下载安装（初版只做用户手动触发检查）
- 不处理 Direct target 的更新（先只做沙盒 target，验证通过后再扩展）

## Decisions

### 1. 选择 Sparkle 2.x 而非自定义实现

**选择**: Sparkle 2.9.x（SPM 集成）

**理由**: 
- 沙盒应用无法写入 `/Applications/`，自定义实现只能提示用户手动下载
- Sparkle 通过 XPC 辅助进程突破沙盒限制，实现真正的自动安装重启
- 业界标准（Ghostty、Boring Notch、DockDoor、Maccy 等均使用）
- 支持 EdDSA 签名验证、原子替换 app bundle、launchd 自动重启

**替代方案**:
- AutoUpdate (TopScrech): 直接调 GitHub API，不需 appcast，但生态不成熟，无沙盒 XPC
- 自定义 GitHub API + 手动下载: 沙盒内无法替换 app，体验差
- Apple Mac App Store: 不在本次范围内

### 2. appcast.xml 托管在 GitHub Release asset

**选择**: 创建专用 "appcast" release，将 appcast.xml 作为 asset 上传

**理由**:
- 无需额外服务器或 GitHub Pages
- 一条 `gh release upload appcast appcast.xml --clobber` 即可更新
- URL 格式: `https://github.com/acerola/hagimi-monitor/releases/download/appcast/appcast.xml`

**替代方案**:
- GitHub Pages 托管: 需要额外分支/Actions 部署，增加复杂度
- repo 内文件 + raw.githubusercontent.com: 受 CDN 缓存影响，更新不及时

### 3. UpdaterBridge 使用 @Observable 模式

**选择**: 使用 Swift Observation 框架的 `@Observable` 宏

**理由**:
- 项目 target 是 macOS 26+，完全支持 @Observable
- 比 ObservableObject 更轻量，与 SwiftUI 的 @Environment 集成更自然
- 参考 TablePro 的 UpdaterBridge 模式，已在生产环境验证

**替代方案**:
- ObservableObject + @Published: 旧模式，功能等价但更冗余
- 直接暴露 SPUStandardUpdaterController: 违反封装原则

### 4. 先在沙盒 target 实现

**选择**: 仅在 HagimiMonitor（沙盒）target 上实现 Sparkle

**理由**:
- 沙盒 target 是主要分发版本，更新需求更迫切
- 沙盒配置更复杂（需要 XPC entitlements），验证通过后 Direct target 只是子集
- Direct target 以后只需去掉 XPC 配置即可

### 5. 签名顺序：由内到外，不用 --deep

**选择**: XPC Services → Helper Tools → Framework → App，严格按顺序签名

**理由**:
- `codesign --deep` 会破坏 XPC Services 的 entitlement，导致沙盒更新失败
- Peter Steinberger 的实战经验验证了这一点
- Sparkle 官方文档明确禁止使用 --deep

## Risks / Trade-offs

- **[风险] Apple 证书配置复杂** → 缓解: GitHub Actions 中使用 base64 编码的 P12 证书 + notarytool API key，参考 boring.notch 的 workflow
- **[风险] 签名顺序错误导致沙盒更新失败** → 缓解: CI 中签名脚本严格按顺序执行，添加 `codesign --verify` 验证步骤
- **[风险] EdDSA 私钥泄露** → 缓解: 私钥存 GitHub Secrets，CI 中通过 stdin 传入，不写入磁盘
- **[风险] appcast.xml 更新延迟** → 缓解: 使用 GitHub Release asset 托管，CDN 缓存时间短（~5min）
- **[权衡] 引入 Sparkle 作为首个第三方依赖** → 项目迟早需要更新机制，Sparkle 是最小必要依赖
- **[权衡] 初版不做自动下载** → 减少复杂度，用户手动检查更新即可，后续可启用 `automaticallyChecksForUpdates`
