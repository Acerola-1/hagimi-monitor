## 1. 依赖与工程接入

- [ ] 1.1 在 Xcode 项目中通过 SPM 添加 `sindresorhus/KeyboardShortcuts` 依赖
- [ ] 1.2 将 `KeyboardShortcuts` 链接到 `HagimiMonitor` 与 `HagimiMonitorDirect` 两个 target
- [ ] 1.3 新建 `KeyboardShortcuts.Name` 扩展，定义 `.togglePinnedPanel`
- [ ] 1.4 确认新增依赖不影响 Sparkle 签名与 release 流程（构建两个 scheme 验证）

## 2. 采样可见性引用计数（MonitorStore）

- [ ] 2.1 在 `MonitorStore` 定义面板来源枚举（如 `PanelKind { menuBar, pinned }`）与可见消费者集合
- [ ] 2.2 新增 `panelDidAppear(_:)` / `panelDidDisappear(_:)`（带来源参数），由集合空/非空推导 `isPanelVisible`
- [ ] 2.3 仅在集合「空→非空」时启动进程采样、「非空→空」时停止，避免抖动
- [ ] 2.4 保留旧的无参 `panelDidAppear()/panelDidDisappear()` 作为 `.menuBar` 便捷封装
- [ ] 2.5 在 `HagimiMonitorTests` 补单测：单开、双开、关闭其一、全关的可见性与采样启停

## 3. 位置持久化与设置字段（MonitorSettings）

- [ ] 3.1 在 `MonitorSettings` 新增钉住窗口位置字段（origin x/y）及对应 UserDefaults 键
- [ ] 3.2 新增读写方法：保存位置、读取位置（无历史值返回 nil）
- [ ] 3.3 （可选）新增「开机自动显示钉住面板」开关字段，默认关闭
- [ ] 3.4 在 `SettingsTests` 补单测：位置持久化的读写与默认值

## 4. PinnedPanelController（钉住窗口）

- [ ] 4.1 新建 `PinnedPanelController`（`@MainActor`，持有独立 `NSPanel`），构造注入 `store` 与 `openSettings`
- [ ] 4.2 配置窗口：`isMovableByWindowBackground = true`、`level = .floating`、`hidesOnDeactivate = false`
- [ ] 4.3 配置 `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`（不含 `.canJoinAllSpaces`，仅当前桌面）
- [ ] 4.4 `windowDidResignKey` 不做关闭；不安装「点击外部关闭」监听（区别于 FluidPanelController）
- [ ] 4.5 用 `MonitorPanelView(store:)` + 透明背景 + 圆角毛玻璃承载内容（复用现有组件）
- [ ] 4.6 实现 `show()`：读取记忆位置，做屏幕可见区域相交校验与越界回收，非激活方式呈现（保持当前 App 前台）
- [ ] 4.7 实现 `hide()` 与 `toggle()`
- [ ] 4.8 实现 `windowDidMove` 回调：拖动结束后将 origin 写入 `MonitorSettings`
- [ ] 4.9 show/hide 时调用 `store.panelDidAppear(.pinned)` / `panelDidDisappear(.pinned)`

## 5. 悬停关闭控件（MonitorPanelView）

- [ ] 5.1 新增 `panelRole` 环境键（menuBar / pinned），默认 menuBar
- [ ] 5.2 `PinnedPanelController` 注入 `panelRole = .pinned`
- [ ] 5.3 在 `MonitorPanelView` 仅当 `panelRole == .pinned` 时显示悬停「取消钉住 / 关闭」按钮
- [ ] 5.4 关闭按钮点击回调走 controller 的 `hide()`（经环境闭包注入，参考现有 `fluidOpenSettings` 模式）

## 6. 快捷键接线（AppDelegate）

- [ ] 6.1 在 `AppDelegate` 惰性持有 `pinnedPanelController`
- [ ] 6.2 `applicationDidFinishLaunching` 中 `KeyboardShortcuts.onKeyUp(for: .togglePinnedPanel)` 调用 `toggle()`
- [ ] 6.3 （可选）若「开机自动显示」开启，则启动时 `show()` 钉住面板
- [ ] 6.4 校验未设置快捷键时不注册热键、不影响其他功能

## 7. 设置界面

- [ ] 7.1 在设置视图新增区块，放入 `KeyboardShortcuts.Recorder(for: .togglePinnedPanel)` 录制控件
- [ ] 7.2 （可选）加入「开机自动显示钉住面板」开关，绑定 `MonitorSettings`
- [ ] 7.3 校验录制新快捷键 / 清除快捷键后热键即时更新且重启后保持

## 8. 本地化

- [ ] 8.1 在 `Localizable.xcstrings` 补齐所有新增文案（设置项标题、说明、关闭按钮）的 `zh-Hans` 与 `en`
- [ ] 8.2 代码中统一用 `String(localized:)`，不硬编码中英文

## 9. 验证与回归

- [ ] 9.1 回归：菜单栏面板「点开即弹、失焦即收」行为不变
- [ ] 9.2 手测：快捷键呼出/关闭、拖动定位、始终最前、失焦不关、悬停关闭
- [ ] 9.3 手测：拖动后位置记忆、App 重启后恢复、拔屏后越界回收
- [ ] 9.4 手测：切换虚拟桌面时钉住面板不跟随（仅当前桌面）
- [ ] 9.5 运行 `xcodebuild test -scheme HagimiMonitorDirect -destination 'platform=macOS'` 全绿
- [ ] 9.6 两个 scheme（HagimiMonitor / HagimiMonitorDirect）均能 Debug 构建通过
