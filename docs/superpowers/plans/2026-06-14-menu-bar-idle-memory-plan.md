# 菜单栏驻留态内存优化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **⚠️ 用户硬约束:绝对不允许 git commit / git push / 创建 PR。** 每个 Task 末尾不再有 commit 步骤,改为"停下等用户亲自审 diff"。用户审完决定是否要 commit、由谁来 commit。

**Goal:** 把 MenuBarExtra 驻留态(面板未打开)的常驻内存从 ~150MB RSS / ~133MB physical footprint 压到 ≤ 80MB,通过砍掉 125ms 周期的菜单栏图标重生 + core pulse 动画 + load 量化 + NSImage 缓存。

**Architecture:** 删除 `MonitorStore` 中 125ms 的 `animationTimer` 与 `@Published var menuBarFrame`;`displayedComputeLoad` 的平滑过渡改由"按需启动 / 稳定自停"的 500ms timer 推进(stable idle = 0 timer)。`MenuBarComputeRingIcon.image(...)` 去 `frame` 参数与 core 呼吸,加 `NSCache` 缓存(key = 量化 load × darkMode × loadLevel)。外圈 ring 视觉不变。

**Tech Stack:** Swift / SwiftUI / AppKit / Combine / NSCache,macOS 26+ Apple Silicon。Xcode `HagimiMonitorDirect` scheme(`DIRECT_DISTRIBUTION`、`DISPLAY_CONTROL`)用于本地开发与验证。

---

## 文件结构

| 文件 | 责任 | 改动 |
| --- | --- | --- |
| `HagimiMonitor/MenuBarComputeRingIcon.swift` | 菜单栏 18×18 ring 图标绘制与缓存 | 修改 |
| `HagimiMonitor/MonitorModels.swift` | `MonitorStore` 状态机与采样调度 | 修改 |
| `HagimiMonitor/HagimiMonitorApp.swift` | App 入口与 `MenuBarExtra` label | 修改 |
| `HagimiMonitor/Constants.swift` | 全局常量 | 修改(仅删除) |
| `HagimiMonitor/MonitorPanelView.swift` | 面板视图(顺手项:DateFormatter) | 修改 |
| `HagimiMonitorTests/MenuBarComputeRingIconCacheTests.swift` | Icon 缓存单元测试 | 新建 |

---

## Task 编排原则

- 每步保证 build 通过(`xcodebuild -scheme HagimiMonitorDirect`)。
- Icon 新签名引入用 `frame: Int = 0` 默认值过渡,最后 Task 删默认值与旧逻辑。
- `ComputeLoadModel.smoothedDisplayValue` / `shouldUpdateMenuBarTarget` 静态方法**保留**(被现有测试 `HagimiMonitorTests.swift:72-80` 引用),仅业务代码不再调用。
- 每个 Task 末尾 **不 commit**,改为输出 `git diff --stat` 给用户审。

---

## Task 1: Icon 引入新签名 overload(过渡)

**目标:** 让调用方能传 `frame=0`,为后续删 `frame` 参数铺路;此时 core pulse 仍存在,行为不变。

**Files:**
- Modify: `HagimiMonitor/MenuBarComputeRingIcon.swift:5`(给 `image` 加 `frame: Int = 0` 默认值)
- Modify: `HagimiMonitor/HagimiMonitorApp.swift:26-31`(调用方不再读 `monitorStore.menuBarFrame`)

- [ ] **Step 1.1: 给 `MenuBarComputeRingIcon.image` 的 `frame` 参数加默认值**

文件 `HagimiMonitor/MenuBarComputeRingIcon.swift` line 5,旧:

```swift
static func image(load: Double, frame: Int, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSImage {
```

改为:

```swift
static func image(load: Double, frame: Int = 0, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSImage {
```

- [ ] **Step 1.2: `HagimiMonitorApp` 调用方去掉 `frame:` 实参**

文件 `HagimiMonitor/HagimiMonitorApp.swift:26-31`,旧:

```swift
Image(nsImage: MenuBarComputeRingIcon.image(
    load: monitorStore.displayedComputeLoad,
    frame: monitorStore.menuBarFrame,
    darkMode: NSApp.effectiveAppearance.isDark,
    loadLevel: monitorStore.haloRingLoadLevel
))
```

改为:

```swift
Image(nsImage: MenuBarComputeRingIcon.image(
    load: monitorStore.displayedComputeLoad,
    darkMode: NSApp.effectiveAppearance.isDark,
    loadLevel: monitorStore.haloRingLoadLevel
))
```

- [ ] **Step 1.3: Build 验证**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Expected: BUILD SUCCEEDED。视觉与改动前完全一致(`frame=0` 时 `linearPulse` 也是 0,只影响 core 透明度的极小项 `0.03`)。

- [ ] **Step 1.4: 停下等用户审**

Run:
```bash
git diff --stat
git diff HagimiMonitor/MenuBarComputeRingIcon.swift HagimiMonitor/HagimiMonitorApp.swift
```

输出给用户。**不要 commit。** 等用户说继续再进入 Task 2。

---

## Task 2: `MonitorStore` 砍 animationTimer + menuBarFrame + 引入按需 smoothing timer

**目标:** 删除 125ms 永不停的 animationTimer,改为只有 `|target - displayed| > threshold` 时才启动的 500ms timer,稳定后自停。`displayedComputeLoad` 写入前做 2% 量化。

**Files:**
- Modify: `HagimiMonitor/MonitorModels.swift:200-244`(`MonitorStore` 字段与 init)
- Modify: `HagimiMonitor/MonitorModels.swift:246-250`(deinit)
- Modify: `HagimiMonitor/MonitorModels.swift:293-369`(`advance` / `advanceAnimation` / `updateMenuBarTargetComputeLoadIfNeeded`)

- [ ] **Step 2.1: 删除 `menuBarFrame` 字段与 `animationTimerCancellable` 字段**

文件 `HagimiMonitor/MonitorModels.swift`,在 `MonitorStore` 类内,删除:

```swift
@Published private(set) var menuBarFrame = 0
```

```swift
private var animationTimerCancellable: AnyCancellable?
```

```swift
private var framesSinceLastMenuBarTargetUpdate = MonitorConstants.menuBarLoadUpdateFrameInterval
```

新增字段(放在原 `animationTimerCancellable` 位置附近):

```swift
private var smoothingTimerCancellable: AnyCancellable?
private var menuBarTargetComputeLoad: Double = 0
```

注意:`menuBarTargetComputeLoad` 原本就存在(line 212),保留即可,不要重复声明。如果原位置 `private var menuBarTargetComputeLoad = 0.0` 已存在,跳过这次新增。

- [ ] **Step 2.2: 删除 init 中 animationTimer 的订阅块**

文件 `HagimiMonitor/MonitorModels.swift:239-243`,删除整块:

```swift
animationTimerCancellable = Timer.publish(every: MonitorConstants.animationInterval, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        self?.advanceAnimation()
    }
```

- [ ] **Step 2.3: 删除 deinit 中 animationTimer cancel**

文件 `HagimiMonitor/MonitorModels.swift:248`,删除:

```swift
animationTimerCancellable?.cancel()
```

新增(在同位置,deinit 末尾):

```swift
smoothingTimerCancellable?.cancel()
```

- [ ] **Step 2.4: 重写 `advanceAnimation` 为新的 smoothing 推进逻辑**

文件 `HagimiMonitor/MonitorModels.swift:344-351`,旧:

```swift
private func advanceAnimation() {
    menuBarFrame = (menuBarFrame + 1) % 48
    updateMenuBarTargetComputeLoadIfNeeded()
    displayedComputeLoad = ComputeLoadModel.smoothedDisplayValue(
        current: displayedComputeLoad,
        target: menuBarTargetComputeLoad
    )
}
```

替换为:

```swift
private func advanceSmoothing() {
    let next = ComputeLoadModel.smoothedDisplayValue(
        current: displayedComputeLoad,
        target: menuBarTargetComputeLoad
    )
    let quantized = MonitorStore.quantizeLoad(next)
    if quantized != displayedComputeLoad {
        displayedComputeLoad = quantized
    }
    if !ComputeLoadModel.shouldUpdateMenuBarTarget(
        currentTarget: displayedComputeLoad,
        nextTarget: menuBarTargetComputeLoad
    ) {
        smoothingTimerCancellable?.cancel()
        smoothingTimerCancellable = nil
    }
}

private static func quantizeLoad(_ load: Double) -> Double {
    let clamped = min(100.0, max(0.0, load))
    return (clamped / 2.0).rounded() * 2.0
}

private func ensureSmoothingTimer() {
    guard smoothingTimerCancellable == nil else { return }
    smoothingTimerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            self?.advanceSmoothing()
        }
}
```

注意:`shouldUpdateMenuBarTarget` 的语义是"当 |a - b| ≥ menuBarLoadChangeThreshold (5.0) 时返回 true",这里复用为"是否还需要继续推进";阈值复用 5.0 表示 displayed 离 target 已经足够近时停 timer。

- [ ] **Step 2.5: 改写 `updateMenuBarTargetComputeLoadIfNeeded` 与 `advance` 调用关系**

文件 `HagimiMonitor/MonitorModels.swift:353-369`,旧:

```swift
private func updateMenuBarTargetComputeLoadIfNeeded() {
    framesSinceLastMenuBarTargetUpdate += 1
    guard framesSinceLastMenuBarTargetUpdate >= MonitorConstants.menuBarLoadUpdateFrameInterval else {
        return
    }

    framesSinceLastMenuBarTargetUpdate = 0
    let currentLoad = combinedComputeLoad
    guard ComputeLoadModel.shouldUpdateMenuBarTarget(
        currentTarget: menuBarTargetComputeLoad,
        nextTarget: currentLoad
    ) else {
        return
    }

    menuBarTargetComputeLoad = currentLoad
}
```

替换为:

```swift
private func updateMenuBarTargetComputeLoad() {
    let currentLoad = combinedComputeLoad
    guard ComputeLoadModel.shouldUpdateMenuBarTarget(
        currentTarget: menuBarTargetComputeLoad,
        nextTarget: currentLoad
    ) else {
        return
    }
    menuBarTargetComputeLoad = currentLoad
    ensureSmoothingTimer()
}
```

然后在 `advance()` 函数尾部(`MonitorModels.swift:293` 起),在采样完成、`modules` 已更新之后,加一行:

```swift
updateMenuBarTargetComputeLoad()
```

具体插入点:`advance()` 体内最后一行之前(以 plan 执行时实际代码结构为准 — 找到 `runSampling(kinds:)` 调用之后、函数 return 前的位置)。如果 `advance()` 体本身是异步派发,把这行放在异步回调里更新 `allModules` 之后。

- [ ] **Step 2.6: Build 验证**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Expected: BUILD SUCCEEDED。如果有 "framesSinceLastMenuBarTargetUpdate" 仍被引用的报错,说明删除不彻底,grep 一下:

```bash
grep -n "framesSinceLastMenuBarTargetUpdate\|menuBarFrame\|animationTimerCancellable\|advanceAnimation\b" HagimiMonitor/MonitorModels.swift
```

应该返回空。

- [ ] **Step 2.7: 跑现有测试**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test
```

Expected: 所有现有测试通过(`HagimiMonitorTests.swift` 里那几个 `ComputeLoadModel.*` 的 `#expect` 不受影响,因为静态方法保留)。

- [ ] **Step 2.8: 停下等用户审**

Run:
```bash
git diff HagimiMonitor/MonitorModels.swift
```

输出给用户。**不要 commit。**

---

## Task 3: Icon 删 frame 参数与 core pulse

**目标:** 此时已无调用方传 `frame`,删除参数与 `linearPulse` 计算。

**Files:**
- Modify: `HagimiMonitor/MenuBarComputeRingIcon.swift`(line 5、13、81-95、109-112)

- [ ] **Step 3.1: 删除 `image` 函数 `frame` 参数**

文件 `HagimiMonitor/MenuBarComputeRingIcon.swift:5`(经 Task 1 修改后是 `frame: Int = 0`),改为:

```swift
static func image(load: Double, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSImage {
```

- [ ] **Step 3.2: 删除 `MenuBarComputeRingImageStyle` 构造时的 frame 字段**

文件 `HagimiMonitor/MenuBarComputeRingIcon.swift:13`,旧:

```swift
let style = MenuBarComputeRingImageStyle(load: load, frame: frame, darkMode: darkMode, loadLevel: loadLevel)
```

改为:

```swift
let style = MenuBarComputeRingImageStyle(load: load, darkMode: darkMode, loadLevel: loadLevel)
```

- [ ] **Step 3.3: 改 `MenuBarComputeRingImageStyle` struct 定义**

文件 `HagimiMonitor/MenuBarComputeRingIcon.swift:81-95`,旧:

```swift
private struct MenuBarComputeRingImageStyle {
    let load: Double
    let frame: Int
    let darkMode: Bool
    let loadLevel: MenuBarComputeLoadLevel

    private var normalizedLoad: Double {
        min(1, max(0, load / 100))
    }

    private var linearPulse: Double {
        let phase = Double(frame % 48) / 48
        return phase < 0.5 ? phase * 2 : (1 - phase) * 2
    }
```

改为:

```swift
private struct MenuBarComputeRingImageStyle {
    let load: Double
    let darkMode: Bool
    let loadLevel: MenuBarComputeLoadLevel

    private var normalizedLoad: Double {
        min(1, max(0, load / 100))
    }
```

(删 `let frame: Int` 与整个 `linearPulse` 计算属性)

- [ ] **Step 3.4: 改 `coreColor` 去掉 linearPulse 项**

文件 `HagimiMonitor/MenuBarComputeRingIcon.swift:109-112`,旧:

```swift
var coreColor: NSColor {
    loadLevel.coreColor(darkMode: darkMode)
        .withAlphaComponent((darkMode ? 0.76 : 0.88) + normalizedLoad * 0.10 + linearPulse * 0.03)
}
```

改为:

```swift
var coreColor: NSColor {
    loadLevel.coreColor(darkMode: darkMode)
        .withAlphaComponent((darkMode ? 0.76 : 0.88) + normalizedLoad * 0.10)
}
```

- [ ] **Step 3.5: Build 验证**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Expected: BUILD SUCCEEDED。视觉:core 不再呼吸,但颜色与改动前 idle 静止时一致。

- [ ] **Step 3.6: 停下等用户审**

Run:
```bash
git diff HagimiMonitor/MenuBarComputeRingIcon.swift
```

输出给用户。**不要 commit。**

---

## Task 4: Icon 加 NSCache

**目标:** 同 (load_bucket, darkMode, loadLevel) 的 NSImage 复用,不重新 lockFocus 绘制。

**Files:**
- Modify: `HagimiMonitor/MenuBarComputeRingIcon.swift`(在 `image` 静态方法上层加 cache)

- [ ] **Step 4.1: 给 `MenuBarComputeLoadLevel` 加 cacheIndex**

文件 `HagimiMonitor/MenuBarComputeRingIcon.swift:149-175`,在 `enum MenuBarComputeLoadLevel` 内 `coreColor(darkMode:)` 函数之前加:

```swift
var cacheIndex: Int {
    switch self {
    case .idle: return 0
    case .working: return 1
    case .busy: return 2
    case .stressed: return 3
    }
}
```

- [ ] **Step 4.2: 在 `MenuBarComputeRingIcon` enum 顶部加静态 cache**

文件 `HagimiMonitor/MenuBarComputeRingIcon.swift:4-5`(`enum MenuBarComputeRingIcon {` 之后),插入:

```swift
private static let cache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 120
    return cache
}()

private static func cacheKey(load: Double, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSString {
    let bucket = Int((min(100.0, max(0.0, load)) / 2.0).rounded())
    return "\(bucket)|\(darkMode ? 1 : 0)|\(loadLevel.cacheIndex)" as NSString
}
```

- [ ] **Step 4.3: 改写 `image` 函数走缓存**

把整个 `image(...)` 函数体改为:

```swift
static func image(load: Double, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSImage {
    let key = cacheKey(load: load, darkMode: darkMode, loadLevel: loadLevel)
    if let cached = cache.object(forKey: key) {
        return cached
    }

    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 18, height: 18).fill()

    let style = MenuBarComputeRingImageStyle(load: load, darkMode: darkMode, loadLevel: loadLevel)
    drawRing(style: style)

    image.unlockFocus()
    image.isTemplate = false

    cache.setObject(image, forKey: key)
    return image
}
```

- [ ] **Step 4.4: Build 验证**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 4.5: 停下等用户审**

Run:
```bash
git diff HagimiMonitor/MenuBarComputeRingIcon.swift
```

输出给用户。**不要 commit。**

---

## Task 5: Constants 清理

**目标:** 删除已无引用的常量,保留仍被 `ComputeLoadModel` 静态方法引用的(`menuBarLoadChangeThreshold`、`menuBarLoadSmoothStep`)。

**Files:**
- Modify: `HagimiMonitor/Constants.swift:12-16`

- [ ] **Step 5.1: grep 确认每个常量的引用**

Run:
```bash
grep -rn "MonitorConstants.animationInterval\|MonitorConstants.menuBarLoadUpdateInterval\|MonitorConstants.menuBarLoadUpdateFrameInterval" HagimiMonitor/ HagimiMonitorTests/
```

Expected: 应返回空(Task 2 已删完业务调用)。如果还有,先回 Task 2 删干净。

Run:
```bash
grep -rn "MonitorConstants.menuBarLoadChangeThreshold\|MonitorConstants.menuBarLoadSmoothStep" HagimiMonitor/ HagimiMonitorTests/
```

Expected: 在 `MonitorModels.swift` 的 `ComputeLoadModel` 内有引用 — 这两个**保留**。

- [ ] **Step 5.2: 删 `Constants.swift` 中无引用常量**

文件 `HagimiMonitor/Constants.swift:11-16`,旧:

```swift
    // MARK: Animation
    static let animationInterval = 0.125
    static let menuBarLoadUpdateInterval: TimeInterval = 3
    static let menuBarLoadUpdateFrameInterval = 24
    static let menuBarLoadChangeThreshold = 5.0
    static let menuBarLoadSmoothStep = 1.25
```

改为:

```swift
    // MARK: Animation
    static let menuBarLoadChangeThreshold = 5.0
    static let menuBarLoadSmoothStep = 1.25
```

- [ ] **Step 5.3: Build 验证**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 5.4: 停下等用户审**

Run:
```bash
git diff HagimiMonitor/Constants.swift
```

输出给用户。**不要 commit。**

---

## Task 6: `MonitorPanelView.timeString` DateFormatter 静态化

**目标:** 顺手项,与驻留态无关,但成本极低。

**Files:**
- Modify: `HagimiMonitor/MonitorPanelView.swift:1-4`(文件顶部加 private let)
- Modify: `HagimiMonitor/MonitorPanelView.swift:188-192`(`timeString`)

- [ ] **Step 6.1: 在文件顶部 import 之后加文件级 DateFormatter**

文件 `HagimiMonitor/MonitorPanelView.swift`,在 `import Charts`(line 3)之后插入:

```swift

private let panelTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()
```

- [ ] **Step 6.2: 改写 `timeString` 计算属性**

文件 `HagimiMonitor/MonitorPanelView.swift:188-192`,旧:

```swift
private var timeString: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: Date())
}
```

改为:

```swift
private var timeString: String {
    panelTimeFormatter.string(from: Date())
}
```

- [ ] **Step 6.3: Build 验证**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 6.4: 停下等用户审**

Run:
```bash
git diff HagimiMonitor/MonitorPanelView.swift
```

输出给用户。**不要 commit。**

---

## Task 7: `selectedKind` 降级(可选)

**目标:** `@Published var selectedKind` 无外部 SwiftUI 观察者,降级为非 Published 减少 SwiftUI invalidation 噪声。

**Files:**
- Modify: `HagimiMonitor/MonitorModels.swift:201`

- [ ] **Step 7.1: 再次确认无外部订阅**

Run:
```bash
grep -rn "selectedKind\|selectedModule" HagimiMonitor/ HagimiMonitorTests/ HagimiMonitorUITests/
```

Expected: 仅 `MonitorModels.swift` 内部引用(`selectedKind` 字段声明 + `selectedModule` getter 内的两处)。如果发现任何 View 文件读取了 `selectedKind` 或 `selectedModule`,**跳过本任务**(说明有 SwiftUI 依赖)。

- [ ] **Step 7.2: 降级声明**

文件 `HagimiMonitor/MonitorModels.swift:201`,旧:

```swift
@Published var selectedKind: MonitorKind = .cpu
```

改为:

```swift
var selectedKind: MonitorKind = .cpu
```

- [ ] **Step 7.3: Build 验证**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

Expected: BUILD SUCCEEDED。如果出现 "@ObservedObject does not have $selectedKind" 之类报错,回滚到 `@Published`。

- [ ] **Step 7.4: 停下等用户审**

Run:
```bash
git diff HagimiMonitor/MonitorModels.swift
```

输出给用户。**不要 commit。**

---

## Task 8: 新增 Icon 缓存单元测试

**目标:** 验证缓存命中、量化分桶、容量上限。

**Files:**
- Create: `HagimiMonitorTests/MenuBarComputeRingIconCacheTests.swift`

- [ ] **Step 8.1: 写测试文件**

新建 `HagimiMonitorTests/MenuBarComputeRingIconCacheTests.swift`:

```swift
import Testing
import AppKit
@testable import HagimiMonitor

@Suite("MenuBarComputeRingIcon cache")
struct MenuBarComputeRingIconCacheTests {

    @Test("Same parameters return identical NSImage instance")
    func sameParametersHitCache() {
        let a = MenuBarComputeRingIcon.image(load: 50, darkMode: true, loadLevel: .working)
        let b = MenuBarComputeRingIcon.image(load: 50, darkMode: true, loadLevel: .working)
        #expect(a === b)
    }

    @Test("Loads inside same 2% bucket hit same cache entry")
    func quantizedBucketCollapsesNeighbors() {
        // bucket = round(load / 2). 50.0 -> 25, 50.9 -> 25, 51.0 -> 26 (boundary).
        let a = MenuBarComputeRingIcon.image(load: 50.0, darkMode: false, loadLevel: .idle)
        let b = MenuBarComputeRingIcon.image(load: 50.9, darkMode: false, loadLevel: .idle)
        #expect(a === b)
    }

    @Test("Loads in different buckets get different NSImages")
    func differentBucketsMiss() {
        let a = MenuBarComputeRingIcon.image(load: 10, darkMode: false, loadLevel: .idle)
        let b = MenuBarComputeRingIcon.image(load: 90, darkMode: false, loadLevel: .idle)
        #expect(a !== b)
    }

    @Test("darkMode dimension is part of cache key")
    func darkModeIsKeyed() {
        let a = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .working)
        let b = MenuBarComputeRingIcon.image(load: 30, darkMode: false, loadLevel: .working)
        #expect(a !== b)
    }

    @Test("loadLevel dimension is part of cache key")
    func loadLevelIsKeyed() {
        let a = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .idle)
        let b = MenuBarComputeRingIcon.image(load: 30, darkMode: true, loadLevel: .stressed)
        #expect(a !== b)
    }

    @Test("Out-of-range loads are clamped to valid buckets")
    func clampingBehavior() {
        let negative = MenuBarComputeRingIcon.image(load: -10, darkMode: false, loadLevel: .idle)
        let zero = MenuBarComputeRingIcon.image(load: 0, darkMode: false, loadLevel: .idle)
        let over = MenuBarComputeRingIcon.image(load: 200, darkMode: false, loadLevel: .idle)
        let hundred = MenuBarComputeRingIcon.image(load: 100, darkMode: false, loadLevel: .idle)
        #expect(negative === zero)
        #expect(over === hundred)
    }
}
```

注意:`@testable import HagimiMonitor` 需要 `MenuBarComputeRingIcon` 至少 internal 可见性(它是 `enum`,默认 internal,OK)。如果 cache 是 `private static`,通过黑盒"参数 → 返回 NSImage 引用"验证就足够,不需要直接访问 cache。

- [ ] **Step 8.2: 加入到 Xcode test target**

Xcode 项目通常自动加入(`HagimiMonitorTests/` 目录下的 `.swift` 文件按规则自动属于 test target)。如果 `xcodebuild test` 不识别新文件,在 Xcode 里手动 add to target `HagimiMonitorTests`。

- [ ] **Step 8.3: 跑测试**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test 2>&1 | grep -E "(Test Suite|Test Case|passed|failed|MenuBarComputeRingIcon)"
```

Expected: `MenuBarComputeRingIconCacheTests` 6 个测试全部通过。

- [ ] **Step 8.4: 停下等用户审**

Run:
```bash
git status
git diff HagimiMonitorTests/
```

输出给用户。**不要 commit。**

---

## Task 9: 验证 checklist(手测)

**目标:** spec 定义的验收指标。

- [ ] **Step 9.1: 干净启动 build**

Run:
```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug clean build
```

Expected: BUILD SUCCEEDED, 0 warning(若有 warning 记录下)。

- [ ] **Step 9.2: 启动 App,关闭面板,驻留 5 分钟**

Run:
```bash
./launch.sh
```

或 Xcode Cmd+R(scheme = HagimiMonitorDirect)。启动后**不要打开面板**,任凭它在菜单栏待 5 分钟。

- [ ] **Step 9.3: Activity Monitor 看 RSS / physical footprint**

打开 Activity Monitor,搜 `HagimiMonitor` 进程,看:
- Real Memory (RSS)
- 在 View → All Processes 里能看到 Memory 列

或命令行:

```bash
ps -o rss= -p $(pgrep HagimiMonitor) | awk '{ print $1/1024 " MB RSS" }'
```

如要更精确的 physical footprint:

```bash
vmmap --summary $(pgrep HagimiMonitor) | head -30
```

期望:`PHYSICAL FOOTPRINT` ≤ 80MB。**记录实际数字**,与改动前 133MB 对比。

- [ ] **Step 9.4: vmmap 看 graphics 段**

Run:
```bash
vmmap $(pgrep HagimiMonitor) | grep -E "(unmapped|IOSurface|CoreAnimation|IOAccelerator|MALLOC)"
```

期望:`owned unmapped (graphics)` 显著低于 57MB(基线)。

- [ ] **Step 9.5: 视觉验证 ring 平滑过渡**

打开一个吃 CPU 的 task(例如 `yes > /dev/null` 跑 N 个、或 Activity Monitor 自带的高占用进程模拟),观察菜单栏 ring 外圈进度弧:
- CPU 从 ~5% 涨到 60%+ 时,弧长应**平滑增长**(0.5s 间隔的 step)。
- 中间 core 不再呼吸(静止)。
- 颜色随 loadLevel 变化(idle 绿、working 青绿、busy 橙、stressed 红)。

- [ ] **Step 9.6: 暗 / 亮模式切换**

系统设置 → 外观切换 → 观察菜单栏图标颜色立即更新或在下一次采样 tick(≤1s)更新。记录实际行为。

- [ ] **Step 9.7: 反复打开关闭面板 10 次,看 RSS 回落**

每次开关后等 5s,记录 RSS:

```bash
ps -o rss= -p $(pgrep HagimiMonitor) | awk '{ print $1/1024 " MB" }'
```

期望:RSS 应回落到接近驻留基线,而非阶梯式增长。

- [ ] **Step 9.8: CPU sample 检查**

启动 5 分钟后 sample 一次,看 `MenuBarComputeRingIcon.image` 是否还在热点列表:

```bash
sample $(pgrep HagimiMonitor) 5 -file /tmp/hagimi.sample
grep -E "MenuBarComputeRingIcon|advanceAnimation|advanceSmoothing" /tmp/hagimi.sample
```

期望:`MenuBarComputeRingIcon.image` 调用极少或不出现;`advanceSmoothing` 在 idle 期间几乎不出现(timer 已 cancel)。

- [ ] **Step 9.9: 汇总报告交给用户**

写一个简短报告(Markdown 格式),列出:
- 改动前后 RSS / physical footprint 对比
- vmmap graphics 段对比
- 视觉与功能验证结果(通过 / 异常项)
- 单元测试通过情况

输出给用户审。**不要 commit。**

---

## Self-Review

1. **Spec coverage 检查**:
   - ① Icon 去 pulse + 加缓存 → Task 1+3+4 ✓
   - ② Store 删 menuBarFrame + 改 timer + 量化 → Task 2 ✓
   - ③ App 调用方更新 → Task 1 ✓
   - ④ DateFormatter 静态化 → Task 6 ✓
   - ⑤ @Published 清理 → Task 7 ✓
   - ⑥ Cache 单元测试 → Task 8 ✓
   - ⑦ 手测 checklist → Task 9 ✓

2. **Placeholder 扫描**:无 TBD/TODO,所有 step 都有具体代码或 grep/build 命令。

3. **类型一致性**:
   - `quantizeLoad` 在 Task 2 是 `private static func quantizeLoad(_ load: Double) -> Double`。
   - `cacheKey` 在 Task 4 是 `private static func cacheKey(load: Double, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSString`,内部用 `(load / 2.0).rounded()` 与 quantizeLoad 公式一致。
   - `image` 函数 Task 1 → Task 3 → Task 4 三次签名变化:`(load, frame=0, darkMode, loadLevel)` → `(load, darkMode, loadLevel)` → 同前 + 走 cache。一致。
   - `cacheIndex` 在 Task 4 用,定义也在 Task 4。

4. **风险点**:Task 2 Step 2.5 的"`advance()` 函数尾部"略依赖最近一次采样异步化提交(`969c648`)的实际位置;execution 时需要 reading 实际代码后插入。已在该步骤提示 engineer。

---

## 执行选择

Plan 已写完并保存到 `docs/superpowers/plans/2026-06-14-menu-bar-idle-memory-plan.md`。两种执行方式:

**1. Subagent-Driven(推荐)** — 每个 Task 派发独立 subagent 执行,Task 间用户审 diff,迭代快。

**2. Inline Execution** — 在当前 session 顺序执行所有 Task,checkpoint 处停下让用户审。

**⚠️ 不论哪种,所有 Task 末尾都不会 git commit,只 `git diff` 给用户审。** 用户审完决定下一步。

哪种?
