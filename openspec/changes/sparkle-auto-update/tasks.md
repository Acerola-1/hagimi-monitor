## 1. 变更范围收窄

- [ ] 1.1 确认本变更不集成 Sparkle、不生成 appcast、不做自动安装
- [ ] 1.2 确认更新入口只负责检查 GitHub Release 并打开下载页面

## 2. 沙盒网络权限

- [ ] 2.1 为 HagimiMonitor target 创建或更新 entitlements 文件
- [ ] 2.2 保持 `com.apple.security.app-sandbox` 为 true
- [ ] 2.3 添加 `com.apple.security.network.client` 为 true
- [ ] 2.4 在 Xcode project build settings 中配置 `CODE_SIGN_ENTITLEMENTS`

## 3. 版本显示

- [ ] 3.1 将 About 页面硬编码的 `Text("版本 1.0.0")` 改为读取 `CFBundleShortVersionString`
- [ ] 3.2 当 Bundle 版本为空时显示 `版本 未知`
- [ ] 3.3 如有 build number，可选择在调试信息中读取 `CFBundleVersion`，但不作为首版 UI 必需项

## 4. GitHub Release 更新检查服务

- [ ] 4.1 新增轻量更新检查模型，表示 idle/checking/up-to-date/update-available/failed 状态
- [ ] 4.2 新增 GitHub latest release 响应模型，解析 `tag_name`、`html_url`、`published_at`、`name`、`body`、`assets`
- [ ] 4.3 实现更新检查服务，请求 `https://api.github.com/repos/acerola/hagimi-monitor/releases/latest`
- [ ] 4.4 实现版本规范化，支持去除 `v` 前缀
- [ ] 4.5 实现数字段版本比较，避免字符串比较误判
- [ ] 4.6 选择下载 URL：优先使用匹配 `.dmg`/`.zip` 的 asset，否则回退到 release `html_url`

## 5. About 页面交互

- [ ] 5.1 在 Settings → About 添加“检查更新”按钮
- [ ] 5.2 检查中禁用按钮并显示进行中状态
- [ ] 5.3 当前已是最新版时显示简洁状态
- [ ] 5.4 有新版本时显示最新版本号和“下载更新”按钮
- [ ] 5.5 点击“下载更新”使用系统浏览器打开下载 URL
- [ ] 5.6 请求失败时显示可恢复错误状态，并允许用户再次检查

## 6. 测试与验证

- [ ] 6.1 为版本规范化和版本比较添加单元测试
- [ ] 6.2 为 GitHub release 响应解析添加单元测试
- [ ] 6.3 本地构建沙盒 target，验证 entitlements 正确嵌入
- [ ] 6.4 手动验证 About 页面版本显示、检查更新、下载按钮打开 URL
- [ ] 6.5 验证网络失败时 UI 不崩溃且可重试
