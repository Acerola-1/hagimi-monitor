## Why

对 HagimiMonitor 主目标(`HagimiMonitor/` 与 `HagimiMonitorDirectOnly/`)做了一次全局代码审查,重点覆盖采样层(`Samplers/`)、进程采样(`Top*Process.swift`)、数据模型(`MonitorModels.swift`)、应用入口(`HagimiMonitorApp` / `AppDelegate`)、系统采样(`SystemMonitorSampler`)与视图层(`Views/`、`MonitorPanelView`、面板控制器)。

整体结论:代码库成熟、注释信息价值高、已处理绝大多数 macOS 底层坑,**无会导致崩溃的严重缺陷**。发现的问题均为精修级别,按风险/收益分为 P0(安全无争议)、P1(有收益需验证)、P2(结构性重构)三档,统一在本变更中规划,分批落地。

## What Changes

### P0 — 安全无争议(本次落地)
- **F1**:`MonitorStore.refreshProcesses` 注释声称「并行执行」,但 `procSampleQueue` 是串行队列;且磁盘/网络的全局快照字典无锁,正确性恰恰依赖该串行性。修正注释为「串行」并注明串行是快照安全的前提,避免后续被误改为并发队列而引入数据竞争。
- **F4**:`NetworkSampler.sample` 的上下行速率对计数器回绕/主接口切换未做保护,可能瞬时爆出假峰。改为下降归零(与磁盘采样口径一致)。
- **F3**:`SMC.parseValue` 的 `flt` 分支用 `load(fromByteOffset:as:)` 从 `[UInt8]` 读 `Float`,存在 4 字节对齐的未定义行为隐患。改用 `loadUnaligned`。
- **F8**:`MonitorPanelView.parseExternalVolumes` 每次调用新建 `JSONDecoder`,改为 `static let` 共享实例。
- **F9**:`InlineDiskProcessList` / `InlineNetworkProcessList` 访问级别与同文件其余视图不一致(internal vs private),统一为 `private`。

### P1 — 有收益、需验证(后续)
- **F7**:`MenuBarStatusLabel` 每次 body 都重建 `NSFont` 并测量固定保留字宽度;按 `(kind, fontSize, style)` 静态缓存测量结果。需与在途的菜单栏单元对齐改动协调。
- **F5**:确认并移除疑似未使用的 `SamplingError.ioKitError` 枚举 case。

### P2 — 结构性重构(后续,分独立提交)
- **F2**:为 `MonitorStore` 添加 `@MainActor`,使「主线程访问」的隐含不变式获得编译期保证。
- **F6**:重构 `MonitorPanelView` 中 `QuickPanelPresentation` 的所有权,避免用 `@ObservedObject` 包裹视图 `init` 内创建的实例。

### 审查后确认无需改动
- `mach_host_self()` 端口不释放(CPUSampler/MemorySampler):已由「缓存、进程内只取一次」正确规避,注释准确。
- `MainActor.assumeIsolated`(F10/F11,面板控制器全局事件监听 / 窗口委托):Swift 6 常见写法,相关 API 文档承诺主线程投递,保持现状。
- 注释清理:主目标无遗留调试/TODO 注释,现有中文注释记录大量踩坑结论,应保留;唯一需修正的是 F1 的不实「并行」描述。

## Capabilities

### New Capabilities
- `metric-sampling-robustness`: 采样层的鲁棒性保证——进程采样串行执行(快照安全)、网络速率对计数器回绕免疫、SMC 浮点解析容忍非对齐字节。

### Modified Capabilities
- (无。P1/P2 为不改变对外行为的内部质量重构,不涉及行为性 spec 变更;详见 `design.md`。)

## Impact

- **P0 受影响文件**:`HagimiMonitor/MonitorModels.swift`、`HagimiMonitor/Samplers/NetworkSampler.swift`、`HagimiMonitor/Samplers/SMC.swift`、`HagimiMonitor/MonitorPanelView.swift`。
- **行为影响**:F4 修正一处偶发的网络速率假峰;其余 P0 项为注释/性能/可见性修正,不改变对外行为。
- **构建**:P0 完成后需 `HagimiMonitor` 与 `HagimiMonitorDirect` 两个 scheme 编译通过。
- **在途改动协调**:`MenuBarStatusLabel.swift` 存在未提交的菜单栏单元对齐改动(非本次审查产物);F7(P1)与其区域重叠,落地前需先协调该改动。
