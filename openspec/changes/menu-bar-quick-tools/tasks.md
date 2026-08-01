# Tasks: Menu Bar Quick Tools

> 状态：全部未开始（本 change 暂缓实现）。落地时按序推进，先攻 Risks 里的 NSPopover×NSPanel 焦点问题。

## 0. 前置验证（头号风险）
- [ ] 验证 NSPopover 从非激活 `NSPanel` 弹出时不会触发宿主面板的 `windowDidResignKey` 收起
- [ ] 确定 popover.behavior（`.transient` vs `.applicationDefined`）与面板关闭逻辑的协调方案
- [ ] 验证 `preferredEdge: .maxY` 在面板贴屏幕底时自动翻侧边，箭头正确重指

## 1. 防休眠（双版本）
- [ ] `HagimiMonitor/Tools/KeepAwakeController.swift`：IOPMAssertionCreateWithName 封装，幂等 activate/deactivate，deinit 释放
- [ ] 激活态不持久化（不写 UserDefaults）

## 2. 键盘锁定（仅 Direct）
- [ ] `HagimiMonitorDirectOnly/KeyboardLockController.swift`：CGEventTap 吞 keyDown/keyUp/flagsChanged
- [ ] 只锁键盘、不锁鼠标；tapDisabled 自动重启用
- [ ] 20 分钟自动解锁计时 + onAutoUnlock 回调
- [ ] 复用 `AccessibilityPermissionService` 做授权门控

## 3. 状态层
- [ ] `HagimiMonitor/Tools/ToolsState.swift`：`@MainActor ObservableObject` + `static shared`
- [ ] `keepAwakeActive`（双版本）/ `keyboardLocked`（`#if DIRECT_DISTRIBUTION`）
- [ ] `anyToolActive` 计算属性；键盘锁 toggle 未授权时触发 `permission.request()`

## 4. 浮层 UI
- [ ] `HagimiMonitor/Tools/ToolsPopoverView.swift`：点亮式 toggle 磁贴列表
- [ ] 激活态整块染色发光 + 圆标满色 + 状态副文案；原生 `Toggle(.switch)` 或整块可点
- [ ] 键盘锁未授权态副文案「需辅助功能权限」；沙盒版仅防休眠一张磁贴
- [ ] 深/浅色两套，对齐 MonitorPalette

## 5. 面板集成
- [ ] `MonitorPanelView.swift` 底部操作区新增「工具」按钮（图标 + 激活角标）
- [ ] `FluidPanelController` / `PinnedPanelController` 持有 NSPopover，点击按钮 `show(relativeTo:of:preferredEdge:.maxY)`
- [ ] popover.contentViewController = `NSHostingController(rootView: ToolsPopoverView(tools: .shared))`
- [ ] 面板收起时同步关闭 popover

## 6. 本地化
- [ ] `Localizable.xcstrings` 新增 `tools.*` 键（zh-Hans / en / ja）：工具名、状态文案、未授权提示

## 7. 验证
- [ ] 双 scheme（HagimiMonitor 沙盒 / HagimiMonitorDirect）均编译通过
- [ ] 沙盒版：浮层只有防休眠，无键盘锁；防休眠断言经 `pmset -g assertions` 可见
- [ ] Direct 版：键盘锁首次点击弹授权，授权后生效；只锁键盘不锁鼠标；自动解锁生效
- [ ] 面板贴屏幕底时 popover 自动侧边弹出
- [ ] 激活工具后收起浮层，「工具」按钮角标出现
