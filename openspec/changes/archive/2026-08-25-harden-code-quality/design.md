## Context

本变更来自一次全局代码审查,而非新功能。为便于后续追溯,这里保留完整发现清单、优先级判定依据,以及少数「审查后决定不改」项的理由。审查覆盖:`Samplers/`、`Top*Process.swift`、`MonitorModels.swift`、`SystemMonitorSampler.swift`、`HagimiMonitorApp.swift`、`AppDelegate.swift`、`Views/`(含 `MonitorPanelView.swift` 与两个面板控制器)。

## 发现清单与优先级

| 编号 | 位置 | 问题 | 严重度 | 档位 |
| --- | --- | --- | --- | --- |
| F1 | `MonitorModels.swift` `refreshProcesses` | 注释称「并行」,实为串行队列;磁盘/网络全局快照字典无锁,靠串行保证安全 | 中 | P0 |
| F3 | `Samplers/SMC.swift` `parseValue` | `flt` 分支在 `[UInt8]` 上做对齐 `load(as: Float)`,对齐未定义行为 | 低 | P0 |
| F4 | `Samplers/NetworkSampler.swift` `sample` | 计数器回绕/接口切换时速率可能瞬时爆假峰 | 低 | P0 |
| F8 | `MonitorPanelView.swift` `parseExternalVolumes` | 每次新建 `JSONDecoder` | 低 | P0 |
| F9 | `MonitorPanelView.swift` | `InlineDiskProcessList` / `InlineNetworkProcessList` 为 internal,风格不一致 | 低 | P0 |
| F7 | `MenuBarStatusLabel.swift` | 每次 body 重建 NSFont 并测量固定保留字 | 中 | P1 |
| F5 | `SamplingError.swift` | `ioKitError` case 疑似未使用 | 极低 | P1 |
| F2 | `MonitorModels.swift` `MonitorStore` | 未标注 `@MainActor`,主线程不变式无编译期保证 | 低 | P2 |
| F6 | `MonitorPanelView.swift` `init` | `@ObservedObject` 包裹视图内创建的 `QuickPanelPresentation` | 中 | P2 |
| F10/F11 | 面板控制器 | `MainActor.assumeIsolated` 依赖运行期主线程投递 | 低(可接受) | 不改 |

## 关键设计点:进程采样的串行不变式(F1)

`MonitorStore.procSampleQueue` 是 `DispatchQueue(label:)`(串行)。四类 TOP 采样通过 `DispatchGroup` + `procSampleQueue.async` 提交,实际**顺序执行**而非并行。这一串行性是正确性依赖,而不仅是性能取舍:

- `TopDiskProcess.swift` 的 `previousDiskSnapshot`、`TopNetworkProcess.swift` 的 `previousNetworkSnapshot` 均为**文件级全局可变字典、无锁**,用于计算两次采样间的增量。
- 只有在单一串行队列上顺序读改,它们才不会数据竞争。`prewarmProcessBaselines` 也派发到同一队列,故一致。

因此 F1 的修复不是「让它真并行」,而是**修正注释使其反映串行事实,并显式记录串行是快照安全的前提**,防止后续有人据旧注释把队列改成 `.concurrent` 而引入难复现的数据竞争。若将来确需并行化,必须先把两份快照封装进各自采样器实例并加同步。

## P0 实现要点

- **F4**:参照磁盘采样口径,`upload`/`download` 用「当前 < 上次则视为 0」的保护,避免 `&-` 回绕出的巨值(虽被 `min(100,…)` 截断为满格,仍是可感知的假峰)。
- **F3**:`byteArray.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Float.self) }`,语义不变、消除对齐 UB。
- **F8**:文件级 `private let sharedVolumeDecoder = JSONDecoder()`,`JSONDecoder` 默认无跨解码状态,可安全复用。
- **F9**:仅改访问修饰符,无行为变化。

## 不改项的理由

- **`mach_host_self()` 泄漏(CPU/MemorySampler)**:已用 stored property 缓存,进程内仅取一次,属可接受的一次性 send-right 泄漏;现有注释已准确说明,无需改动。
- **F10/F11 `MainActor.assumeIsolated`**:`NSEvent` 全局监听回调与 `NSWindowDelegate` 方法由 AppKit 保证主线程投递,该写法是 Swift 6 下的标准手法;改成 `DispatchQueue.main.async` 反而引入一帧延迟,得不偿失。保持现状。

## 风险与协调

- `MenuBarStatusLabel.swift` 存在**未提交的在途改动**(菜单栏指标单元统一左对齐,非本次审查产物)。F7(P1)与其区域重叠,必须在该改动落定后再动,避免冲突。本次 P0 不触碰该文件。
- P0 全部为局部、低风险修改;P2(F2/F6)改动面较大,应各自独立提交并单独回归。
