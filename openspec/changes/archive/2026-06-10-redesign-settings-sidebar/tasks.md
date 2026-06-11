## 1. 准备与脚手架

- [x] 1.1 新建目录 `HagimiMonitor/Views/Settings/`，确认 Xcode 项目自动收纳新文件
- [x] 1.2 在 `SettingsView.swift` 或新建 `SettingsRoute.swift` 中定义 `enum SettingsRoute: Hashable { case general; case module(MonitorKind); case about }`
- [x] 1.3 阅读现有 `SettingsView.swift` 各 Tab 内容块，标记需要原样迁移的子视图（常规 / 关于 / 6 个模块行）

## 2. 拆分详情视图

- [x] 2.1 新建 `GeneralSettingsView.swift`，把现有「常规」Tab 的全部表单原样迁入；保留 `@AppStorage` / `@EnvironmentObject` 依赖
- [x] 2.2 新建 `AboutSettingsView.swift`，迁移「关于」Tab 内容（版本信息、更新检查按钮、GitHub 链接等）
- [x] 2.3 新建 `ModuleSettingsView.swift`，接收 `kind: MonitorKind` 参数；当前阶段渲染该模块的可见性开关行 + 预留 `// MARK: - 子项可见性（后续）` placeholder

## 3. 实现 sidebar

- [x] 3.1 新建 `SettingsSidebar.swift`，用 `List(selection:)` + `Label` 绑定 `SettingsRoute`
- [x] 3.2 平铺一级项「常规」（图标 `gearshape`）、「关于」（图标 `info.circle`），中间用 `Section { … } header: { Label("模块", systemImage: "square.grid.2x2") }` 包裹 6 个模块子项，header 不参与 selection
- [x] 3.3 为 6 个模块子项绑定 `.module(.cpu/.gpu/.memory/.storage/.network/.battery)` 路由与对应 SF Symbol（参考 design.md D6）
- [x] 3.4 调用 `.listStyle(.sidebar)` 与 `.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)`

## 4. 组装 NavigationSplitView

- [x] 4.1 在 `SettingsView.swift` 中用 `@State private var route: SettingsRoute = .general` 维护选中态
- [x] 4.2 用 `NavigationSplitView { SettingsSidebar(selection: $route) } detail: { … }` 替换原 `TabView`
- [x] 4.3 在 detail 闭包内 `switch route` 分发到 `GeneralSettingsView` / `ModuleSettingsView(kind:)` / `AboutSettingsView`
- [x] 4.4 给根视图加 `.frame(minWidth: 640, idealWidth: 720, minHeight: 480, idealHeight: 520)`
- [x] 4.5 删除原 `TabView` 残留代码与 Tab item 定义

## 5. 视觉与依赖注入校对

- [ ] 5.1 启动应用，确认 sidebar 与 detail 都正确显示 Liquid Glass 效果（浅色 / 深色 / 跟随系统三种主题各跑一遍）
- [ ] 5.2 验证更新检查按钮（`UpdateChecker`）等依赖原 `EnvironmentObject` / `@StateObject` 的功能在新结构下依旧可用
- [ ] 5.3 验证 `DISPLAY_CONTROL` 条件编译下 Direct 构建的显示器控制选项位置仍正确（如属于「常规」则保留在 `GeneralSettingsView`）
- [ ] 5.4 调整 sidebar 选中态 / hover 态在 Liquid Glass 背景下的可读性

## 6. 构建与回归

- [x] 6.1 `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug build` 通过
- [x] 6.2 `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build` 通过
- [ ] 6.3 手动验证：模块可见性开关切换后，菜单栏面板对应模块隐藏 / 显示符合预期（行为不应被本次重构影响）
- [ ] 6.4 手动验证：所有原「常规」「关于」Tab 中的设置项均保留且功能正常

## 7. 收尾

- [ ] 7.1 更新 README（如截图涉及设置窗口，标注「截图待更新」即可，不强求本次替换图片）
- [ ] 7.2 在 PR / commit 信息中说明 UI 重构范围与后续「子项可见性」「温度监控」的预留位置
