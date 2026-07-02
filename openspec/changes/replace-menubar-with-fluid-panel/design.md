## Context

HagimiMonitor 是 `LSUIElement` 菜单栏应用，面板通过 SwiftUI `MenuBarExtra(.window)` 承载 `MonitorPanelView`，`label` 为动态 `MenuBarStatusLabel`（负载环或可变宽指标文本）。

现状问题：展开 CPU/GPU 等子项时，面板整体闪烁、顶部 "SYSTEM · LIVE" 一起像被重新加载。经排查根因为 **`MenuBarExtra(.window)` 在 macOS 15（及更早）对宿主窗口 resize 的实现缺陷**：内容高度变化时系统整窗重绘；这与行级毛玻璃材质无关（已验证把行玻璃从 `.behindWindow` 改为 `.withinWindow` 后仍闪）。Apple 直到 macOS 26 才改进该行为。

已完成的前置工作（本仓库已合入 commit `980324c`）：行级效果统一为 `NSVisualEffectView` 毛玻璃，液态玻璃仅保留在底部按钮。本次改动聚焦承载层。

参考实现：`docs/FluidMenuBarExtra-main/`（第三方库 FluidMenuBarExtra，仅供借鉴；因其仅支持静态图标、维护度低，不作为依赖引入）。本 change 目录下附带一份草稿 `reference/FluidPanelController.draft.swift`（未接线、未纳入编译，且已知有一处 `@Environment(\.openSettings)` 用法编译错误待修），可作为实现起点参考，但需按本设计校对补全后再放入 `HagimiMonitor/` 编译目录。

约束：
- 必须同时支持 macOS 15 与 macOS 26+，且不破坏 26 现有体验。
- 不引入第三方依赖。
- 面板内容视图 `MonitorPanelView`、`MonitorStore`、`MenuBarStatusLabel` 尽量原样复用。
- 遵循项目本地化规范；本次不新增用户可见文案。

## Goals / Non-Goals

**Goals:**
- 在 macOS 15 上展开子项时不再闪烁，且高度变化平滑、顶边锚定。
- 恢复展开/折叠动画，且 15 与 26 行为一致（取消版本分叉）。
- 保留动态菜单栏图标（负载环 / 可变宽指标文本）。
- 复刻承载层必需交互：点击切换、外部点击/失焦关闭、全屏保持菜单栏、多屏与屏幕边缘定位。

**Non-Goals:**
- 重新设计面板布局或新增监控指标。
- 改变行级毛玻璃材质方案（已在前置 commit 完成）。
- 修复 macOS 27 测试版上的问题（本次不覆盖，后续单独处理）。
- 引入或封装通用的第三方菜单栏库。

## Decisions

### 1. 自建 NSPanel 承载面板，替换 MenuBarExtra
**决策：** 移除 `MenuBarExtra` Scene，新增 `FluidPanelController`（`@MainActor`），用 `NSPanel`（`styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .fullSizeContentView]`，`level = .statusBar`，透明背景、有阴影）承载 `NSHostingView(MonitorPanelView)`。

**理由：** 系统对 `MenuBarExtra(.window)` 的 resize 无法干预；自建窗口后可用 AppKit 原生 `setFrame(display:animate:)` 平滑 resize，不触发 SwiftUI 视图树 rebuild，从根上去闪。

**替代方案：**
- 直接依赖 FluidMenuBarExtra —— 否决：仅支持静态图标，无法显示动态负载环；仓库 star 少、维护度低。
- 固定窗口高度、内部裁剪展开 —— 否决：收起态底部大片空白，不适合菜单栏面板。

### 2. 动画由窗口层驱动，SwiftUI 侧不做几何动画
**决策：** 展开时 SwiftUI 内容**瞬时**切换到展开布局并上报新的 fitting size，由 `setFrame(animate: true)` 提供高度补间；`MonitorPanelView.setExpansion` 不再 `withAnimation`，`detailDisclosure` 不再按版本分叉。

**理由：** 上一轮「SwiftUI 几何动画 + 系统窗口 resize」互相抢锚点，导致顶部抖动。让窗口层独占高度动画，内容 top 对齐、随窗口下拉逐渐露出，观感即「平滑向下展开」。

**替代方案：** 逐帧上报中间尺寸并每帧 `animate:true` —— 否决：动画叠加打架，且逐帧 resize 在 15 上抖。

### 3. 顶边锚定算法
**决策：** 以状态项按钮所在窗口的 `frame.origin` 为基准，`origin.y -= newHeight`、`origin.x -= windowBorderSize(2pt)`；再对屏幕左右可见边缘做回收（超右缘左移、超左缘右移）。

**理由：** macOS 坐标原点在左下，`origin.y + height` 即顶边；减去高度可使顶边恒定钉在菜单栏下沿，面板只向下生长。此为 FluidMenuBarExtra 的核心技巧。

### 4. 动态图标承载
**决策：** `NSStatusItem.button` 内嵌 `NSHostingView(MenuBarStatusLabel)`，用 Auto Layout 居中并填满按钮高度；状态项 `variableLength`，宽度由 hosting 固有尺寸决定。主题/外观变化时替换 `rootView` 刷新。

**理由：** 指标模式是可变宽 SwiftUI 文本，渲染成静态 `NSImage` 麻烦且失去自适应；内嵌 hosting 可直接复用现有 `MenuBarStatusLabel` 两种模式。

**替代方案：** 每帧把 SwiftUI 渲染成 `NSImage` 赋给 `button.image` —— 否决：可变宽文本处理繁琐、易糊。

### 5. App 启动结构
**决策：** 用 `NSApplicationDelegateAdaptor` 引入 `AppDelegate`，在 `applicationDidFinishLaunching` 创建并持有 `FluidPanelController`（注入 `MonitorStore` 与打开设置的动作）。`App.body` 保留 `Settings` 与 `WindowGroup("Preview")`，移除 `MenuBarExtra`。

**理由：** 已是 `LSUIElement`，不会自动弹窗；AppDelegate 是持有 NSStatusItem 生命周期的标准位置。

**开放点：** `@Environment(\.openSettings)` 只能在 SwiftUI 视图层取得。方案：在一个轻量 SwiftUI 宿主里读取并回传给控制器，或改用 `SettingsWindowPresenter` 现有的打开设置路径（后者更简单，见 Open Questions）。

### 6. 交互与生命周期联动
**决策：**
- `LocalEventMonitor([.leftMouseDown])`：命中状态项按钮 → `togglePanel()`，返回 `nil` 吞掉事件。
- `GlobalEventMonitor([.leftMouseDown, .rightMouseDown])` + `windowDidResignKey` → `dismissPanel()`（0.18s 淡出）。
- 显示时 `panelDidAppear()`，隐藏完成后 `panelDidDisappear()`，保持进程采样按需启停。
- 显隐各 post `beginMenuTracking` / `endMenuTracking`，全屏下保持菜单栏。

## Risks / Trade-offs

- **NSPanel 圆角/阴影与系统菜单不完全一致** → 借鉴 FluidMenuBarExtra 的窗口参数并微调 `cornerRadius`/阴影；接受轻微差异（库本身也有此权衡）。
- **失焦关闭与打开设置窗口冲突**（点设置按钮会让面板失焦 → 关闭属预期，但需保证设置窗口正常前置）→ 在打开设置的动作里先关闭面板再前置设置窗口，回归验证。
- **多屏 / 不同菜单栏高度 / 刘海屏定位偏移** → 用状态项按钮窗口的 `screen.visibleFrame` 计算并回收边缘；在多屏与刘海机型上回归。
- **`NSHostingView.sizingOptions=[]` 与 fitting size 时序** → 首次显示前 `layoutSubtreeIfNeeded()` 再取 `fittingSize`，避免首帧尺寸跳变。
- **窗口透明 + NSVisualEffectView 背景协同**（现有 `TransparentWindowBackground` 依赖 SwiftUI 窗口层级）→ 自建窗口后需确认透明与毛玻璃仍生效，必要时把透明处理移入 `NSPanel` 配置。
- **macOS 26 体验回归**（26 原本正常）→ 26 也走自建窗口，需专门验证展开动画与视觉不劣于现状。
- **无法本地验证 macOS 15**（开发机非 15）→ 依赖 15 真机回归；tasks 中列出明确验证清单。

## Migration Plan

1. 新增 `FluidPanelController` 及配套（尺寸读取修饰符、事件监听），先不接线，保证可编译。
2. 新增 `AppDelegate`，在 `HagimiMonitorApp` 接入 `NSApplicationDelegateAdaptor`，移除 `MenuBarExtra`。
3. 简化 `MonitorPanelView` 的 `setExpansion` / `detailDisclosure`（去版本分叉，恢复统一动画）。
4. macOS 26 构建运行自测：显隐、切换、外部关闭、展开动画、设置窗口、Preview。
5. macOS 15 真机回归：重点确认展开不闪、顶边锚定、动画平滑、图标两种模式、全屏/多屏。
6. 回归通过后归档 change。

**回滚策略：** 改动集中在承载层与 App 入口；如需回滚，恢复 `MenuBarExtra` Scene 并移除 `FluidPanelController` 接线即可，面板内容视图不受影响。

## Open Questions

- 打开设置的入口：复用 `SettingsWindowPresenter.open(...)` 是否足够，还是必须经由 `@Environment(\.openSettings)`？（倾向前者，省去环境注入。）
- 面板圆角与阴影的目标值：是否需要与 macOS 26 系统菜单严格一致，还是接受 Fluid 风格的略宽圆角？
- `TransparentWindowBackground` 在自建 `NSPanel` 下是否仍需要，或可由 `NSPanel` 的透明配置直接替代。
