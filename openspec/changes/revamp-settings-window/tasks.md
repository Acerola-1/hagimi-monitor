## 1. 数据模型（先于 UI）

- [x] 1.1 在 `HagimiMonitor/MonitorModels.swift` 新增 `MetricSwitch` 结构体（`id`/`title`/`isDefault`，遵循 `Identifiable, Hashable`）
- [x] 1.2 在 `MonitorKind` 上加 `var availableMetrics: [MetricSwitch]`，为每个 case 返回至少一项占位（例如 `cpu.overall`/`gpu.overall`/`memory.overall`/`storage.overall`/`network.overall`/`battery.overall`）
- [x] 1.3 在 `MonitorSettings` 新增 `@Published private(set) var enabledMetrics: [MonitorKind: Set<String>]` 与 `isMetricEnabled(_:for:)` / `setMetric(_:enabled:for:)`
- [x] 1.4 实现 UserDefaults 持久化：key `settings.enabledMetrics.<kind.rawValue>`，缺失时回退到 `availableMetrics.filter { $0.isDefault }.map(\.id)`
- [x] 1.5 在 `setupBindings()` 中添加 `enabledMetrics` 的持久化订阅（按 kind 分别写入，避免单个变化全表 rewrite）

## 2. 设置窗口骨架

- [x] 2.1 新建 `HagimiMonitor/Views/Settings/SettingsRootView.swift`，使用受控紧凑双栏容器
- [x] 2.2 在 SettingsRootView 中定义 `@State private var selection: SettingsRoute`，默认 `.general`
- [x] 2.3 设置窗口尺寸：`.frame(minWidth: 560, idealWidth: 600, minHeight: 360, idealHeight: 382)`，移除任何固定 `width/height`
- [x] 2.4 重写 `HagimiMonitor/Views/Settings/SettingsSidebar.swift`：侧栏 row **只用** `Label(kind.title, systemImage: kind.symbol).tag(SettingsRoute.module(kind))`，移除所有内嵌 Toggle
- [x] 2.5 设置侧栏固定宽度 `164`，避免 split view 产生额外空白列
- [x] 2.6 在详情列根据 `selection` 路由到 `GeneralSettingsView` / `ModuleSettingsView` / `DisplayModuleSettingsView`（DISPLAY_CONTROL）/ `AboutSettingsView`
- [x] 2.7 保留 `SettingsWindowTracker` 的 `NSViewRepresentable` 桥接逻辑，让 `SettingsWindowPresenter` 仍能跟踪窗口

## 3. 详情页重写

- [x] 3.1 `GeneralSettingsView`：用 `Form .grouped` + `LabeledContent` 重构 `开机自启`/`主题`/`配色`/`负载环` 四项；`Toggle`/`Picker` 直接绑 `settings.*`
- [x] 3.2 `ModuleSettingsView`：第一个 Section「显示」放 `Toggle("在面板中显示", isOn:)`；第二个 Section「检测项目」`ForEach(kind.availableMetrics)` 渲染 checkmark 选择行
- [x] 3.2a 将「检测项目」从 switch 改为整行 checkmark 选择器，并限制每个模块最多选中 4 项
- [x] 3.3 `ModuleSettingsView`：底部加一个 `Button("重置默认值") { ... }`，`.buttonStyle(.glass)`；点击后把该 kind 的 `enabledMetrics` 恢复为 `availableMetrics.filter { $0.isDefault }.map(\.id)`
- [x] 3.4 `DisplayModuleSettingsView`（DISPLAY_CONTROL）：迁移现有 4 个 Toggle 到 `Form .grouped`，保持字段绑定不变
- [x] 3.5 `AboutSettingsView`：顶部 App 信息块包在 `GlassEffectContainer` 内并加 `glassEffect(.regular, in: .rect(cornerRadius: 14))`；"检查更新"/"下载更新" 用 `.buttonStyle(.glassProminent)`；GitHub / Releases 链接用 `.buttonStyle(.glass)`
- [x] 3.6 `AboutSettingsView`：把所有手拼的 `HStack { Text, Spacer, Button }` 替换为 `LabeledContent`

## 4. 入口与桥接

- [x] 4.1 在 `HagimiMonitorApp.swift` 把 `Settings { SettingsView(...) }` 改为 `Settings { SettingsRootView(...) }`
- [x] 4.2 删除 `HagimiMonitor/SettingsView.swift` 中的旧 `SettingsView` / `SettingsSelection`（保留 `SettingsTab` 与 `SettingsWindowTracker`，迁移到合适位置或继续放原文件中只保留这两个类型）
- [x] 4.3 在 `SettingsWindowPresenter.swift` 增加 `SettingsTab → SettingsRoute` 的转换函数，用 `NotificationCenter` 或 `@Binding` 把目标 route 推给已打开的 SettingsRootView
- [x] 4.4 校验菜单栏面板"关于"按钮 (`MonitorPanelView.swift`) 仍能直达 About 页

## 5. 构建与可视验证

- [x] 5.0 收紧设置窗口视觉密度：固定 164pt 侧栏、窗口 ideal 600×382，并统一无页面标题、无滚动条的 `SettingsPage` / `SettingsGroup` / `SettingsRow` 布局
- [x] 5.1 `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug build` 通过
- [x] 5.2 `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build` 通过
- [ ] 5.3 浅色 / 深色 / 跟随系统三种主题切换，逐页（常规 / 各模块 / 关于）目视检查
- [ ] 5.4 拉伸窗口最小尺寸和较大尺寸，确认布局不破
- [ ] 5.5 验证 App Store target 不含 `DisplayModuleSettingsView`，侧栏不出现"显示器"项
- [ ] 5.6 验证持久化：勾选/取消一项检测项目 → 重启 App → 状态恢复
- [ ] 5.7 验证从面板"关于"按钮点击能直达 About 页
