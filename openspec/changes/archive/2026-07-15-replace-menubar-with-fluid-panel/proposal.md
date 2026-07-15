## Why

面板在展开 CPU/GPU 等子项时，最外层容器会闪烁、连同顶部 "SYSTEM · LIVE" 一起像被重新加载，动画鬼畜。根因是 SwiftUI 的 `MenuBarExtra(.window)` 在 macOS 15（及更早）对宿主窗口的 resize 实现很差：内容高度变化时系统会整窗重绘，Apple 直到 macOS 26 才改进。上一轮修复误判为「动画不平滑」，在 15 上砍掉了展开动画，结果既没动画又依旧闪。要在 macOS 15 上同时拿到「不闪」和「平滑展开」，必须绕开系统对该窗口的托管，自建 `NSWindow` 承载面板并自行驱动 resize 动画。

## What Changes

- **BREAKING**（内部架构）：移除 `HagimiMonitorApp` 中的 `MenuBarExtra` Scene，改为通过 `NSApplicationDelegateAdaptor` 在启动时创建自建的菜单栏面板控制器 `FluidPanelController`。
- 新增 `FluidPanelController`：借鉴 FluidMenuBarExtra 思路，自建 `NSPanel` 承载现有 `MonitorPanelView`，用 `NSStatusItem` + 内嵌 `NSHostingView` 承载动态 `MenuBarStatusLabel`（负载环 / 可变宽指标文本均正常显示）。
- 面板高度动画改由窗口层 `setFrame(display:animate:)` 驱动，顶边锚定在菜单栏下沿只向下生长；SwiftUI 侧内容尺寸瞬时上报、不做几何动画，从根上消除闪烁与顶部抖动。
- 恢复展开/折叠动画：因 window 层已提供平滑高度补间，`MonitorPanelView` 不再需要按 `macOS 26` 与 `15` 分叉禁用动画，两版本行为统一。
- 复刻承载层必需的交互：左键点击状态项切换面板、点击外部/失焦自动关闭、全屏下保持菜单栏、多屏与屏幕右缘回收定位、面板显隐时联动 `panelDidAppear/panelDidDisappear`。
- 不引入第三方依赖（FluidMenuBarExtra 仅支持静态图标且维护度低），仅借鉴其实现思路自研。

## Capabilities

### New Capabilities
- `fluid-menu-bar-panel`: 自建 `NSPanel` + `NSStatusItem` 的菜单栏面板承载层，替代系统 `MenuBarExtra(.window)`，负责面板显隐、顶边锚定的平滑 resize、动态图标承载与交互（外部点击关闭、全屏保持、多屏定位）。

### Modified Capabilities
- `panel-animation-consistency`: 取消「macOS 15 使用 identity 过渡 / 不做几何补间」的版本分叉要求；展开高度动画统一改由窗口层驱动，两版本一致平滑。
- `menu-bar`: 菜单栏图标不再由 `MenuBarExtra` 的 `label` 承载，改为 `NSStatusItem.button` 内嵌 `NSHostingView`；需保持图标稳定可见、且承载方式不导致进程异常退出。

## Impact

- **代码**：`HagimiMonitorApp.swift`（移除 MenuBarExtra、接入 AppDelegate）、新增 `FluidPanelController.swift` 及配套（尺寸读取、事件监听）、`MonitorPanelView.swift`（恢复统一展开动画、清理版本分叉的 `detailDisclosure` / `setExpansion`）。
- **承载层行为**：面板改由自建 `NSPanel` 显示，圆角/阴影/定位由代码控制，需在 macOS 15 与 26 双平台回归验证。
- **依赖**：无新增第三方依赖；`docs/FluidMenuBarExtra-main/` 仅作参考。
- **风险面**：App 激活策略（已是 `LSUIElement`）、Settings 窗口与 Preview `WindowGroup` 的协同、失焦关闭与设置窗口打开的交互、多屏 / 全屏 / Spaces 边角。
