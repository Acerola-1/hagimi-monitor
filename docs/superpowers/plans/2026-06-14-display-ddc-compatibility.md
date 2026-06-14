# Display DDC/CI 兼容性升级 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 升级 `HagimiMonitorDirectOnly/` 下 Apple Silicon DDC 控制模块的兼容性、稳定性，并新增"接管系统亮度/音量媒体键"功能（默认关闭）。

**Architecture:** 在现有 `DisplayDDCBridge` + `DisplayControlController` 基础上分层补强：（1）底层加 percent↔raw 转换、fault counter、全局串行队列、慢屏自适应延迟；（2）显示器分类提取为 `DisplayClassifier`，过滤虚拟屏并把外接 Apple 原生屏导向 DisplayServices；（3）显示重配置/唤醒自动 refresh；（4）新增 `MediaKeyTapBridge` + `OSDBridge`，全局 `CGEventTap` 拦截媒体键，受用户偏好开关控制，启动时绝不主动索要 Accessibility 权限。

**Tech Stack:** Swift / SwiftUI / IOKit / CoreDisplay / DisplayServices(.framework) / OSD(.framework) / CGEventTap / Combine。仅 `HagimiMonitorDirect` scheme（`#if DISPLAY_CONTROL`）。

**Branch policy:** 实施前先创建并切换到 feature 分支（如 `feat/display-ddc-compat`），所有 task 在该分支上 commit。**严禁** push 远端、合并到 `dev` / `main`、创建 PR、打 tag。全部 task 完成后停下，告知用户分支名与 commit 列表，由用户决定是否合并入 dev。

**Reference repos in `docs/`:**
- `docs/MonitorControl-main/MonitorControl/Support/Arm64DDC.swift`
- `docs/MonitorControl-main/MonitorControl/Model/OtherDisplay.swift`
- `docs/MonitorControl-main/MonitorControl/Support/DisplayManager.swift`
- `docs/MonitorControl-main/MonitorControl/Support/MediaKeyTapManager.swift`
- `docs/MonitorControl-main/MonitorControl/Support/AppDelegate.swift` (148-186)
- `docs/Lunar-main/Lunar/DDC/DDC.swift`

---

## File Structure

新建文件：

| 路径 | 责任 |
|---|---|
| `HagimiMonitorDirectOnly/DDCRawConversion.swift` | percent ↔ DDC raw 转换 |
| `HagimiMonitorDirectOnly/DDCFaultRegistry.swift` | per-display per-control 失败计数与 disable 状态机 |
| `HagimiMonitorDirectOnly/DisplayClassifier.swift` | 显示器分类（builtIn / appleNative / externalDDC / virtual / dummy）|
| `HagimiMonitorDirectOnly/DisplayChangeObserver.swift` | 显示重配置 / 系统唤醒回调 |
| `HagimiMonitorDirectOnly/MediaKeyTapBridge.swift` | CGEventTap 拦截 NX_SYSDEFINED 系统按键 |
| `HagimiMonitorDirectOnly/MediaKeyController.swift` | 媒体键事件路由（选屏、步进计算、写入） |
| `HagimiMonitorDirectOnly/OSDBridge.swift` | macOS 原生 OSD 显示（私有 API） |
| `HagimiMonitorDirectOnly/AccessibilityPermissionService.swift` | Accessibility 权限检查 + 监听 |
| `HagimiMonitorDirectOnly/MediaKeySettingsSection.swift` | 媒体键设置 SwiftUI 子 section |
| `HagimiMonitorTests/DDCRawConversionTests.swift` | 转换单测 |
| `HagimiMonitorTests/DDCFaultRegistryTests.swift` | 状态机单测 |

修改文件：

| 路径 | 改动 |
|---|---|
| `HagimiMonitorDirectOnly/DisplayBridgingHeader.h` | 新增 OSDManager / IOPSCopyPowerSourcesInfo 等私有声明 |
| `HagimiMonitorDirectOnly/DisplayDDCBridge.swift` | 移除 `maxDetectLimit`；接入 fault registry；接入 raw 转换；调整音量/静音序列；变更 `ControlKey` 可见性以共享 |
| `HagimiMonitorDirectOnly/DisplayControlsSection.swift` | service 用 `DisplayClassifier`；外接 Apple 原生屏走 DisplayServices；监听重配置；接入全局串行队列；media key 入口 |
| `HagimiMonitor/MonitorSettings.swift` | 新增 5 个媒体键设置 + UserDefaults keys + Combine 持久化 |
| `HagimiMonitor/Localizable.xcstrings` | 新增 `mediaKey.*` 字符串（zh-Hans + en） |

---

## 公共类型约定

下列类型供多 task 共用，**首次出现的 task 负责创建，后续 task 仅引用**：

```swift
// HagimiMonitorDirectOnly/DDCFaultRegistry.swift（Task 2 创建，public to module）
struct ControlKey: Hashable {
    let displayID: CGDirectDisplayID
    let control: DisplayControlKind
}

// HagimiMonitorDirectOnly/MediaKeyTapBridge.swift（Task 9 创建）
enum MediaKey {
    case brightnessUp, brightnessDown
    case volumeUp, volumeDown, mute
}
```

注意：当前 `DisplayDDCBridge.swift:106-109` 已有 `private struct ControlKey`，Task 2 会把它**提升为模块内可见的非 private 类型**并删除原 private 定义。

---

## Task 1：percent ↔ DDC raw 转换 + 移除 `maxDetectLimit`

**Files:**
- Create: `HagimiMonitorDirectOnly/DDCRawConversion.swift`
- Create: `HagimiMonitorTests/DDCRawConversionTests.swift`
- Modify: `HagimiMonitorDirectOnly/DisplayDDCBridge.swift:14,16,40-50,57-95`

- [ ] **Step 1.1：写转换单测（先红）**

新建 `HagimiMonitorTests/DDCRawConversionTests.swift`：

```swift
import Testing
@testable import HagimiMonitor

struct DDCRawConversionTests {
    @Test func percentToRawClampsBelowZero() {
        #expect(DDCRawConversion.ddcRaw(percent: -10, max: 100) == 0)
    }

    @Test func percentToRawClampsAbove100() {
        #expect(DDCRawConversion.ddcRaw(percent: 150, max: 100) == 100)
    }

    @Test func percentToRawWithMax255() {
        #expect(DDCRawConversion.ddcRaw(percent: 50, max: 255) == 128)
    }

    @Test func percentToRawWithMax1() {
        #expect(DDCRawConversion.ddcRaw(percent: 50, max: 1) == 1)
        #expect(DDCRawConversion.ddcRaw(percent: 0, max: 1) == 0)
    }

    @Test func rawToPercentBasic() {
        #expect(abs(DDCRawConversion.percent(raw: 128, max: 255) - 50.196) < 0.01)
    }

    @Test func rawToPercentWithZeroMaxReturnsZero() {
        #expect(DDCRawConversion.percent(raw: 50, max: 0) == 0)
    }

    @Test func sanitizeMaxClampsExtreme() {
        #expect(DDCRawConversion.sanitize(max: 0) == 1)
        #expect(DDCRawConversion.sanitize(max: 65535) == 32767)
        #expect(DDCRawConversion.sanitize(max: 100) == 100)
    }
}
```

- [ ] **Step 1.2：跑测试确认失败**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug test \
  -only-testing:HagimiMonitorTests/DDCRawConversionTests
```

期望：编译失败，`DDCRawConversion` 未定义。

- [ ] **Step 1.3：实现 DDCRawConversion**

新建 `HagimiMonitorDirectOnly/DDCRawConversion.swift`：

```swift
import Foundation

enum DDCRawConversion {
    /// 将百分比（0...100）转换为 DDC 16-bit 原始值。
    static func ddcRaw(percent: Double, max: UInt16) -> UInt16 {
        let safeMax = sanitize(max: max)
        let clamped = min(100, Swift.max(0, percent))
        let scaled = clamped / 100.0 * Double(safeMax)
        return UInt16(scaled.rounded())
    }

    /// 将 DDC 原始值转换为百分比。
    static func percent(raw: UInt16, max: UInt16) -> Double {
        guard max > 0 else { return 0 }
        let value = Double(raw) / Double(max) * 100.0
        return min(100, Swift.max(0, value))
    }

    /// 防止异常 max 导致溢出或除零。
    static func sanitize(max: UInt16) -> UInt16 {
        if max == 0 { return 1 }
        if max > 32_767 { return 32_767 }
        return max
    }
}
```

- [ ] **Step 1.4：跑测试确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug test \
  -only-testing:HagimiMonitorTests/DDCRawConversionTests
```

期望：6 tests passed。

- [ ] **Step 1.5：在 DisplayDDCBridge 用上转换、移除 maxDetectLimit**

修改 `HagimiMonitorDirectOnly/DisplayDDCBridge.swift`：

删除第 16 行 `private let maxDetectLimit: UInt16 = 100`

将 `read(_:displayID:)`（第 26-55 行）的核心循环替换为：

```swift
let key = ControlKey(displayID: displayID, control: control)
for vcp in orderedCandidates(for: key) {
    guard let values = DDCTransport.read(service: service.service, vcpCode: vcp.rawValue),
          values.max > 0
    else {
        continue
    }

    let safeMax = DDCRawConversion.sanitize(max: values.max)
    let safeCurrent = min(values.current, safeMax)
    maxValues[key] = safeMax
    controlCodes[key] = vcp

    let percentage = DDCRawConversion.percent(raw: safeCurrent, max: safeMax)
    displayDDCLog.notice(
        "Read DDC display \(displayID, privacy: .public) control \(String(describing: control), privacy: .public) code \(vcp.rawValue, privacy: .public) raw \(values.current, privacy: .public)/\(values.max, privacy: .public) safe \(safeCurrent, privacy: .public)/\(safeMax, privacy: .public) percent \(percentage, privacy: .public)"
    )
    return percentage
}
```

将 `write(_:for:displayID:)`（第 57-95 行）的 `ddcValue` 计算替换：

```swift
let key = ControlKey(displayID: displayID, control: control)
let maxValue = maxValues[key] ?? 100
var ddcValue = DDCRawConversion.ddcRaw(percent: value, max: maxValue)
if control == .volume, value > 0 {
    ddcValue = Swift.max(1, ddcValue)
}
```

- [ ] **Step 1.6：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 1.7：commit**

```bash
git add HagimiMonitorDirectOnly/DDCRawConversion.swift \
        HagimiMonitorDirectOnly/DisplayDDCBridge.swift \
        HagimiMonitorTests/DDCRawConversionTests.swift
git commit -m "[优化] 移除 DDC max 钳制，按显示器真实最大值计算百分比"
```



---

## Task 2：DDCFaultRegistry 失败计数 + 自适应慢延迟

**Files:**
- Create: `HagimiMonitorDirectOnly/DDCFaultRegistry.swift`
- Create: `HagimiMonitorTests/DDCFaultRegistryTests.swift`
- Modify: `HagimiMonitorDirectOnly/DisplayDDCBridge.swift:106-109,12-104,151-209`

- [ ] **Step 2.1：写状态机单测**

新建 `HagimiMonitorTests/DDCFaultRegistryTests.swift`：

```swift
import Testing
@testable import HagimiMonitor
import CoreGraphics

struct DDCFaultRegistryTests {
    private let key = ControlKey(displayID: 1, control: .brightness)

    @Test func startsEnabled() {
        let r = DDCFaultRegistry()
        #expect(!r.isDisabled(key))
        #expect(!r.shouldUseLongerDelay(key))
    }

    @Test func disablesAfterFiveReadFailures() {
        let r = DDCFaultRegistry()
        for _ in 0..<4 { r.recordReadFailure(key) }
        #expect(!r.isDisabled(key))
        r.recordReadFailure(key)
        #expect(r.isDisabled(key))
    }

    @Test func disablesAfterTenWriteFailures() {
        let r = DDCFaultRegistry()
        for _ in 0..<9 { r.recordWriteFailure(key) }
        #expect(!r.isDisabled(key))
        r.recordWriteFailure(key)
        #expect(r.isDisabled(key))
    }

    @Test func longerDelayKicksInAtThreeReadFailures() {
        let r = DDCFaultRegistry()
        r.recordReadFailure(key)
        r.recordReadFailure(key)
        #expect(!r.shouldUseLongerDelay(key))
        r.recordReadFailure(key)
        #expect(r.shouldUseLongerDelay(key))
    }

    @Test func successDecrementsReadFault() {
        let r = DDCFaultRegistry()
        r.recordReadFailure(key)
        r.recordReadFailure(key)
        r.recordReadSuccess(key)
        #expect(!r.shouldUseLongerDelay(key))
    }

    @Test func resetClearsAllControlsForDisplay() {
        let r = DDCFaultRegistry()
        for _ in 0..<5 { r.recordReadFailure(key) }
        let other = ControlKey(displayID: 2, control: .brightness)
        for _ in 0..<5 { r.recordReadFailure(other) }
        r.reset(displayID: 1)
        #expect(!r.isDisabled(key))
        #expect(r.isDisabled(other))
    }
}
```

- [ ] **Step 2.2：跑测试确认失败**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug test \
  -only-testing:HagimiMonitorTests/DDCFaultRegistryTests
```

期望：编译失败，`DDCFaultRegistry` / `ControlKey` 未定义（`ControlKey` 当前是 private）。

- [ ] **Step 2.3：实现 DDCFaultRegistry 与公共 ControlKey**

新建 `HagimiMonitorDirectOnly/DDCFaultRegistry.swift`：

```swift
import CoreGraphics
import Foundation

struct ControlKey: Hashable {
    let displayID: CGDirectDisplayID
    let control: DisplayControlKind
}

final class DDCFaultRegistry {
    static let readFaultDisableThreshold = 5
    static let readFaultLongerDelayThreshold = 3
    static let writeFaultDisableThreshold = 10

    private struct State {
        var readFaults: Int = 0
        var writeFaults: Int = 0
        var disabled: Bool = false
    }

    private var states: [ControlKey: State] = [:]
    private let lock = NSLock()

    func recordReadFailure(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.readFaults += 1
        if s.readFaults >= Self.readFaultDisableThreshold {
            s.disabled = true
        }
        states[key] = s
    }

    func recordReadSuccess(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.readFaults = max(0, s.readFaults - 1)
        states[key] = s
    }

    func recordWriteFailure(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.writeFaults += 1
        if s.writeFaults >= Self.writeFaultDisableThreshold {
            s.disabled = true
        }
        states[key] = s
    }

    func recordWriteSuccess(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.writeFaults = max(0, s.writeFaults - 1)
        states[key] = s
    }

    func isDisabled(_ key: ControlKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return states[key]?.disabled ?? false
    }

    func shouldUseLongerDelay(_ key: ControlKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (states[key]?.readFaults ?? 0) >= Self.readFaultLongerDelayThreshold
    }

    func reset(displayID: CGDirectDisplayID) {
        lock.lock(); defer { lock.unlock() }
        for key in states.keys where key.displayID == displayID {
            states.removeValue(forKey: key)
        }
    }
}
```

修改 `HagimiMonitorDirectOnly/DisplayDDCBridge.swift`：删除原 `private struct ControlKey`（第 106-109 行），让代码引用 `DDCFaultRegistry.swift` 中的版本。

- [ ] **Step 2.4：跑测试确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug test \
  -only-testing:HagimiMonitorTests/DDCFaultRegistryTests
```

期望：6 tests passed。

- [ ] **Step 2.5：把 registry 接进 DisplayDDCBridge**

修改 `HagimiMonitorDirectOnly/DisplayDDCBridge.swift`：

`DisplayDDCBridge` 类内字段补充：

```swift
private let registry = DDCFaultRegistry()
```

`read` 函数入口（在第 26 行 `guard let service ...` 之后）加：

```swift
let earlyKey = ControlKey(displayID: displayID, control: control)
if registry.isDisabled(earlyKey) {
    return nil
}
```

`read` 函数内部循环成功路径（设置 `maxValues[key] = safeMax` 之后）加：

```swift
registry.recordReadSuccess(key)
```

`read` 函数失败 return（最后一行 `return nil` 之前）加：

```swift
registry.recordReadFailure(ControlKey(displayID: displayID, control: control))
```

`write` 函数入口（第 57 行 `guard let service ...` 之后）加：

```swift
let earlyKey = ControlKey(displayID: displayID, control: control)
if registry.isDisabled(earlyKey) {
    return false
}
```

`write` 函数尾部成功 return 前加 `registry.recordWriteSuccess(key)`，失败 return 前加 `registry.recordWriteFailure(ControlKey(displayID: displayID, control: control))`。

`refresh(displayIDs:)` 起始行加（reset 不在列表中的旧屏 + reset 新加入的屏）：

```swift
let knownIDs = Set(servicesByDisplayID.keys)
for id in knownIDs.subtracting(displayIDs) {
    registry.reset(displayID: id)
}
servicesByDisplayID = Arm64DDCMatcher().matchedServices(for: displayIDs)
```

- [ ] **Step 2.6：让 DDCTransport 支持自适应延迟**

修改 `HagimiMonitorDirectOnly/DisplayDDCBridge.swift` 中 `private enum DDCTransport`：

`read` 签名改为：

```swift
static func read(service: IOAVService, vcpCode: UInt8, longerDelay: Bool = false) -> (current: UInt16, max: UInt16)? {
    var send = [vcpCode]
    var reply = [UInt8](repeating: 0, count: 11)
    guard communicate(service: service, send: &send, reply: &reply, longerDelay: longerDelay) else {
        return nil
    }
    let maxValue = (UInt16(reply[6]) << 8) + UInt16(reply[7])
    let currentValue = (UInt16(reply[8]) << 8) + UInt16(reply[9])
    return (currentValue, maxValue)
}
```

`communicate` 签名改为 `static func communicate(service: IOAVService, send: inout [UInt8], reply: inout [UInt8], longerDelay: Bool = false) -> Bool`，并将原 `usleep(50_000)` 改为：

```swift
usleep(longerDelay ? 150_000 : 50_000)
```

`DisplayDDCBridge.read` 调用处改成：

```swift
let useLongDelay = registry.shouldUseLongerDelay(key)
guard let values = DDCTransport.read(service: service.service, vcpCode: vcp.rawValue, longerDelay: useLongDelay),
      values.max > 0
else {
    continue
}
```

- [ ] **Step 2.7：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 2.8：commit**

```bash
git add HagimiMonitorDirectOnly/DDCFaultRegistry.swift \
        HagimiMonitorDirectOnly/DisplayDDCBridge.swift \
        HagimiMonitorTests/DDCFaultRegistryTests.swift
git commit -m "[新增] DDC 失败计数与连续失败后自动延长延迟"
```

---

## Task 3：DisplayClassifier + 虚拟屏过滤 + 外接 Apple 原生屏走 DisplayServices

**Files:**
- Create: `HagimiMonitorDirectOnly/DisplayClassifier.swift`
- Modify: `HagimiMonitorDirectOnly/DisplayControlsSection.swift:526-597`

- [ ] **Step 3.1：实现 DisplayClassifier**

新建 `HagimiMonitorDirectOnly/DisplayClassifier.swift`：

```swift
import CoreGraphics
import Foundation

enum DisplayKind: Equatable {
    case builtIn
    case appleNative
    case externalDDC
    case virtual
    case dummy
    case unsupported
}

struct DisplayClassifier {
    let probeNativeBrightness: (CGDirectDisplayID) -> Bool

    init(probeNativeBrightness: @escaping (CGDirectDisplayID) -> Bool = DisplayClassifier.defaultProbe) {
        self.probeNativeBrightness = probeNativeBrightness
    }

    func classify(displayID: CGDirectDisplayID) -> DisplayKind {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return .builtIn
        }

        let info = CoreDisplay_DisplayCreateInfoDictionary(displayID)?
            .takeRetainedValue() as? [String: Any] ?? [:]

        if (info["kCGDisplayIsVirtualDevice"] as? Bool) == true ||
           (info["kCGDisplayIsAirPlay"] as? Bool) == true {
            return .virtual
        }

        if isDummy(info: info) {
            return .dummy
        }

        if probeNativeBrightness(displayID) {
            return .appleNative
        }

        return .externalDDC
    }

    private func isDummy(info: [String: Any]) -> Bool {
        let names = info["DisplayProductName"] as? [String: String] ?? [:]
        if names.values.contains(where: { $0.lowercased().contains("dummy") }) {
            return true
        }
        if let vendor = info["DisplayVendorID"] as? Int64, vendor == 0xF0F0 {
            return true
        }
        return false
    }

    static func defaultProbe(_ id: CGDirectDisplayID) -> Bool {
        var brightness: Float = -1
        let result = DisplayServicesGetBrightness(id, &brightness)
        return result == 0 && brightness >= 0
    }
}
```

- [ ] **Step 3.2：构建确认编译通过（暂未接线）**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 3.3：在 DisplayControlService 用 classifier 替换 isBuiltIn 判断**

修改 `HagimiMonitorDirectOnly/DisplayControlsSection.swift` 中 `private final class DisplayControlService`（第 526 行起）：

字段补充：

```swift
private let classifier = DisplayClassifier()
```

`displays()` 函数（第 531 行）的循环主体改为：

```swift
return displayIDs.compactMap { id -> ControlledDisplay? in
    let kind = classifier.classify(displayID: id)

    if kind == .virtual || kind == .dummy || kind == .unsupported {
        return nil
    }

    let isBuiltIn = (kind == .builtIn)
    let useDisplayServices = (kind == .builtIn || kind == .appleNative)
    let name = displayName(for: id, isBuiltIn: isBuiltIn)
    let storageID = displayStorageID(for: id, name: name, isBuiltIn: isBuiltIn)

    let nativeBrightness = useDisplayServices ? displayServices.getBrightness(displayID: id) : nil
    let hasDDCService = (kind == .externalDDC) && ddc.hasService(for: id)
    let ddcBrightness = (kind == .externalDDC) ? ddc.read(.brightness, displayID: id) : nil
    let ddcVolume = (kind == .externalDDC) ? ddc.read(.volume, displayID: id) : nil
    let ddcContrast = (kind == .externalDDC) ? ddc.read(.contrast, displayID: id) : nil

    let storedBrightness = storedValue(for: .brightness, displayStorageID: storageID)
    let storedVolume = storedValue(for: .volume, displayStorageID: storageID)
    let storedContrast = storedValue(for: .contrast, displayStorageID: storageID)

    return ControlledDisplay(
        id: id,
        storageID: storageID,
        name: name,
        isBuiltIn: isBuiltIn,
        supportsBrightness: useDisplayServices
            ? (nativeBrightness != nil)
            : (ddcBrightness != nil || storedBrightness != nil || hasDDCService),
        supportsVolume: !useDisplayServices && (ddcVolume != nil || storedVolume != nil),
        supportsContrast: !useDisplayServices && (ddcContrast != nil || storedContrast != nil),
        brightness: nativeBrightness.map { Double($0 * 100) }
            ?? ddcBrightness
            ?? storedBrightness
            ?? DisplayControlKind.brightness.defaultValue,
        volume: ddcVolume
            ?? storedVolume
            ?? DisplayControlKind.volume.defaultValue,
        contrast: ddcContrast
            ?? storedContrast
            ?? DisplayControlKind.contrast.defaultValue
    )
}
```

`setValue(_:for:display:)`（第 578 行）改为：

```swift
func setValue(_ value: Double, for control: DisplayControlKind, display: ControlledDisplay) -> Bool {
    guard display.supports(control) else { return false }

    let kind = classifier.classify(displayID: display.id)
    let useDisplayServices = (kind == .builtIn || kind == .appleNative)

    if useDisplayServices {
        switch control {
        case .brightness:
            return displayServices.setBrightness(displayID: display.id, value: Float(value / 100))
        case .volume, .contrast:
            return false
        }
    }

    let success = ddc.write(value, for: control, displayID: display.id)
    if success {
        saveStoredValue(value, for: control, displayStorageID: display.storageID)
    }
    return success
}
```

- [ ] **Step 3.4：构建并人工验证**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

人工验证（在装有外接屏的机器上跑）：
- 启动 App，检查日志：`Detected N online displays` 后无虚拟屏
- 若连接 Sidecar 或 AirPlay，应不出现在 panel 中

- [ ] **Step 3.5：commit**

```bash
git add HagimiMonitorDirectOnly/DisplayClassifier.swift \
        HagimiMonitorDirectOnly/DisplayControlsSection.swift
git commit -m "[新增] 显示器分类，过滤虚拟屏并把外接 Apple 原生屏导向 DisplayServices"
```

---

## Task 4：全局串行队列 + last-value 去重

**Files:**
- Modify: `HagimiMonitorDirectOnly/DisplayControlsSection.swift:393-427`

- [ ] **Step 4.1：改造 DisplayControlWorker**

修改 `HagimiMonitorDirectOnly/DisplayControlsSection.swift` 中 `private final class DisplayControlWorker`（第 392 行起）替换为：

```swift
private final class DisplayControlWorker {
    static let shared = DisplayControlWorker()

    private let queue = DispatchQueue(label: "hagimi.ddc.global", qos: .userInitiated)
    private var pendingWrites: [ControlKey: Double] = [:]
    private var lastWrittenValues: [ControlKey: Double] = [:]
    private var debounceTimers: [ControlKey: DispatchWorkItem] = [:]
    private let debounceInterval: DispatchTimeInterval = .milliseconds(150)

    func refresh(service: DisplayControlService, completion: @escaping ([ControlledDisplay]) -> Void) {
        queue.async {
            completion(service.displays())
        }
    }

    func setValue(
        _ value: Double,
        for key: ControlKey,
        display: ControlledDisplay,
        service: DisplayControlService,
        completion: @escaping (DisplayWriteResult) -> Void
    ) {
        queue.async {
            self.pendingWrites[key] = value
            self.debounceTimers[key]?.cancel()
            let timer = DispatchWorkItem { [service, display, key, completion] in
                guard let latestValue = self.pendingWrites.removeValue(forKey: key) else { return }
                self.debounceTimers.removeValue(forKey: key)

                if let last = self.lastWrittenValues[key], abs(last - latestValue) < 0.001 {
                    completion(DisplayWriteResult(key: key, value: latestValue, success: true))
                    return
                }

                let success = service.setValue(latestValue, for: key.control, display: display)
                if success {
                    self.lastWrittenValues[key] = latestValue
                }
                completion(DisplayWriteResult(key: key, value: latestValue, success: success))
            }
            self.debounceTimers[key] = timer
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: timer)
        }
    }

    /// 显示器移除时调用，避免污染重新接入后的去重判断
    func clearLastValues(displayID: CGDirectDisplayID) {
        queue.async {
            for key in self.lastWrittenValues.keys where key.displayID == displayID {
                self.lastWrittenValues.removeValue(forKey: key)
            }
            for key in self.pendingWrites.keys where key.displayID == displayID {
                self.pendingWrites.removeValue(forKey: key)
            }
            self.debounceTimers.values.forEach { $0.cancel() }
            self.debounceTimers.removeAll()
        }
    }
}
```

修改 `DisplayControlController`（约第 290 行）中：

```swift
private let worker = DisplayControlWorker()
```

改为：

```swift
private let worker = DisplayControlWorker.shared
```

- [ ] **Step 4.2：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 4.3：commit**

```bash
git add HagimiMonitorDirectOnly/DisplayControlsSection.swift
git commit -m "[优化] DDC 写入改为全局串行队列 + 上次值去重"
```

---

## Task 5：调整音量/静音写入序列

**Files:**
- Modify: `HagimiMonitorDirectOnly/DisplayDDCBridge.swift:57-95`

- [ ] **Step 5.1：调整音量写入逻辑**

修改 `HagimiMonitorDirectOnly/DisplayDDCBridge.swift` 的 `write(_:for:displayID:)`：

把原音量/静音处理（`if control == .volume`...`if value <= 0` 块）替换为：

```swift
if control == .volume, value <= 0 {
    let muteSuccess = DDCTransport.write(
        service: service.service,
        vcpCode: DDCVCPCode.audioMuteScreenBlank.rawValue,
        value: 1
    )
    if muteSuccess {
        registry.recordWriteSuccess(key)
        displayDDCLog.notice("Wrote DDC mute display \(displayID, privacy: .public)")
        return true
    }
    registry.recordWriteFailure(key)
    return false
}
```

即：`value > 0` 时不再主动 unmute（让显示器自己处理），仅 `value == 0` 时发 mute=1。

- [ ] **Step 5.2：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 5.3：commit**

```bash
git add HagimiMonitorDirectOnly/DisplayDDCBridge.swift
git commit -m "[修复] 音量写入不再主动 unmute，避免部分显示器忽略后续 volume"
```

---

## Task 6：DisplayChangeObserver + 自动 refresh

**Files:**
- Create: `HagimiMonitorDirectOnly/DisplayChangeObserver.swift`
- Modify: `HagimiMonitorDirectOnly/DisplayControlsSection.swift:289-308`

- [ ] **Step 6.1：实现 DisplayChangeObserver**

新建 `HagimiMonitorDirectOnly/DisplayChangeObserver.swift`：

```swift
import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DisplayChangeObserver {
    private var callback: (() -> Void)?
    private var debounceTimer: DispatchSourceTimer?
    private var registered = false

    func start(onChange: @escaping () -> Void) {
        callback = onChange
        if !registered {
            CGDisplayRegisterReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
            registered = true
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
            registered = false
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        debounceTimer?.cancel()
        debounceTimer = nil
    }

    deinit {
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func systemDidWake(_ note: Notification) {
        scheduleCallback(after: .milliseconds(800))
    }

    fileprivate func handleReconfigure() {
        scheduleCallback(after: .milliseconds(1000))
    }

    private func scheduleCallback(after delay: DispatchTimeInterval) {
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.callback?()
        }
        debounceTimer = timer
        timer.resume()
    }

    private static let cgCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        // 仅在配置已应用阶段触发，避免开始/中间阶段过多回调
        if flags.contains(.endsConfigurationFlag) ||
           flags.contains(.addFlag) ||
           flags.contains(.removeFlag) {
            let observer = Unmanaged<DisplayChangeObserver>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                observer.handleReconfigure()
            }
        }
    }
}
```

- [ ] **Step 6.2：在 DisplayControlController 中接入**

修改 `HagimiMonitorDirectOnly/DisplayControlsSection.swift` 中 `DisplayControlController`（约第 289 行）：

加字段：

```swift
private let changeObserver = DisplayChangeObserver()
```

加 init：

```swift
init() {
    changeObserver.start { [weak self] in
        self?.refreshAsync()
    }
}

deinit {
    changeObserver.stop()
}
```

- [ ] **Step 6.3：构建并验证**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

人工验证：
- 启动 App
- 拔插一根 USB-C 显示器线
- 观察日志中再次出现 `Detected N online displays`

- [ ] **Step 6.4：commit**

```bash
git add HagimiMonitorDirectOnly/DisplayChangeObserver.swift \
        HagimiMonitorDirectOnly/DisplayControlsSection.swift
git commit -m "[新增] 显示器重配置/系统唤醒后自动刷新 DDC 服务列表"
```

---

## Task 7：capability probe 拆分（lazy volume/contrast + retry 降级）

**Files:**
- Modify: `HagimiMonitorDirectOnly/DisplayDDCBridge.swift`（DDCTransport.communicate 的 retry 次数）
- Modify: `HagimiMonitorDirectOnly/DisplayControlsSection.swift`（DisplayControlService.displays / value 路径）

- [ ] **Step 7.1：让 DDCTransport.communicate 支持自定义 retry 次数**

修改 `HagimiMonitorDirectOnly/DisplayDDCBridge.swift` 中 `DDCTransport.communicate`：

签名改为：

```swift
private static func communicate(
    service: IOAVService,
    send: inout [UInt8],
    reply: inout [UInt8],
    longerDelay: Bool = false,
    maxRetries: Int = 5
) -> Bool {
```

将原 `for _ in 0..<5` 改为 `for _ in 0..<maxRetries`。

`DDCTransport.read` 和 `DDCTransport.write` 增加 `maxRetries` 参数转发：

```swift
static func read(service: IOAVService, vcpCode: UInt8, longerDelay: Bool = false, maxRetries: Int = 5) -> (current: UInt16, max: UInt16)? { ... communicate(..., maxRetries: maxRetries) ... }
static func write(service: IOAVService, vcpCode: UInt8, value: UInt16, maxRetries: Int = 5) -> Bool { ... communicate(..., maxRetries: maxRetries) ... }
```

`DisplayDDCBridge.read(_:displayID:)` 增加：

```swift
func read(_ control: DisplayControlKind, displayID: CGDirectDisplayID, fastFail: Bool = false) -> Double? {
    ...
    let retries = fastFail ? 2 : 5
    ...
    guard let values = DDCTransport.read(service: service.service, vcpCode: vcp.rawValue, longerDelay: useLongDelay, maxRetries: retries),
          values.max > 0 else { continue }
    ...
}
```

- [ ] **Step 7.2：DisplayControlService.displays 启动只 probe brightness**

修改 `HagimiMonitorDirectOnly/DisplayControlsSection.swift` 中 `displays()` 的 externalDDC 分支：

```swift
let ddcBrightness = (kind == .externalDDC) ? ddc.read(.brightness, displayID: id, fastFail: true) : nil
let ddcVolume: Double? = nil    // lazy
let ddcContrast: Double? = nil  // lazy
```

并把 `supportsVolume` / `supportsContrast` 的判定改为：

```swift
supportsVolume: !useDisplayServices && hasDDCService,
supportsContrast: !useDisplayServices && hasDDCService,
```

即 capability 由 hasDDCService 推断，真实是否可用由首次 read/write 后 fault counter 兜底。

- [ ] **Step 7.3：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。启动 App 应明显比之前更快进入 panel。

- [ ] **Step 7.4：commit**

```bash
git add HagimiMonitorDirectOnly/DisplayDDCBridge.swift \
        HagimiMonitorDirectOnly/DisplayControlsSection.swift
git commit -m "[优化] 启动只 probe 亮度，volume/contrast 延迟到首次访问，retry 减半"
```

---

## Task 8：MonitorSettings 新增媒体键设置项

**Files:**
- Modify: `HagimiMonitor/MonitorSettings.swift:53-90,225-260,300-320`

- [ ] **Step 8.1：添加 @Published 字段**

修改 `HagimiMonitor/MonitorSettings.swift`，在现有 `@Published var displayContrastControlEnabled: Bool = false` 之后插入：

```swift
@Published var mediaKeyBrightnessEnabled: Bool = false
@Published var mediaKeyVolumeEnabled: Bool = false
@Published var mediaKeyShowOSD: Bool = true
@Published var mediaKeyFineScaleBrightness: Bool = false
@Published var mediaKeyFineScaleVolume: Bool = false
```

- [ ] **Step 8.2：在 init 中读取持久化**

在 init 中添加（紧接 `displayContrastControlEnabled = ...` 那行后）：

```swift
mediaKeyBrightnessEnabled = defaults.object(forKey: Keys.mediaKeyBrightnessEnabled) as? Bool ?? false
mediaKeyVolumeEnabled = defaults.object(forKey: Keys.mediaKeyVolumeEnabled) as? Bool ?? false
mediaKeyShowOSD = defaults.object(forKey: Keys.mediaKeyShowOSD) as? Bool ?? true
mediaKeyFineScaleBrightness = defaults.object(forKey: Keys.mediaKeyFineScaleBrightness) as? Bool ?? false
mediaKeyFineScaleVolume = defaults.object(forKey: Keys.mediaKeyFineScaleVolume) as? Bool ?? false
```

- [ ] **Step 8.3：添加 Combine 持久化绑定**

在现有 `$displayContrastControlEnabled.sink { ... }.store(in: &cancellables)` 之后添加：

```swift
$mediaKeyBrightnessEnabled
    .dropFirst()
    .sink { [weak self] newValue in
        self?.persist(newValue, forKey: Keys.mediaKeyBrightnessEnabled)
    }
    .store(in: &cancellables)

$mediaKeyVolumeEnabled
    .dropFirst()
    .sink { [weak self] newValue in
        self?.persist(newValue, forKey: Keys.mediaKeyVolumeEnabled)
    }
    .store(in: &cancellables)

$mediaKeyShowOSD
    .dropFirst()
    .sink { [weak self] newValue in
        self?.persist(newValue, forKey: Keys.mediaKeyShowOSD)
    }
    .store(in: &cancellables)

$mediaKeyFineScaleBrightness
    .dropFirst()
    .sink { [weak self] newValue in
        self?.persist(newValue, forKey: Keys.mediaKeyFineScaleBrightness)
    }
    .store(in: &cancellables)

$mediaKeyFineScaleVolume
    .dropFirst()
    .sink { [weak self] newValue in
        self?.persist(newValue, forKey: Keys.mediaKeyFineScaleVolume)
    }
    .store(in: &cancellables)
```

- [ ] **Step 8.4：添加 Keys 常量**

在 `private enum Keys` 中加：

```swift
static let mediaKeyBrightnessEnabled = "settings.mediaKey.brightnessEnabled"
static let mediaKeyVolumeEnabled = "settings.mediaKey.volumeEnabled"
static let mediaKeyShowOSD = "settings.mediaKey.showOSD"
static let mediaKeyFineScaleBrightness = "settings.mediaKey.fineScaleBrightness"
static let mediaKeyFineScaleVolume = "settings.mediaKey.fineScaleVolume"
```

- [ ] **Step 8.5：构建并跑现有 SettingsTests**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug test \
  -only-testing:HagimiMonitorTests/SettingsTests
```

期望：现有测试全部通过（新字段不破坏旧测试）。

- [ ] **Step 8.6：commit**

```bash
git add HagimiMonitor/MonitorSettings.swift
git commit -m "[新增] 媒体键接管的 5 个偏好项（默认全部关闭）"
```

---

## Task 9：MediaKeyTapBridge（CGEventTap 拦截）

**Files:**
- Create: `HagimiMonitorDirectOnly/MediaKeyTapBridge.swift`

- [ ] **Step 9.1：实现 MediaKeyTapBridge**

新建 `HagimiMonitorDirectOnly/MediaKeyTapBridge.swift`：

```swift
import AppKit
import Foundation
import OSLog

private let mediaKeyLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "MediaKey")

enum MediaKey {
    case brightnessUp, brightnessDown
    case volumeUp, volumeDown, mute
}

struct MediaKeyEvent {
    let key: MediaKey
    let isPressed: Bool
    let isRepeat: Bool
    let modifiers: NSEvent.ModifierFlags
}

final class MediaKeyTapBridge {
    typealias Handler = (MediaKeyEvent) -> Bool   // 返回 true 表示已处理，吞掉事件

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: Handler?
    private var enabledKeys: Set<MediaKey> = []

    func start(keys: Set<MediaKey>, handler: @escaping Handler) -> Bool {
        stop()
        guard !keys.isEmpty else {
            mediaKeyLog.notice("MediaKeyTapBridge.start called with empty keys; staying inactive")
            return false
        }
        self.enabledKeys = keys
        self.handler = handler

        let mask = (1 << CGEventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            mediaKeyLog.error("CGEvent.tapCreate failed (likely missing Accessibility permission)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        mediaKeyLog.notice("MediaKeyTapBridge started with \(keys.count, privacy: .public) keys")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        handler = nil
        enabledKeys = []
    }

    deinit { stop() }

    private static let tapCallback: CGEventTapCallBack = { _, type, cgEvent, refcon in
        guard let refcon else { return Unmanaged.passUnretained(cgEvent) }
        let bridge = Unmanaged<MediaKeyTapBridge>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = bridge.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        guard type == .systemDefined,
              let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.subtype.rawValue == 8
        else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = Int32((data1 & 0xFFFF_0000) >> 16)
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isPressed = keyState == 0x0A
        let isRepeat = (keyFlags & 0x1) == 1

        let key: MediaKey?
        switch Int(keyCode) {
        case NX_KEYTYPE_BRIGHTNESS_UP: key = .brightnessUp
        case NX_KEYTYPE_BRIGHTNESS_DOWN: key = .brightnessDown
        case NX_KEYTYPE_SOUND_UP: key = .volumeUp
        case NX_KEYTYPE_SOUND_DOWN: key = .volumeDown
        case NX_KEYTYPE_MUTE: key = .mute
        default: key = nil
        }

        guard let mediaKey = key, bridge.enabledKeys.contains(mediaKey) else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let event = MediaKeyEvent(
            key: mediaKey,
            isPressed: isPressed,
            isRepeat: isRepeat,
            modifiers: nsEvent.modifierFlags
        )

        if bridge.handler?(event) == true {
            return nil
        }
        return Unmanaged.passUnretained(cgEvent)
    }
}
```

注意：`NX_KEYTYPE_*` 常量来自 `<IOKit/hidsystem/ev_keymap.h>`，由现有 `DisplayBridgingHeader.h` 间接 import IOKit 已可用；如不可用则在 Step 9.2 处理。

- [ ] **Step 9.2：构建确认 NX_KEYTYPE 常量可用**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

如果报错 `NX_KEYTYPE_BRIGHTNESS_UP` 未定义，在 `HagimiMonitorDirectOnly/DisplayBridgingHeader.h` 末尾追加：

```c
#import <IOKit/hidsystem/ev_keymap.h>
```

再次构建。期望：BUILD SUCCEEDED。

- [ ] **Step 9.3：commit**

```bash
git add HagimiMonitorDirectOnly/MediaKeyTapBridge.swift \
        HagimiMonitorDirectOnly/DisplayBridgingHeader.h
git commit -m "[新增] MediaKeyTapBridge：CGEventTap 拦截系统亮度/音量按键"
```

---

## Task 10：AccessibilityPermissionService

**Files:**
- Create: `HagimiMonitorDirectOnly/AccessibilityPermissionService.swift`

- [ ] **Step 10.1：实现权限服务**

新建 `HagimiMonitorDirectOnly/AccessibilityPermissionService.swift`：

```swift
import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionService: ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: DispatchSourceTimer?

    init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(accessibilityChanged(_:)),
            name: .init("com.apple.accessibility.api"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        pollTimer?.cancel()
    }

    /// 静默检查（不弹系统对话框）
    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// 主动请求权限：弹系统对话框 + 跳转设置面板
    func request() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
        ]
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
        startPollingUntilGranted()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func accessibilityChanged(_ note: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    private func startPollingUntilGranted() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.refresh()
            if self.isTrusted {
                self.pollTimer?.cancel()
                self.pollTimer = nil
            }
        }
        pollTimer = timer
        timer.resume()
    }
}
```

`com.apple.accessibility.api` 通知有时不触发；`startPollingUntilGranted` 是兜底，每秒检查一次直到拿到权限。

- [ ] **Step 10.2：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 10.3：commit**

```bash
git add HagimiMonitorDirectOnly/AccessibilityPermissionService.swift
git commit -m "[新增] Accessibility 权限服务：静默检查 + 用户主动请求 + 通知监听"
```

---

## Task 11：OSDBridge（macOS 原生 OSD）

**Files:**
- Modify: `HagimiMonitorDirectOnly/DisplayBridgingHeader.h`
- Create: `HagimiMonitorDirectOnly/OSDBridge.swift`

- [ ] **Step 11.1：在 bridging header 声明 OSDManager**

修改 `HagimiMonitorDirectOnly/DisplayBridgingHeader.h`，末尾追加：

```c
@interface OSDManager : NSObject
+ (id _Nullable)sharedManager;
- (void)showImage:(long long)image
        onDisplayID:(unsigned int)displayID
        priority:(unsigned int)priority
        msecUntilFade:(unsigned int)msec
        filledChiclets:(unsigned int)filled
        totalChiclets:(unsigned int)total
        locked:(BOOL)locked;
@end
```

- [ ] **Step 11.2：实现 OSDBridge**

新建 `HagimiMonitorDirectOnly/OSDBridge.swift`：

```swift
import CoreGraphics
import Foundation
import OSLog

private let osdLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "OSD")

enum OSDImage: Int64 {
    case brightness = 1
    case speaker = 3
    case speakerMuted = 4
}

final class OSDBridge {
    private static let osdManagerClass: AnyClass? = NSClassFromString("OSDManager")

    func show(
        _ image: OSDImage,
        displayID: CGDirectDisplayID,
        percent: Double,
        totalChiclets: Int = 100
    ) {
        guard let cls = Self.osdManagerClass as? NSObject.Type,
              let manager = cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue()
        else {
            osdLog.warning("OSDManager class unavailable")
            return
        }

        let filled = max(0, min(totalChiclets, Int((percent / 100.0 * Double(totalChiclets)).rounded())))
        let selector = NSSelectorFromString(
            "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:"
        )
        guard manager.responds(to: selector) else {
            osdLog.warning("OSDManager does not respond to showImage:onDisplayID:...")
            return
        }

        // 直接调 ObjC 方法（参数较多，用 NSInvocation 不实际，依赖 Bridging-Header 中的接口声明走类型化调用）
        if let typedManager = manager as? OSDManager {
            typedManager.showImage(
                image.rawValue,
                onDisplayID: displayID,
                priority: 0x1F4,
                msecUntilFade: 1000,
                filledChiclets: UInt32(filled),
                totalChiclets: UInt32(totalChiclets),
                locked: false
            )
        }
    }
}
```

- [ ] **Step 11.3：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

如果链接器报告 OSDManager 未定义，检查 project 是否已链接 `/System/Library/PrivateFrameworks/OSD.framework`。如未链接，在 Xcode 项目 Direct target 的 General → Frameworks, Libraries → 添加该 framework（`-framework OSD`，weak link 推荐）。

期望：BUILD SUCCEEDED。

- [ ] **Step 11.4：commit**

```bash
git add HagimiMonitorDirectOnly/DisplayBridgingHeader.h \
        HagimiMonitorDirectOnly/OSDBridge.swift \
        hagimi-monitor.xcodeproj
git commit -m "[新增] 通过 OSD.framework 显示原生亮度/音量提示"
```

---

## Task 12：MediaKeyController（事件路由 + 选屏 + 步进）

**Files:**
- Create: `HagimiMonitorDirectOnly/MediaKeyController.swift`

- [ ] **Step 12.1：实现 MediaKeyController**

新建 `HagimiMonitorDirectOnly/MediaKeyController.swift`：

```swift
import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class MediaKeyController {
    private let tap = MediaKeyTapBridge()
    private let osd = OSDBridge()
    private let permission: AccessibilityPermissionService
    private weak var controller: DisplayControlController?
    private var settings: MonitorSettings?

    private var standardStep: Double = 100.0 / 16.0
    private var fineStep: Double = 100.0 / 64.0

    init(permission: AccessibilityPermissionService) {
        self.permission = permission
    }

    func attach(controller: DisplayControlController, settings: MonitorSettings) {
        self.controller = controller
        self.settings = settings
        refresh()
    }

    func refresh() {
        guard let settings else { return }
        let wantBrightness = settings.mediaKeyBrightnessEnabled
        let wantVolume = settings.mediaKeyVolumeEnabled

        guard wantBrightness || wantVolume else {
            tap.stop()
            return
        }
        guard permission.isTrusted else {
            tap.stop()
            return
        }

        var keys: Set<MediaKey> = []
        if wantBrightness, hasExternalDDCDisplay() {
            keys.formUnion([.brightnessUp, .brightnessDown])
        }
        if wantVolume, hasExternalAudioCapableDisplay() {
            keys.formUnion([.volumeUp, .volumeDown, .mute])
        }
        if keys.isEmpty {
            tap.stop()
            return
        }

        _ = tap.start(keys: keys) { [weak self] event in
            guard let self else { return false }
            return self.handle(event: event)
        }
    }

    private func handle(event: MediaKeyEvent) -> Bool {
        guard event.isPressed else { return true }

        let isOptionOnly = event.modifiers.contains(.option)
            && !event.modifiers.contains(.shift)
            && !event.modifiers.contains(.command)
            && !event.modifiers.contains(.control)

        if isOptionOnly && !event.isRepeat {
            switch event.key {
            case .brightnessUp, .brightnessDown:
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
            case .volumeUp, .volumeDown, .mute:
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Sound.prefPane"))
            }
            return true
        }

        let isFine = event.modifiers.contains(.shift) && event.modifiers.contains(.option)
        let invertFine: Bool
        switch event.key {
        case .brightnessUp, .brightnessDown:
            invertFine = settings?.mediaKeyFineScaleBrightness ?? false
        default:
            invertFine = settings?.mediaKeyFineScaleVolume ?? false
        }
        let useFine = invertFine ? !isFine : isFine
        let step = useFine ? fineStep : standardStep

        switch event.key {
        case .brightnessUp:
            adjustBrightness(by: +step); return true
        case .brightnessDown:
            adjustBrightness(by: -step); return true
        case .volumeUp:
            adjustVolume(by: +step); return true
        case .volumeDown:
            adjustVolume(by: -step); return true
        case .mute:
            toggleMute(); return true
        }
    }

    private func adjustBrightness(by delta: Double) {
        guard let controller else { return }
        for display in controller.displays where !display.isBuiltIn && display.supportsBrightness {
            let current = controller.value(for: .brightness, displayID: display.id)
            let next = min(100, max(0, current + delta))
            controller.setValueAsync(next, for: .brightness, displayID: display.id)
            if settings?.mediaKeyShowOSD == true {
                osd.show(.brightness, displayID: display.id, percent: next)
            }
        }
    }

    private func adjustVolume(by delta: Double) {
        guard let controller else { return }
        for display in controller.displays where !display.isBuiltIn && display.supportsVolume {
            let current = controller.value(for: .volume, displayID: display.id)
            let next = min(100, max(0, current + delta))
            controller.setValueAsync(next, for: .volume, displayID: display.id)
            if settings?.mediaKeyShowOSD == true {
                let image: OSDImage = next <= 0 ? .speakerMuted : .speaker
                osd.show(image, displayID: display.id, percent: next)
            }
        }
    }

    private func toggleMute() {
        guard let controller else { return }
        for display in controller.displays where !display.isBuiltIn && display.supportsVolume {
            let current = controller.value(for: .volume, displayID: display.id)
            let next: Double = current > 0 ? 0 : 50
            controller.setValueAsync(next, for: .volume, displayID: display.id)
            if settings?.mediaKeyShowOSD == true {
                let image: OSDImage = next <= 0 ? .speakerMuted : .speaker
                osd.show(image, displayID: display.id, percent: next)
            }
        }
    }

    private func hasExternalDDCDisplay() -> Bool {
        controller?.displays.contains { !$0.isBuiltIn && $0.supportsBrightness } ?? false
    }

    private func hasExternalAudioCapableDisplay() -> Bool {
        controller?.displays.contains { !$0.isBuiltIn && $0.supportsVolume } ?? false
    }
}
```

- [ ] **Step 12.2：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 12.3：commit**

```bash
git add HagimiMonitorDirectOnly/MediaKeyController.swift
git commit -m "[新增] MediaKeyController 路由媒体键到 DDC + OSD"
```

---

## Task 13：将 MediaKeyController 接入 DisplayControlController

**Files:**
- Modify: `HagimiMonitorDirectOnly/DisplayControlsSection.swift`（DisplayControlController init / refreshAsync 完成后通知 controller refresh）

- [ ] **Step 13.1：DisplayControlController 暴露 settings 和 permission**

修改 `DisplayControlController`（约 290 行）：

字段加：

```swift
let permission = AccessibilityPermissionService()
private lazy var mediaKeyController = MediaKeyController(permission: permission)
private var settingsObservation: AnyCancellable?
```

init 改为：

```swift
init() {
    changeObserver.start { [weak self] in
        self?.refreshAsync()
    }
}

func attach(settings: MonitorSettings) {
    mediaKeyController.attach(controller: self, settings: settings)

    let merged = Publishers.Merge5(
        settings.$mediaKeyBrightnessEnabled.map { _ in () },
        settings.$mediaKeyVolumeEnabled.map { _ in () },
        settings.$mediaKeyShowOSD.map { _ in () },
        settings.$mediaKeyFineScaleBrightness.map { _ in () },
        settings.$mediaKeyFineScaleVolume.map { _ in () }
    )
    .merge(with: permission.$isTrusted.map { _ in () })

    settingsObservation = merged
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.mediaKeyController.refresh()
        }
}
```

`refreshAsync` 完成处（在 `self.displays = detectedDisplays` 之后）加：

```swift
self.mediaKeyController.refresh()
```

import 加 `import Combine`。

- [ ] **Step 13.2：在 DisplayControlsSection.body 调用 attach**

修改 `DisplayControlsSection`（第 7 行起）的 `onAppear`：

```swift
.onAppear {
    controller.attach(settings: settings)
    controller.refreshAsync()
}
```

确保 `attach` 是幂等的（重复 attach 不会重复创建 EventTap）。`MediaKeyController.attach` 当前实现会覆盖，OK。

- [ ] **Step 13.3：构建确认通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

- [ ] **Step 13.4：commit**

```bash
git add HagimiMonitorDirectOnly/DisplayControlsSection.swift
git commit -m "[新增] 将 MediaKeyController 接入 DisplayControlController 并响应设置变化"
```

---

## Task 14：本地化字符串

**Files:**
- Modify: `HagimiMonitor/Localizable.xcstrings`

- [ ] **Step 14.1：添加 mediaKey.* 字符串**

在 `HagimiMonitor/Localizable.xcstrings` 中添加以下 key（每个 key 都需 `zh-Hans` 和 `en` 两个翻译）：

| Key | zh-Hans | en |
|---|---|---|
| `mediaKey.section-title` | 媒体键接管 | Media Key Takeover |
| `mediaKey.brightness-toggle` | 接管亮度键（F1/F2） | Take over Brightness Keys (F1/F2) |
| `mediaKey.volume-toggle` | 接管音量键（F10/F11/F12） | Take over Volume Keys (F10/F11/F12) |
| `mediaKey.permission-required` | 需要"辅助功能"权限 | Accessibility Permission Required |
| `mediaKey.permission-explanation` | 仅用于拦截亮度/音量按键事件，不会读取键盘输入或其他按键。 | Used only to intercept brightness/volume key events. Other keystrokes are not read. |
| `mediaKey.open-system-settings` | 打开系统设置 | Open System Settings |
| `mediaKey.refresh-permission` | 刷新权限状态 | Refresh Permission |
| `mediaKey.status-authorized` | 已授权 | Authorized |
| `mediaKey.status-not-authorized` | 未授权 | Not Authorized |
| `mediaKey.show-osd` | 显示原生 OSD 提示 | Show Native OSD |
| `mediaKey.fine-scale-brightness` | 亮度键反向使用 Shift+Option 切换标准步进 | Invert Shift+Option for fine brightness step |
| `mediaKey.fine-scale-volume` | 音量键反向使用 Shift+Option 切换标准步进 | Invert Shift+Option for fine volume step |

由于 xcstrings 是 JSON 格式，直接 Xcode 中编辑（双击文件用 Xcode 字符串目录编辑器）。或者命令行追加：用 Xcode 打开后保存生成 xcstrings 文件。

- [ ] **Step 14.2：构建确认资源通过**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。Xcode 不会因为新增 string 报警告。

- [ ] **Step 14.3：commit**

```bash
git add HagimiMonitor/Localizable.xcstrings
git commit -m "[新增] 媒体键设置相关本地化字符串（中英）"
```

---

## Task 15：MediaKeySettingsSection 设置 UI

**Files:**
- Create: `HagimiMonitorDirectOnly/MediaKeySettingsSection.swift`
- Modify: `HagimiMonitor/Views/Settings/ModuleSettingsView.swift`（在 `.display` kind 时插入）

- [ ] **Step 15.1：实现 MediaKeySettingsSection**

新建 `HagimiMonitorDirectOnly/MediaKeySettingsSection.swift`：

```swift
import SwiftUI

struct MediaKeySettingsSection: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var permission: AccessibilityPermissionService

    var body: some View {
        SettingsGroup(String(localized: "mediaKey.section-title")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $settings.mediaKeyBrightnessEnabled) {
                    Text(String(localized: "mediaKey.brightness-toggle"))
                }
                Toggle(isOn: $settings.mediaKeyVolumeEnabled) {
                    Text(String(localized: "mediaKey.volume-toggle"))
                }

                if settings.mediaKeyBrightnessEnabled || settings.mediaKeyVolumeEnabled {
                    Divider()
                    permissionBlock
                    Divider()
                    optionsBlock
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var permissionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: permission.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permission.isTrusted ? .green : .orange)
                Text(permission.isTrusted
                     ? String(localized: "mediaKey.status-authorized")
                     : String(localized: "mediaKey.status-not-authorized"))
                    .font(.callout.weight(.semibold))
            }

            if !permission.isTrusted {
                Text(String(localized: "mediaKey.permission-required"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "mediaKey.permission-explanation"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(String(localized: "mediaKey.open-system-settings")) {
                    permission.request()
                }
                Button(String(localized: "mediaKey.refresh-permission")) {
                    permission.refresh()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var optionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.mediaKeyShowOSD) {
                Text(String(localized: "mediaKey.show-osd"))
            }
            Toggle(isOn: $settings.mediaKeyFineScaleBrightness) {
                Text(String(localized: "mediaKey.fine-scale-brightness"))
            }
            Toggle(isOn: $settings.mediaKeyFineScaleVolume) {
                Text(String(localized: "mediaKey.fine-scale-volume"))
            }
        }
    }
}
```

- [ ] **Step 15.2：在 ModuleSettingsView 集成**

修改 `HagimiMonitor/Views/Settings/ModuleSettingsView.swift`：

确认 `kind == .display` 时显示，并在合适位置（metrics 之后）追加：

```swift
#if DISPLAY_CONTROL
if kind == .display {
    MediaKeySettingsSection(
        settings: settings,
        permission: AccessibilityPermissionService.shared
    )
}
#endif
```

由于 `MediaKeySettingsSection` 持有的 `permission` 需要稳定实例，加 `static let shared` 或将 permission 注入为外部依赖。本计划采用：

修改 `HagimiMonitorDirectOnly/AccessibilityPermissionService.swift`，类内顶部加：

```swift
@MainActor static let shared = AccessibilityPermissionService()
```

并相应让 `DisplayControlController` 也使用 `AccessibilityPermissionService.shared` 而不是自己 `init()`：

```swift
let permission = AccessibilityPermissionService.shared
```

- [ ] **Step 15.3：构建确认通过 + 人工验证**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build
```

期望：BUILD SUCCEEDED。

人工验证：
- 启动 App → 打开设置 → 显示模块（或对应位置）
- 看到"媒体键接管" section
- 默认两个开关全部 off
- 拨开"接管亮度键"开关 → 出现权限引导块，"未授权"红橙
- 点"打开系统设置" → 跳转到 系统设置 → 隐私与安全性 → 辅助功能
- 在系统设置中授权后，回到 App → 状态自动变绿"已授权"
- 在外接屏上按 F2 → 屏幕亮度变化 + 出现原生 OSD

- [ ] **Step 15.4：commit**

```bash
git add HagimiMonitorDirectOnly/MediaKeySettingsSection.swift \
        HagimiMonitorDirectOnly/AccessibilityPermissionService.swift \
        HagimiMonitor/Views/Settings/ModuleSettingsView.swift
git commit -m "[新增] 设置页接管亮度/音量键的开关与授权引导"
```

---

## Task 16：完整端到端验证

**Files:** 无代码改动

- [ ] **Step 16.1：跑全部测试**

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug test
```

期望：所有测试 passed，包括新增的 `DDCRawConversionTests`、`DDCFaultRegistryTests` 与既有的 `SettingsTests` / `UpdateCheckerTests` / `MetricFlowPlacerTests`。

- [ ] **Step 16.2：人工兼容性回归**

按 spec §3 兼容性矩阵清点：

- [ ] USB-C / DP 直连屏：亮度/音量/对比度滑块工作
- [ ] 长时间拖动滑块：CPU / 屏幕反应正常，无卡顿
- [ ] 媒体键关闭：F2 等键走系统默认行为
- [ ] 媒体键开启 + 已授权 + 外接屏：F1/F2 调亮度有 OSD
- [ ] 媒体键开启 + 未授权：UI 显示未授权，按 F2 走系统行为
- [ ] 拔插显示器：panel 自动刷新
- [ ] 系统休眠唤醒：DDC 正常恢复
- [ ] 故意把显示器 DDC 设置关闭（在显示器 OSD 菜单里）：连续 5 次失败后 panel 滑块灰掉

- [ ] **Step 16.3：清理与最终 commit（如有遗漏）**

```bash
git status
```

如有未提交内容评估是否合并入合适的 task commit；否则单独 commit。

---

## Self-Review Notes

**Spec coverage（逐节核对）：**

- §5.1 移除 maxDetectLimit → Task 1
- §5.2 全局串行队列 + 去重 → Task 4
- §5.3 DDCFaultRegistry → Task 2
- §5.4 DisplayClassifier → Task 3
- §5.5 DisplayServices 外接 Apple 原生屏 → Task 3
- §5.6 监听重配置/唤醒 → Task 6
- §5.7 音量/静音序列 → Task 5
- §5.8 capability probe 拆分 → Task 7
- §5.9 媒体键接管 → Task 9-15（拆 7 步）
- §5.10 percent ↔ raw 转换 → Task 1
- §6 数据流：Task 4 + Task 2 写入路径接入
- §7 测试：Task 1-2 单测；Task 16 集成验证

**实施顺序对应 spec §9：**

1 → Task 1，2 → Task 2，3 → Task 3，4 → Task 4，5 → Task 5，6 → Task 6，7 → Task 7，8 → Task 8-15（媒体键），9 → Task 14（本地化）。

**未提供的本地化字符串清单：**`display.*` 系列 spec §9 提到，但当前代码里 `display.no-controls`、`display.no-displays`、`display.no-external-displays`、`display.built-in-display`、`display.external-display` 已存在。本次无需新增 `display.*`；仅加 `mediaKey.*`。

**关键不变量（reviewer 检查）：**

- `AXIsProcessTrustedWithOptions(prompt: true)` 仅出现在 `AccessibilityPermissionService.request()` 内，不在 init / start / refresh 路径
- `MediaKeyTapBridge.start` 失败不抛错也不弹窗，只 log
- 默认值：`mediaKeyBrightnessEnabled = false`、`mediaKeyVolumeEnabled = false`
- 所有媒体键代码包在 `HagimiMonitorDirectOnly/`，App Store target 不会编译它们

**未在本计划范围内（明确不做）：**

- 鼠标滚轮 / 屏幕边缘滚动调亮度
- 自定义全局快捷键
- 输入源切换 / KVM
- DisplayLink 软件 dimming
- M1/M2 内建 HDMI 突破
- per-display 高级设置 UI（curve / invert / remap）
