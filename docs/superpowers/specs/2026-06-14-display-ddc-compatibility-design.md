# Display DDC/CI 兼容性升级设计

- 日期：2026-06-14
- 范围：`HagimiMonitorDirectOnly/`（Direct build，仅 Apple Silicon）
- 关联代码：`DisplayDDCBridge.swift`、`DisplayControlsSection.swift`、`DisplayBridgingHeader.h`
- 不涉及：App Store target、Intel Mac

## 1. 背景与问题

当前 Direct build 已实现基础 DDC/CI：`DisplayDDCBridge.swift` 用 `IOAVServiceReadI2C/WriteI2C` 走 `DCPAVServiceProxy`，service matching 算法直接抄自 MonitorControl `Arm64DDC.swift`。`DisplayControlsSection.swift` 提供 SwiftUI 滑块、`@MainActor` controller、150ms debounce 写入。

用户反馈兼容性不好，调研后定位到以下问题（按影响排序）：

1. **`maxDetectLimit = 100` 钳制最大值**：很多显示器返回的 max 是 255 或厂商专有值；强制裁到 100 后写入比例失真，"亮度调到 100% 但屏幕仍偏暗"。
2. **没有全局串行队列**：当前 `DisplayControlWorker.queue` 是单进程级 serial queue + per-key debounce，但**多个显示器、多个 control 仍可能并发提交 DDC**。MonitorControl 用 `globalDDCQueue` 全局串行，避免 I2C 总线/IOAVService 多路同时调用。
3. **没有 fault counter**：失败的 control 一直重试，UI 上滑块仍可拖动。Lunar 模式：连续失败 N 次后标记 unavailable，UI 灰掉、不再下发。
4. **虚拟屏过滤不足**：只过滤 `CGDisplayIsBuiltin`，未排除 DisplayLink / AirPlay / Sidecar / dummy。这些屏会进入 ioreg 匹配流程，`hasDDCService` 可能误判，写入必然失败。
5. **没有 DisplayServices 路径用于外接 Apple 原生屏**：Studio Display / LG UltraFine 这类支持 native brightness 的外接屏，应优先走 `DisplayServicesSetBrightness` 而非 DDC。当前内建屏走了，外接屏没走。
6. **没有显式的 capability probe**：现状是首次 read 失败才标记不支持。多个 control 并行 probe 会被 retry 拖慢 UI 启动。
7. **没有 longerDelay / 慢屏适配**：某些扩展坞、Thunderbolt 桥接需要 read 前 sleep 100ms+。当前固定 50ms。
8. **音量/静音序列**：当前 write volume 时先写 mute=2 再写 volume，部分显示器对此序列敏感；MonitorControl 是 mute 独立路径、volume 写之前不主动 unmute。
9. **没有显示重配置/唤醒回调**：热插拔、休眠唤醒后 ioreg 变化，当前只在 `onAppear` refresh 一次。

## 2. 目标

**做**：

- 修复钳制 max 导致的精度丢失
- 加全局串行队列 + last-value 去重
- 加 per-display per-control fault counter + 自动 disable
- 显示器枚举阶段过滤虚拟屏 / dummy
- 外接 Apple 原生屏走 DisplayServices
- 监听显示重配置和系统唤醒，自动 refresh
- 调整音量/静音写入序列
- 失败 N 次后自动启用 longer delay
- **接管系统亮度/音量/静音媒体键**，外接屏上按 F1/F2/F11/F12/Mute 直接走 DDC + 显示原生 OSD（参考 MonitorControl `MediaKeyTapManager`）

**不做**（YAGNI）：

- per-display 用户可见的高级设置 UI（curveDDC / invertDDC / remapDDC / pollingMode / minDDCOverride / maxDDCOverride）—— 内部数据结构留位但不做 UI，等用户真要时再加
- Intel 路线（已 `#error`，不动）
- 输入源切换、PBP/KVM、色彩增益
- DisplayLink 软件 dimming（非 DDC，是另一个独立特性）
- M1/M2 内建 HDMI 黑魔法（BetterDisplay 闭源，无开源参考）

## 3. 兼容性边界（明确告知用户）

| 场景 | 状态 |
|---|---|
| Apple Silicon + USB-C/DP/Thunderbolt 直连 | 主要支持目标 |
| Apple Silicon + HDMI 直连（非内建 HDMI 端口） | 实验性，按 capability probe 结果 |
| Apple Silicon Mac 内建 HDMI 端口 | 不支持（开源方案均无解）|
| Apple 原生外接屏（Studio Display 等） | 走 DisplayServices，硬件原生 |
| 扩展坞 / 转接器 | 取决于是否透传 DDC，自动 probe |
| DisplayLink / AirPlay / Sidecar / 虚拟屏 | 显式过滤，不显示控制 |
| MST / 菊花链 | 实验性，可能只有部分屏可控 |
| Intel Mac | 不支持（已 `#error`）|

不可控时 UI 显示降级提示，不阻塞，不让用户以为是 App bug。

## 4. 架构

### 4.1 现状

```
DisplayControlsSection (SwiftUI)
  └─ DisplayControlController (@MainActor, ObservableObject)
       └─ DisplayControlWorker (serial queue + per-key debounce)
            └─ DisplayControlService
                 ├─ DisplayServicesBridge   (内建屏)
                 └─ DisplayDDCBridge         (外接 DDC)
                      └─ Arm64DDCMatcher / DDCTransport
```

### 4.2 目标

```
DisplayControlsSection (SwiftUI)
  └─ DisplayControlController (@MainActor)
       ├─ DisplayChangeObserver  (新)  —— 监听 CGDisplayReconfiguration + workspace.didWake
       └─ DisplayControlWorker
            └─ DisplayControlService
                 ├─ DisplayServicesBridge        —— 内建屏 + 外接 Apple 原生屏
                 ├─ DisplayDDCBridge             —— 外接第三方屏
                 │    ├─ Arm64DDCMatcher
                 │    ├─ DDCTransport
                 │    └─ DDCFaultRegistry  (新)  —— per-display per-control fault counter
                 └─ DisplayClassifier      (新)  —— 虚拟屏 / dummy / Apple native 分类
            └─ globalDDCQueue        (新)        —— 跨 service 全局串行
            └─ writeNextValue / writeLastValue (新) —— last-value 去重
```

### 4.3 关键决策

**保留现有 debounce + serial queue 结构**。它已基本对齐 MonitorControl `OtherDisplay.writeDDCQueue` 的语义。补的是：（a）跨实例的全局串行，（b）last-value 去重，（c）显式 fault tracking。

**不引入 SwiftPM 子包**。直接在 `HagimiMonitorDirectOnly/` 下扩展现有文件，新建 `DDCFaultRegistry.swift`、`DisplayClassifier.swift`、`DisplayChangeObserver.swift`。保持模块简单，便于 `DISPLAY_CONTROL` 编译条件统一管理。

**fault threshold 定为读 5 次、写 10 次**（Lunar 是 10/20）。菜单栏工具用户对响应敏感，更激进降级。

## 5. 详细设计

### 5.1 移除 maxDetectLimit，按真实 max 写入

**当前**（`DisplayDDCBridge.swift:16,40-45`）：

```swift
private let maxDetectLimit: UInt16 = 100
let effectiveMax = min(values.max, maxDetectLimit)
let effectiveCurrent = min(values.current, effectiveMax)
```

**改为**：直接用 `values.max`，但若 `max < 1` 视为读失败。写入时 `ddcValue = round(percent / 100 * actualMax)`。

风险点：少量显示器返回异常大的 max（如 65535），需保留一个**合理上限**避免溢出。建议 `clampedMax = max(1, min(values.max, 32767))`。

**仍然保留 percent 概念**给 UI（0–100），底层按 percent ↔ DDC raw 双向转换。这样 `DisplayServices` 路径（用 0..1 float）和 DDC 路径可以共用 SwiftUI Slider。

### 5.2 全局串行队列 + last-value 去重

**当前**（`DisplayControlsSection.swift:393-427`）：

```swift
private let queue = DispatchQueue(label: "hagimi.ddc", qos: .userInitiated)
private var pendingWrites: [ControlKey: Double] = [:]
private var debounceTimers: [ControlKey: DispatchWorkItem] = [:]
```

`pendingWrites` 已有去重，`queue` 单例 serial，看似够。**问题**：`refresh()` 也用同一个 queue 跑 `service.displays()`（其中包含三次 DDC read），与 `setValue` 写并发时会自我串行——OK；但如果未来 read 周期化，read 期间 write 会被延后到 read 队尾。

**改动**：

1. 把 DDC **读操作**也走全局串行（当前 read 在 `service.displays()` 里，已经走 worker queue，不变）。
2. 引入 `writeLastSavedValue: [ControlKey: Double]` 在 service 层。debounce timer 触发时，若 `pendingValue == lastSavedValue` 直接跳过，不发 DDC，提升手感。
3. `DisplayServicesBridge` 写入也走同一 queue —— 防止并发 DDC + DisplayServices 互相干扰（虽然不同 API，但 framebuffer 状态有相关）。

### 5.3 DDCFaultRegistry

**新文件** `HagimiMonitorDirectOnly/DDCFaultRegistry.swift`：

```swift
final class DDCFaultRegistry {
    struct State { var readFaults: Int; var writeFaults: Int; var disabled: Bool }
    private var states: [ControlKey: State] = [:]
    
    func recordReadFailure(_ key: ControlKey)   // ++readFaults; if >= 5 → disabled = true
    func recordReadSuccess(_ key: ControlKey)   // readFaults = max(0, --readFaults)
    func recordWriteFailure(_ key: ControlKey)  // ++writeFaults; if >= 10 → disabled = true
    func recordWriteSuccess(_ key: ControlKey)  // writeFaults = max(0, --writeFaults)
    func isDisabled(_ key: ControlKey) -> Bool
    func reset(displayID: CGDirectDisplayID)    // 显示器重连时清空
}
```

**接入点**：
- `DisplayDDCBridge.read/write` 在 return 前调 `recordReadFailure / recordReadSuccess`
- 入口 `DisplayDDCBridge.read/write` 先 `if registry.isDisabled(key) { return nil/false }`
- `DisplayControlController.handleWriteResult` 失败时 → `markControlUnsupported`（已有）；这里逻辑要从"单次失败就标记 unsupported"改为"由 fault registry 决定"

**threshold 来源**：Lunar 用 read 10 / write 20，本项目更激进取 5 / 10（菜单栏体验优先）。

**降级到 longerDelay**：连续读失败 ≥ 3 次但还没到 5 次时，`DDCTransport` 内部把下一次 `readSleepTime` 从 50ms 提到 150ms。这是借鉴 MonitorControl `longerDelay` 的自动启用版本。

### 5.4 DisplayClassifier

**新文件** `HagimiMonitorDirectOnly/DisplayClassifier.swift`：

```swift
enum DisplayKind {
    case builtIn
    case appleNative      // DisplayServices 可控的外接屏
    case externalDDC      // 走 DDC
    case virtual          // DisplayLink / AirPlay / Sidecar
    case dummy
    case unsupported
}

struct DisplayClassifier {
    func classify(displayID: CGDirectDisplayID) -> DisplayKind
}
```

**判定逻辑**（按 MonitorControl `DisplayManager.isVirtual / isDummy` + DisplayServices 探测）：

1. `CGDisplayIsBuiltin(id) != 0` → `.builtIn`
2. CoreDisplay info 里 `kCGDisplayIsVirtualDevice == true` 或 `kCGDisplayIsAirPlay == true` → `.virtual`
3. raw name 包含 "dummy" 或 vendor == 0xF0F0 → `.dummy`
4. `DisplayServicesGetBrightness` 返回 success（外接 Apple 原生屏）→ `.appleNative`
5. 默认 → `.externalDDC`（再由 DDC matcher 决定是否真有 service）

`virtual` / `dummy` / `unsupported` 直接不显示控制；`appleNative` 走 DisplayServices；`externalDDC` 走 DDC。

### 5.5 DisplayServices 覆盖外接 Apple 原生屏

**当前**（`DisplayControlsSection.swift:547,584-589`）：

```swift
let appleBrightness = isBuiltIn ? displayServices.getBrightness(displayID: id) : nil
// 只有 isBuiltIn 才走 DisplayServices
```

**改**：用 `DisplayClassifier.classify` 替代 `isBuiltIn` 判断。`.builtIn` 和 `.appleNative` 都走 `DisplayServicesBridge`。`.appleNative` 通常也支持 DDC，但优先 DisplayServices（更稳、原生）。

### 5.6 监听重配置 / 唤醒

**新文件** `HagimiMonitorDirectOnly/DisplayChangeObserver.swift`：

```swift
@MainActor
final class DisplayChangeObserver {
    private var callback: (() -> Void)?
    
    func start(onChange: @escaping () -> Void) {
        // CGDisplayRegisterReconfigurationCallback
        // NSWorkspace.shared.notificationCenter.addObserver for didWakeNotification
    }
    func stop()
}
```

**接入**：`DisplayControlController` 在 init 时 start，触发时调 `refreshAsync()`。debounce 1 秒（重配置回调会连发多次）。

### 5.7 音量/静音序列调整

**当前**（`DisplayDDCBridge.swift:70-81`）：volume>0 时先写 mute=2，再写 volume；volume=0 时只写 mute=1。

**问题**：写 mute=2 后立刻写 volume，部分显示器忽略 volume；MonitorControl 是 volume 写时不主动 unmute，让显示器自己处理。

**改为**：
- `value > 0`：只写 volume VCP `0x62`，不主动 unmute
- `value == 0`：写 mute VCP `0x8D = 1`，不写 volume
- 提供独立 mute toggle 入口（未来扩展），现阶段不做 UI

### 5.8 capability probe

**当前**：`displays()` 同步执行 brightness / volume / contrast 三次 read，UI 启动卡顿（每次 read 失败有 5 轮 × 80ms ≈ 400ms 重试，三个 control × 多个 display 累加可观）。

**改**：

1. 启动 probe 只读 brightness 一次（最关键），volume / contrast 标记为 "未 probe"
2. `value()` 首次访问 volume / contrast 时再 lazy probe
3. probe 失败的 control 进 fault registry，下一次 refresh 不再 probe
4. probe 期间 retry 次数从 5 降到 2（快速失败）

读 retry 区分两个上下文：
- **probe / 周期 read**：少 retry（2 次）
- **写后立即 read（如果有）**：多 retry（5 次）

实际上当前代码不做"写后立即 read"，所以全部用低 retry 即可。

### 5.9 媒体键接管（亮度 / 音量 / 静音）

#### 5.9.1 用户体验目标

外接屏接入时，按 F1/F2 调亮度、F10/F11/F12 调音量/静音，效果应当：

- 调用对应屏的 DDC（`brightness` / `audioSpeakerVolume` / `audioMuteScreenBlank`）
- 触发 macOS 原生 OSD（小亮度方块或音量方块），位置跟随当前控制的屏
- 长按连发，节奏接近系统行为
- 修饰键支持（与 MonitorControl 一致）：
  - `Shift + Option`：精细步进（小步长，约 1/4 步）
  - 无修饰键：标准步进（1/16 步）
  - `Option`（仅按一次）：直接打开"显示器/声音"系统设置面板
- 内建屏可见时，亮度键不接管（让系统原生处理 MacBook 内建亮度）；外接屏可见时再接管
- 如果默认音频输出设备本身可控（蓝牙耳机、AirPods、外接 USB 音响），音量键**不接管**，由系统处理；只有"音频走外接屏喇叭、且系统认为不可控"时接管

#### 5.9.2 技术方案

参考 MonitorControl 用第三方 SPM 包 `MonitorControl/MediaKeyTap`（fork 自 `the0neyouseek/MediaKeyTap`），底层是 `CGEvent.tapCreate` + `kCGEventTapOptionDefault` 全局事件拦截，过滤 `NX_SYSDEFINED` 系统事件中的 `NX_SUBTYPE_AUX_CONTROL_BUTTONS`（亮度/音量/静音/Eject 等）。

**两种实现路径选择**：

| 方案 | 描述 | 评价 |
|---|---|---|
| A. 引入 `MediaKeyTap` SPM 依赖 | 直接复用 MonitorControl 同款 | 最快、行为对齐；但增加 SPM 依赖、包不在 Apple Silicon 现代化的活跃度 |
| B. 自实现一个轻量 MediaKeyTap | 自己写 `CGEventTap` + `NX_SYSDEFINED` 解析 | 代码量约 150-200 行；可控；不增加外部依赖；与现有 `HagimiMonitorDirectOnly` 风格一致 |

**选 B**。MediaKeyTap 包核心逻辑很短（解析 NSEvent.subtype == 14 的 systemDefined event，提取 keyCode），自己写一份避免引入维护断档的依赖，也方便加自定义行为（如指示当前控制屏）。

#### 5.9.3 架构

```
MediaKeyTapBridge  (新, HagimiMonitorDirectOnly/MediaKeyTapBridge.swift)
  ├─ start() / stop()
  ├─ CGEventTap @ kCGSessionEventTap
  ├─ 过滤 NX_SYSDEFINED + NX_SUBTYPE_AUX_CONTROL_BUTTONS
  ├─ 解析 keyCode → MediaKey enum {brightnessUp, brightnessDown, volumeUp, volumeDown, mute}
  ├─ 区分 keyDown / keyRepeat / keyUp
  └─ delegate.handle(mediaKey, isPressed, isRepeat, modifiers)
       ↓
DisplayControlController.handleMediaKey  (新)
  ├─ 选目标屏（policy 见下）
  ├─ 计算新 percent（标准 1/16 / 精细 1/64）
  ├─ 调 service.setValue (走现有 DDC 路径)
  └─ OSDDisplayClient (新, 私有 API) → 显示原生 OSD
```

#### 5.9.4 目标屏选择策略

- **亮度键**：所有外接 DDC 屏全部跟随调（MonitorControl 默认行为）。仅当无外接屏时不接管。
- **音量键**：选当前主输出音频设备所在的屏；如果无法识别，则走所有外接屏。
- 用户后续可加偏好开关：仅控制鼠标所在屏 / 仅控制主屏。**初期不做这个开关**（YAGNI），默认全部跟随。

#### 5.9.5 OSD 显示

macOS 私有 framework：`/System/Library/PrivateFrameworks/OSD.framework`

```objc
// MonitorControl Bridging-Header.h 引用方式
@interface OSDManager : NSObject
+ (id)sharedManager;
- (void)showImage:(long long)image onDisplayID:(unsigned int)displayID priority:(unsigned int)priority msecUntilFade:(unsigned int)msec filledChiclets:(unsigned int)filled totalChiclets:(unsigned int)total locked:(BOOL)locked;
@end
```

常用 image 常量：

- 亮度：`1`（brightness）
- 音量：`3`（speaker）
- 音量静音：`4`（speaker muted）

**实现**：新建 `OSDBridge.swift`，包私有 API 调用，仅在 `DISPLAY_CONTROL` 编译条件下纳入。失败回退到不显示 OSD（不阻塞主功能）。

**风险**：macOS Tahoe 26 已知 issue（MonitorControl `#1831`）—— Control Center OSD 出现但百分比不更新。这是系统级问题，开源工具均无解。降级方案：在 OSD 失败时打 log，不影响 DDC 写入。

#### 5.9.6 修饰键处理

```swift
let isShift = modifiers.contains(.shift)
let isOption = modifiers.contains(.option)
let isFine = isShift && isOption
let stepStandard = 1.0 / 16.0   // 6.25%
let stepFine     = 1.0 / 64.0   // 1.5625%
let step = (isFine ? stepFine : stepStandard) * 100
```

`Option` 单独按下且非 repeat → 打开系统设置（亮度键 → 显示器；音量键 → 声音）。

#### 5.9.7 长按连发

CGEventTap 的 systemDefined event 自带 keyRepeat 标志（`NSEvent.data1 & 0x1`）。直接读用即可，无需自己起 timer。但需要在 `keyDown` 触发一次、`keyRepeat` 持续触发、`keyUp` 不触发。

#### 5.9.8 权限策略与默认行为

**核心原则**：媒体键接管**默认关闭**，避免 App 启动就索要 Accessibility 权限造成困扰。用户在设置页主动开启时，引导授权。

权限层级：

```
[设置页 → 显示控制 → 媒体键接管]
  默认关闭
  ↓ 用户拨开 toggle
  检查 Accessibility 权限
    ├─ 已授权 → 直接启动 EventTap
    └─ 未授权 → 弹引导卡片（不强弹系统对话框）
         ├─ 文案说明：为什么需要、做什么、不做什么
         ├─ "打开系统设置"按钮 → 跳转到 隐私与安全性 → 辅助功能
         └─ "刷新权限"按钮 → 重新检查
  ↓ 用户在系统设置里授权
  通过 NSDistributedNotificationCenter 监听 com.apple.accessibility.api
  ↓ 自动检测到授权
  启动 EventTap，UI 显示绿色"已激活"
```

权限检查 API：

```swift
// 静默检查（不弹系统对话框）
let isTrusted = AXIsProcessTrusted()

// 主动请求（弹系统对话框，仅在用户点击"获取权限"按钮时使用）
let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
let granted = AXIsProcessTrustedWithOptions(options)
```

**设置页 UI 草图**（功能需求，非最终视觉）：

```
┌─ 媒体键接管 ──────────────────────────────┐
│                                            │
│  [开关] 接管亮度键 (F1/F2)              ⚪  │
│  [开关] 接管音量键 (F10/F11/F12)        ⚪  │
│                                            │
│  ⚠️ 需要"辅助功能"权限                      │
│  说明：仅用于拦截亮度/音量按键事件，         │
│         不会读取键盘输入或其他按键。         │
│                                            │
│   [打开系统设置]    [刷新权限状态]           │
│                                            │
│  当前状态：未授权 / 已授权（绿色）           │
│                                            │
│  ─────────────────────────────────         │
│  □ 显示原生 OSD                            │
│  □ 用 Shift+Option 切换为标准步进           │
│                                            │
└────────────────────────────────────────────┘
```

**状态机**：

| `mediaKeyBrightnessEnabled` / `mediaKeyVolumeEnabled` | Accessibility 已授权 | EventTap 状态 |
|---|---|---|
| 全部 false（默认） | 任意 | 不创建 |
| 任一 true | true | 创建并运行 |
| 任一 true | false | 不创建，UI 显示"未授权"提示 |

权限变化监听：

```swift
DistributedNotificationCenter.default().addObserver(
    forName: .init("com.apple.accessibility.api"),
    object: nil,
    queue: .main
) { _ in
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.refreshMediaKeyTapState()
    }
}
```

**关键不变量**：App 启动时**绝不**调用 `AXIsProcessTrustedWithOptions(prompt: true)`。仅当用户在设置页点"获取权限"按钮时才允许弹系统对话框。

#### 5.9.9 设置项

新增 `MonitorSettings`：

- `mediaKeyBrightnessEnabled: Bool`（**默认 false**）
- `mediaKeyVolumeEnabled: Bool`（**默认 false**）
- `mediaKeyFineScaleBrightness: Bool`（默认 false，反向使用 Shift+Option）
- `mediaKeyFineScaleVolume: Bool`（默认 false）
- `mediaKeyShowOSD: Bool`（默认 true）

UI 放在设置页"显示控制"分区下，独立子 section（见 5.9.8 草图）。section 内顺序：

1. 两个主开关（亮度 / 音量），打开任一个时显示权限引导
2. 权限引导 + 状态指示
3. 选项细化（OSD、精细步进）

**本地化字符串**（需新增到 `Localizable.xcstrings`）：

- `mediaKey.section-title`
- `mediaKey.brightness-toggle`
- `mediaKey.volume-toggle`
- `mediaKey.permission-required`
- `mediaKey.permission-explanation`（说明用途和隐私边界）
- `mediaKey.open-system-settings`
- `mediaKey.refresh-permission`
- `mediaKey.status-authorized`
- `mediaKey.status-not-authorized`
- `mediaKey.show-osd`
- `mediaKey.fine-scale-brightness`
- `mediaKey.fine-scale-volume`

#### 5.9.10 与现有 debounce / 队列的关系

媒体键事件本身不需要 debounce（用户敲一次只该走一次）。但要走**同一个 globalDDCQueue** 写入，避免与滑块拖动冲突。

媒体键写入的 percent 直接更新 `pendingValues`，UI 滑块同步动；OSD 由 `DisplayControlController.handleMediaKey` 触发，不依赖 debounce 完成。

#### 5.9.11 不在本节范围

- 自定义全局快捷键（`KeyboardShortcuts` 包，MonitorControl 也用）—— 后续可加
- 鼠标滚轮调亮度（PR #1867 提到，YAGNI）
- 屏幕边缘滚动调亮度（YAGNI）

### 5.10 percent ↔ DDC raw 转换

新 helper：

```swift
// percent: 0...100, max: 1...32767
static func ddcRaw(forPercent percent: Double, max: UInt16) -> UInt16 {
    let clamped = min(100, max(0, percent))
    return UInt16((clamped / 100 * Double(max)).rounded())
}
static func percent(forRaw raw: UInt16, max: UInt16) -> Double {
    guard max > 0 else { return 0 }
    return min(100, max(0, Double(raw) / Double(max) * 100))
}
```

`maxValues[key]` 字典从"钳到 100"改为"存 actualMax"。

## 6. 数据流（写入路径）

```
SwiftUI Slider drag
  ↓
DisplayControlController.setValueAsync(percent)
  ↓
pendingValues[displayID][control] = percent (UI 立即更新)
  ↓
DisplayControlWorker.setValue → debounce 150ms
  ↓
service.setValue(percent, control, display)
  ├─ classify → builtIn/appleNative → DisplayServicesBridge.set(percent/100)
  └─ classify → externalDDC →
        ↓
        globalDDCQueue.async {
          if writeLastValue == percent { return success }   // 去重
          if registry.isDisabled(key) { return fail }
          raw = ddcRaw(percent, maxValues[key])
          DDCTransport.write(...)
            ↓ 失败
            registry.recordWriteFailure
            (达到阈值 → disable)
            ↓ 成功
            registry.recordWriteSuccess
            writeLastValue = percent
        }
  ↓
handleWriteResult on @MainActor
  ├─ 成功 → 更新 displays[i]
  └─ 失败 → 若 registry.isDisabled → markControlUnsupported（UI 灰掉）
```

## 7. 测试

新增/扩展 `HagimiMonitorTests/`：

- `DDCFaultRegistryTests.swift`：阈值、reset、disable 状态机
- `DisplayClassifierTests.swift`：mock CoreDisplay info dict（可注入），覆盖 builtIn / virtual / airplay / dummy / appleNative / externalDDC
- `DDCRawConversionTests.swift`：percent ↔ raw 转换边界（0、100、max=1、max=255、max=65535）
- 集成测试：`DisplayDDCBridgeTests` 用 mock IOAVService（注入协议）验证 retry 计数和 fault 联动

`DisplayControlController` 现有 `@MainActor` 直接持有 service/worker，难单元测试。**保留现状**，不为测试改架构（YAGNI）。

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 私有 API 在 macOS 26 后续小版本失效 | 仍只在 Direct build；失败时 fault registry 标记 unsupported，UI 不崩 |
| `IOAVServiceCreateWithService` 在某些 service 上崩溃 | 现有 `Location == "External"` 过滤已避免内建端口 |
| 全局串行队列阻塞 UI | 队列在 `qos: .userInitiated` 后台，UI 走 pendingValues 乐观更新 |
| fault threshold 太激进，正常屏被误判 disabled | reset on display reconfigure；用户可手动重新连接屏幕复位 |
| capability probe 导致启动慢 | probe 只读 brightness；volume/contrast lazy；retry 降到 2 |
| **媒体键导致 App 启动就索权限** | **默认关闭**，仅用户在设置页主动开启时才检查/请求权限 |
| **Accessibility 权限被回收后媒体键失效** | 监听 `com.apple.accessibility.api` 通知，自动重启 EventTap；UI 实时显示授权状态 |
| **媒体键接管后某些键不工作（如音频走 AirPods）** | 选键策略与 MonitorControl 一致：默认输出设备可控时不接管音量键 |
| **App Store target 误编译** | 媒体键代码全部包在 `#if DISPLAY_CONTROL` 内，与 DDC 一致 |

## 9. 实施顺序建议

1. percent ↔ raw 转换 + 移除 `maxDetectLimit`（独立、可单测）
2. `DDCFaultRegistry` + 接入读写路径
3. `DisplayClassifier` + 替换 `isBuiltIn` 判断 + DisplayServices 覆盖外接 Apple 原生屏
4. 全局串行队列 + last-value 去重
5. 音量/静音序列调整
6. `DisplayChangeObserver` + 自动 refresh
7. capability probe 拆分（lazy volume/contrast、retry 降级）
8. **媒体键接管**：`MediaKeyTapBridge` + `OSDBridge` + 设置项（独立子模块，最后做）
9. 文案与本地化（`display.*` + `mediaKey.*` 新增）

每步独立可验证，可分多次提交。媒体键放最后，因为它依赖前面"DDC 写入路径稳定可靠"。

## 10. 不在本次范围内的后续工作

- per-display 用户可见高级设置（remap/curve/invert/min-max override）
- DisplayLink 软件 dimming overlay
- 输入源切换 / KVM 控制
- 自适应亮度（Lunar 卖点）
- App Store target 的软件 dimming 路径

## 11. 参考资料

- `docs/MonitorControl-main/MonitorControl/Support/Arm64DDC.swift` —— Apple Silicon DDC 主参考
- `docs/MonitorControl-main/MonitorControl/Model/OtherDisplay.swift` —— 写队列 / next-value 去重
- `docs/MonitorControl-main/MonitorControl/Support/DisplayManager.swift` —— isVirtual / isDummy
- `docs/MonitorControl-main/MonitorControl/Support/MediaKeyTapManager.swift` —— 媒体键接管主参考
- `docs/MonitorControl-main/MonitorControl/Support/AppDelegate.swift:148-186` —— `updateMediaKeyTap()` 选键策略
- `docs/MonitorControl-main/MonitorControl/Enums/PrefKey.swift` —— per-display 配置概念
- `docs/Lunar-main/Lunar/DDC/DDC.swift` —— fault counter / read-write timeout / skip property
- `docs/Lunar-main/Lunar/DDC/DDC.c` —— Intel I2C 重试参考
- `docs/Lunar-main/Lunar/Control/Control.swift` —— DisplayControl 抽象
- MediaKeyTap 包：https://github.com/MonitorControl/MediaKeyTap —— 媒体键 EventTap 实现参考（仅看不引）
- macOS `OSD.framework` —— MonitorControl Bridging-Header 中私有 API 声明
- m1ddc commit `f95a3472`（2026-06-07）—— Get-VCP max byte offset 修复，验证当前偏移正确
- MonitorControl PR `#1874`（2026-05-29）—— 并发与 DDC 可靠性修复，可借鉴
