# 菜单栏驻留态内存优化 设计文档

日期: 2026-06-14
作者: brainstorming session

## 背景

Direct 构建驻留状态(MenuBarExtra,面板未打开)实测内存:

- RSS 150.4MB, physical footprint 133.2MB
- owned unmapped (graphics) 57.2MB(最大头,图形 / 窗口 / Layer / IOSurface)
- MALLOC allocated 40.1MB(其中 DefaultMallocZone 33.2MB, AttributeGraph 4.7MB)
- mapped file resident 25.4MB, shared memory 7.5MB, IOAccelerator graphics 3.6MB

CPU sample 显示热点是 SwiftUI / AppKit 渲染链路(`NSHostingView.layout`、`ViewGraphRootValueUpdater.render`、`AttributeGraph`、`MonitorPanelView.body`、`GlassEffectContainer`、`NSStatusItem` 重绘),而非 DDC I/O。

根因定位到驻留态:`MonitorStore` 启动后会持续跑一个 **125ms 周期的 `animationTimer`**,每次触发都改 `@Published var menuBarFrame`(用于 core 呼吸动画)与 `@Published var displayedComputeLoad`。这两者都会让 `HagimiMonitorApp` 的 `MenuBarExtra` body 重新求值,继而调用 `MenuBarComputeRingIcon.image(...)` 重新生成一张 18×18 `NSImage`(走 `lockFocus`/`unlockFocus`,经过 IOSurface / CoreAnimation 路径)。

每秒 8 次菜单栏图标重生 + SwiftUI body 重算,即使在 idle 状态(`menuBarFrame` 仍然 0..47 循环驱动 core pulse)也不会停,长期堆积出图形内存与 AttributeGraph 占用。

## 目标

将菜单栏驻留态(面板未打开)的常驻内存压到 60–80MB 量级,**不破坏 ring 随负载平滑变化的视觉**。打开面板后的内存峰值不在本次范围。

## 非目标

- 不重构 `MonitorPanelView` 的 `GlassEffectContainer` / `glassEffectID` 体系。
- 不改变采样间隔 `MonitorRefreshSchedule`。
- 不改 ring 的视觉算法本身(progress、tint、trackColor、coreColor 的 base 值不变)。

## 用户决定

- pulse 动画:**core 不再呼吸**(直接静止),但**外圈 ring 必须随 load 平滑过渡**(不允许跳变)。
- 范围:**只压驻留态**,面板打开态不动。
- 顺手项:**做 DateFormatter 静态化 + `@Published` 清理**;不做面板重构。
- **不要擅自 git commit**,所有提交点等用户显式批准。

## 改动清单

### 1. `MenuBarComputeRingIcon` — 去 pulse + 加缓存

文件: `HagimiMonitor/MenuBarComputeRingIcon.swift`

- `MenuBarComputeRingImageStyle`:
  - 删除 `let frame: Int` 字段。
  - 删除 `linearPulse` 计算属性。
  - `coreColor` 中移除 `+ linearPulse * 0.03` 这一项,改为只与 `darkMode`、`normalizedLoad`、`loadLevel` 相关。
- `image(...)` 函数签名:
  - 旧:`image(load: Double, frame: Int, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSImage`
  - 新:`image(load: Double, darkMode: Bool, loadLevel: MenuBarComputeLoadLevel) -> NSImage`
- 加文件内静态缓存:
  - 用 `NSCache<NSString, NSImage>`(自动响应内存压力 evict)。
  - cache key: `NSString` 形如 `"\(quantizedLoadBucket)|\(darkMode ? 1 : 0)|\(loadLevel.cacheIndex)"`,其中 `displayedComputeLoad` 取值范围为 0…100(百分比,与 `combinedComputeLoad` 一致),`quantizedLoadBucket` 为 `Int(round(load / 2.0))`(每 2% 一档,0…50 共 51 档),`loadLevel.cacheIndex` 为 enum 的稳定整型索引(0…3)。
  - cache 容量上限 `countLimit = 120`(理论组合 51 × 2 × 4 = 408,设 120 已能覆盖常见组合,超出时 NSCache 自行驱逐)。
  - 命中复用,未命中走 `lockFocus` 绘制并入缓存。
- `MenuBarComputeLoadLevel` 加 `var cacheIndex: Int { ... }` 给四个 case 稳定 0…3 索引,用于 cache key 拼装。

### 2. `MonitorStore` — 删 menuBarFrame + 重构动画驱动

文件: `HagimiMonitor/MonitorModels.swift`

- 删除字段:
  - `@Published private(set) var menuBarFrame`
  - `private var animationTimerCancellable: AnyCancellable?`
  - `private var framesSinceLastMenuBarTargetUpdate`
- 删除 `init` 里 `animationTimerCancellable = Timer.publish(every: animationInterval, ...)` 整个块,以及 `deinit` 里对应 cancel。
- 删除 `advanceAnimation()` 中关于 `menuBarFrame = (menuBarFrame + 1) % 48` 的那行;函数本身可能整体废弃(只保留 `displayedComputeLoad` 推进逻辑,见下)。
- `displayedComputeLoad` 的平滑:
  - **首选方案**:在 `advance()`(采样 tick,每秒一次)更新完 `allModules` 后,计算新 target,直接 `withAnimation(.easeInOut(duration: 0.6)) { displayedComputeLoad = quantizedTarget }`。SwiftUI 自己负责把外圈过渡渲染出来。
  - **fallback 方案**:若 `withAnimation` 在 `MenuBarExtra` label 上无效,自写一个**按需启动 / 稳定即停**的低频 timer:仅当 `|target - displayedComputeLoad| > 0.5` 时启动 500ms timer,每 tick 把 displayedComputeLoad 推近 target,差值进入阈值即 cancel。比 125ms 永不停的开销低一个量级。
  - 量化:写入 `displayedComputeLoad` 之前先把 0…100 范围按每 2% 取整(即 `round(load / 2) * 2`),提升菜单栏图标缓存命中率。
- `Constants.swift`:
  - 删除 `animationInterval`、`menuBarLoadUpdateFrameInterval`、`menuBarLoadUpdateInterval`(确认无其他引用后)。
  - 不动 `tickInterval` 与 sampling 相关常量。

### 3. `HagimiMonitorApp` 调用方更新

文件: `HagimiMonitor/HagimiMonitorApp.swift`

- `MenuBarExtra` 的 label 闭包内 `MenuBarComputeRingIcon.image(...)` 调用去掉 `frame:` 参数。
- 其余不变。`Image(nsImage:)` 这层 SwiftUI 仍会因为 `displayedComputeLoad` 变化触发 body 重算,但因 load 已量化 + 图标层缓存,实际 NSImage 创建次数大幅下降(稳态 idle 接近 0)。

### 4. `MonitorPanelView.timeString` — DateFormatter 静态化

文件: `HagimiMonitor/MonitorPanelView.swift`

- 当前 `timeString`(line 188-192)每次 panel body 重算都 `DateFormatter()` 新建。
- 提成文件级 `private let panelTimeFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()`。
- `timeString` 改为 `panelTimeFormatter.string(from: Date())`。
- 与驻留态无关(面板关闭时不命中),纯顺手项。

### 5. `@Published` 清理(谨慎)

- 在 `MonitorModels.swift` 中扫所有 `@Published`,grep 各属性的实际订阅者:
  - `modules` — `MonitorPanelView.ForEach` 依赖,**保留**。
  - `selectedKind` — 初步看无 SwiftUI 观察者(`MenuBarExtra` label 不用,`MonitorPanelView` 也没引用),**plan 阶段 grep 确认后,可改为普通 `var` 或直接删字段**。如果只在内部读写,降级为非 Published 即可避免每次切换都触发 SwiftUI invalidation 噪声。
  - `displayedComputeLoad` — `MenuBarExtra` label 依赖,**保留**(改动后写入路径加量化 + withAnimation)。
- 这一项是低风险清理,任何不确定的属性保持原样。

## 数据流(改动后)

```
sampling timer (1s / refreshSchedule.tickInterval)
        │
        ▼
   advance()
        │
        ├─► sampler.sample(kinds)
        ├─► allModules / modules update
        ├─► 计算 combinedComputeLoad target
        ├─► quantize target (2% 一档)
        └─► withAnimation { displayedComputeLoad = quantizedTarget }
                                 │
                                 ▼
                  SwiftUI 重算 MenuBarExtra label
                                 │
                                 ▼
              MenuBarComputeRingIcon.image(load, darkMode, loadLevel)
                                 │
                       ┌─────────┴─────────┐
                       ▼                   ▼
                   cache hit            cache miss
                   (复用 NSImage)        (lockFocus 绘制 + 入 cache)
```

不再存在 125ms animationTimer。稳态 idle 下,每秒最多 1 次缓存查询,且因 load 量化常命中,实际 NSImage 重生频率趋近 0。

## 风险与回退

| 风险 | 缓解 |
| --- | --- |
| NSCache 持有 NSImage 反而吃图形内存(IOSurface 不一定随 NSImage release 立即还) | NSCache 内存压力下自动 evict + countLimit 上限。Plan 阶段做对比测试:开缓存 vs 不开缓存的 RSS。无收益就关掉,只保留 "砍 timer + 量化",仍可拿到大部分收益。 |
| 去 pulse 后用户感觉菜单栏"卡死了" | header 里 SwiftUI 自带的 `.symbolEffect(.pulse)` 小圆点保留(系统效果开销极低)。外圈仍随 load 平滑变化。负载真有波动时菜单栏一定在动。 |
| `withAnimation` 在 MenuBarExtra label 中行为未知 | fallback 到"按需启动 / 稳定自停"的 500ms 低频 timer。仍比 125ms 永不停优。Plan 阶段先做最小验证。 |
| `@Published` 清理误删导致面板无法刷新 | 仅清理已 grep 确认无观察者的属性;有疑问保持原样。 |

## 测试

### 单元测试

新增 `HagimiMonitorTests/MenuBarComputeRingIconCacheTests.swift`:

- 同参数 `image(...)` 两次调用应返回**同一** NSImage 实例(命中缓存)。
- 量化边界:load = 0.5 与 load = 1.0 命中同一 bucket(取决于量化精度,断言行为一致)。
- 不同 darkMode / loadLevel 不串扰。
- countLimit 触发后旧条目可被驱逐(NSCache 行为非严格 LRU,但容量上限应生效)。

### 手测 checklist(写入 implementation plan)

- [ ] 启动后驻留 5 分钟,Activity Monitor 看 RSS / physical footprint;期望 ≤ 80MB。
- [ ] 与改动前对比 owned unmapped graphics 的差值。
- [ ] CPU 从 5% 慢爬到 80%,外圈 ring 平滑过渡,无跳变。
- [ ] 系统暗/亮模式切换,菜单栏图标颜色立刻正确(可能要等下一次 sample tick,记录实际行为)。
- [ ] 4 个 loadLevel(idle/working/busy/stressed)颜色都能正确显示。
- [ ] 反复打开/关闭面板 10 次,RSS 回落到接近基线,而非阶梯式增长。
- [ ] CPU sample 检查 `MenuBarComputeRingIcon.image` 不再是热点。

## 验收标准

1. 驻留 5 分钟后 RSS ≤ 80MB(对比前 150MB)。
2. owned unmapped graphics 显著下降(对比前 57MB)。
3. ring 视觉行为:外圈随 load 平滑变化,core 不呼吸但颜色按 loadLevel 正确。
4. 现有测试全部通过,新增缓存测试通过。
5. 无新增 lint / build warning。

## 不在本次范围

- `MonitorPanelView` 内 `GlassEffectContainer` / `glassEffectID` 重构。
- 采样间隔与 sampler 内部优化。
- 设置窗口、SettingsRootView 相关。
- DDC / SMC 模块。
