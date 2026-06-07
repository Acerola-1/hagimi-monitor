## 1. Sparkle SPM 集成与项目配置

- [ ] 1.1 在 Xcode 项目中添加 Sparkle 2.x SPM 依赖（package URL: `https://github.com/sparkle-project/Sparkle`），仅链接到 HagimiMonitor target
- [ ] 1.2 使用 Sparkle 的 `generate_keys` 工具生成 EdDSA 密钥对，导出公钥备用
- [ ] 1.3 在 HagimiMonitor target 的 Info.plist 中添加 `SUFeedURL`（指向 `https://github.com/acerola/hagimi-monitor/releases/download/appcast/appcast.xml`）、`SUPublicEDKey`（EdDSA 公钥）、`SUEnableInstallerLauncherService`（true）

## 2. Entitlements 配置

- [ ] 2.1 为 HagimiMonitor（沙盒）target 创建 entitlements 文件 `HagimiMonitor/HagimiMonitor.entitlements`
- [ ] 2.2 在 entitlements 中添加 `com.apple.security.app-sandbox`（true）、`com.apple.security.network.client`（true）
- [ ] 2.3 在 entitlements 中添加 `com.apple.security.temporary-exception.mach-lookup.global-name` 数组，包含 `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` 和 `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`
- [ ] 2.4 在 Xcode project build settings 中将 `CODE_SIGN_ENTITLEMENTS` 指向新创建的 entitlements 文件
- [ ] 2.5 构建验证：沙盒 target 编译通过，entitlements 正确嵌入

## 3. UpdaterBridge 实现

- [ ] 3.1 创建 `HagimiMonitor/UpdaterBridge.swift`，实现 `@Observable @MainActor final class UpdaterBridge`
- [ ] 3.2 在 UpdaterBridge 中创建 `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`
- [ ] 3.3 通过 KVO 观察 `controller.updater.canCheckForUpdates`，同步到 `canCheckForUpdates` 属性
- [ ] 3.4 实现 `checkForUpdates()` 方法，调用 `controller.updater.checkForUpdates()`
- [ ] 3.5 编译验证：UpdaterBridge 可被正确实例化

## 4. App 入口集成

- [ ] 4.1 在 `HagimiMonitorApp.swift` 中添加 `@StateObject private var updaterBridge = UpdaterBridge()`
- [ ] 4.2 在 MenuBarExtra 的内容视图中注入 `.environment(updaterBridge)`
- [ ] 4.3 修改 `AppMenuCommands` 接收 UpdaterBridge 参数，在 CommandGroup(after: .appInfo) 中添加 "检查更新…" 按钮
- [ ] 4.4 编译验证：App 启动正常，菜单中出现 "检查更新…" 项

## 5. Settings About 页面更新

- [ ] 5.1 将 `SettingsView.swift` 第 249 行硬编码的 `Text("版本 1.0.0")` 改为读取 `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`，nil 时显示 "版本 未知"
- [ ] 5.2 在 About 页面添加 "检查更新" 按钮，通过 `@Environment(UpdaterBridge.self)` 调用 `checkForUpdates()`
- [ ] 5.3 编译验证：Settings About 页面显示正确的 Bundle 版本号

## 6. appcast.xml 模板

- [ ] 6.1 在项目根目录创建 `appcast.xml` 模板文件，包含 Sparkle RSS 格式骨架
- [ ] 6.2 模板中设置 `sparkle:minimumSystemVersion` 为 `26.0`，`sparkle:hardwareRequirements` 为 `arm64`
- [ ] 6.3 创建 `scripts/generate_appcast.sh` 辅助脚本，封装 `generate_appcast` 工具调用

## 7. GitHub Actions Release Workflow

- [ ] 7.1 创建 `.github/workflows/release.yml`，触发条件为 `push tags: v*`
- [ ] 7.2 添加 Build 步骤：`xcodebuild archive` 构建 HagimiMonitor target
- [ ] 7.3 添加 Code Sign 步骤：按 XPC → Helper Tools → Framework → App 顺序签名，不使用 `--deep`
- [ ] 7.4 添加 Notarize 步骤：`xcrun notarytool submit` + `xcrun stapler staple`
- [ ] 7.5 添加 Generate Appcast 步骤：下载 Sparkle 工具，用 `generate_appcast --ed-key-file -` 从 stdin 读取私钥签名
- [ ] 7.6 添加 Create Release 步骤：`gh release create` 上传 app artifact + `gh release upload appcast appcast.xml --clobber`
- [ ] 7.7 配置 GitHub Secrets: `APPLE_SIGNING_CERT_P12`、`APPLE_SIGNING_CERT_PASSWORD`、`NOTARY_API_KEY_PATH`、`NOTARY_API_KEY_ID`、`NOTARY_API_ISSUER`、`SPARKLE_EDDSA_PRIVATE_KEY`

## 8. 端到端验证

- [ ] 8.1 本地构建沙盒 target，验证 Sparkle 初始化成功，"检查更新…" 菜单项可点击
- [ ] 8.2 手动创建测试 Release + appcast.xml，验证应用能检测到更新
- [ ] 8.3 验证更新下载、安装、重启流程在沙盒环境下正常工作
- [ ] 8.4 验证 Settings About 页面版本号显示正确
