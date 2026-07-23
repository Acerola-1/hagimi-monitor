# 小猫彩蛋（致敬 RunCat）设计文档

日期：2026-07-23

## 背景与动机

HagimiMonitor 的菜单栏负载环概念最初参考自开源项目 [RunCat](../../RunCatNeo)（Apache 2.0，Kyome22 / Takuto Nakamura）。在 v1.0 发布前，希望加入一个致敬 RunCat 的隐藏彩蛋：让小猫真的在菜单栏跑起来，速度由本项目自己的综合负载驱动，而不是简单的链接或弹窗。

## 目标

- 在下拉面板 header 的空白区域，极低概率地出现一只临时"客串"的小猫，作为彩蛋入口。
- 用户认出并持续点击后，将菜单栏当前显示模式（不论原来是负载环还是指标）切换为真正的「小猫奔跑模式」，速度跟随本项目的综合负载（`combinedComputeLoad`）。
- 附带一段致谢弹窗，说明灵感来源 RunCat，引导用户支持原项目。
- 猫模式不出现在设置页，只能通过该彩蛋触发；用户想切回去，直接去设置选回原来的 ring/metrics 即可，无需专门的"退出"入口。

## 非目标

- 不做 RunCat 那样的多角色（狗/史莱姆/咖啡等）与自定义 runner 系统，只做猫这一种。
- 不做速度反向偏好（负载越高越慢）这类用户可调选项，只做"负载越高跑越快"一种映射。
- 不在设置页暴露任何"猫模式"相关的开关或说明入口。
- 不引入通用的彩蛋/成就系统框架，这是一次性的、专用的实现。

## 交互流程

1. **随机客串**：面板每次由隐藏变为可见（`onAppear`）时，若当前 `menuBarDisplayMode != .cat`，以 **10%** 概率触发一次客串——小猫从 header 行 `Spacer` 所在的空白区域滑入/淡入，原地循环播放跑步帧（固定的"待机"帧间隔，不与负载挂钩，因为此时它还只是预告，尚未接管菜单栏图标）。
2. **停留与超时**：客串最多停留 **8 秒**（或点满 10 次提前结束）；超时未点够则小猫自行跑走消失，点击计数清零，需等下次面板重新打开再摇一次骰子。
3. **点击反馈**：
   - 累计点击 **3 次**：小猫头顶弹出一个小气泡提示"点我点我"（`Localizable.xcstrings` 中英双语）。
   - 累计点击 **10 次**：立即执行激活——`store.settings.menuBarDisplayMode = .cat`；同时弹出一个说明弹窗，致谢 RunCat（文案：本项目菜单栏灵感来自 RunCat，如果喜欢欢迎支持原项目，这里只是致敬彩蛋）；header 客串小猫退场。
4. **激活后**：菜单栏图标变为小猫跑步动画，帧间隔由 `combinedComputeLoad` 驱动（见下）。用户在设置页选择 ring 或 metrics 即可切回，无需额外操作。

## 架构与组件设计

### 1. `MenuBarDisplayMode` 新增 `.cat`

- `MenuBarDisplayMode`（`MenuBarDisplayModels.swift`）新增一个 `case cat`，保持 `CaseIterable`。
- 持久化沿用现有 `MonitorSettings.Keys.menuBarDisplayMode` / `$menuBarDisplayMode.dropFirst().sink { persist(...) }` 逻辑，不新增 UserDefaults key——`.cat` 和 ring/metrics 一样被原样存取，App 重启后仍是猫模式，直到用户在设置里手动切走。
- `GeneralSettingsView` 里 `Picker` 的 `ForEach(MenuBarDisplayMode.allCases)` 改为遍历一个过滤掉 `.cat` 的子集（例如 `MenuBarDisplayMode.allCases.filter { $0 != .cat }`），确保设置页分段选择器里看不到、也选不出"猫"。
- `MenuBarStatusLabel.swift` 的 `switch store.settings.menuBarDisplayMode` 新增 `.cat` 分支，渲染新的猫图标视图。

### 2. 菜单栏猫图标渲染（`MenuBarCatIcon.swift`，新文件）

- 结构对齐 `MenuBarComputeRingIcon.swift`：一个 `enum`，暴露读取当前帧 `NSImage` 的静态方法，但因为只有 5 帧、不按负载分桶着色，不需要 `NSCache` 分桶缓存，直接在类型加载时把 5 帧解码成 `NSImage` 常量数组即可。
- 素材：把 `docs/RunCatNeo/LocalPackage/Sources/UserInterface/Resources/Media.xcassets/Runners/Cat/cat-frame-{0..4}.imageset/cat-frame-{0..4}.png` 五张图拷贝进 `HagimiMonitor/Assets.xcassets`，作为新的 imageset。
- 每帧 `isTemplate = true`，交给 AppKit 按菜单栏当前外观自动着色（照搬 RunCat 的做法），不用像环形图标那样手动判断 light/dark。
- 帧推进用一个独立的 `Timer`（与 `MenuBarLoadAnimator` 现有 30fps 定时器同构但独立一份，帧率远低于 30fps，帧间隔本身就是"速度"），驱动 `@Published` 当前帧索引，`MenuBarStatusLabel` 订阅并展示。

### 3. 速度公式（综合负载驱动）

- 复用 `MonitorStore.loadAnimator.displayedComputeLoad`（即综合负载 `combinedComputeLoad` 的 30fps 平滑值），量纲与 RunCat 的 CPU 百分比一致（0–100）。
- 沿用 RunCat 的区间映射，把「CPU 百分比」换成「综合负载」：
  ```swift
  let loadValue = min(20, max(1, displayedComputeLoad / 5))
  let frameInterval = baseInterval / loadValue
  ```
- 不做"负载越高越慢"的偏好开关，只做负载越高跑越快一种映射。

### 4. Header 客串组件（新增视图，暂定 `HeaderCatCameo.swift` 或内嵌在 `MonitorPanelView`）

- 复用同一套 5 帧图，但用固定的"待机"帧间隔播放（不读综合负载）。
- 状态机（每次面板 `onAppear` 且 `menuBarDisplayMode != .cat` 时判定）：
  - `spawnProbability`：一个具名常量，当前定为 **0.10**（用户明确要求从 3% 调到 10%）。
  - 出现后启动一个 8 秒的停留计时器 + 一个点击计数器；点击计数达到 3 触发提示气泡，达到 10 触发激活流程并让计时器失效。
  - 计时器到期而未激活：清空客串状态（小猫退场、计数清零），等待下次面板打开重新摇骰子。
- 位置：嵌入 `MonitorPanelView.header(theme:)` 现有 `HStack` 中 `Spacer(minLength: 0)` 所在的空白区域，作为该区域的一个可选 overlay/子视图，不影响其余 header 布局。
- 点击热区就是小猫本体图形范围，不额外扩大命中区域。

### 5. 致谢弹窗

- 10 次点击触发时展示一个弹窗（`.sheet` 或 `.popover`，与现有面板玻璃拟态风格保持一致），文案走 `Localizable.xcstrings`（zh-Hans + en）：
  > 这个功能的灵感来自开源项目 RunCat。如果你喜欢这个小彩蛋，欢迎去支持一下原项目——这里只是一个致敬。

### 6. 本地化

- 新增词条（均需 zh-Hans + en）：客串提示气泡"点我点我"、致谢弹窗正文、弹窗关闭按钮（如需要）。不新增任何设置页文案，因为猫模式不出现在设置页。

### 7. 版权归属

- 复制的 5 张 PNG 属于 RunCat（Apache 2.0）。按 License 要求，在项目里保留一份归属说明——落地位置沿用 `AboutSettingsView.swift` 现有的鸣谢/第三方许可小节模式（若尚无此类小节，新增一条最小化的"素材来自 RunCat (Apache 2.0)"说明），不需要单独的 NOTICE 文件。

## 测试构建注意事项

实现完成后交付给用户测试的版本，**不要求用户等待那 10% 概率**：把 `HeaderCatCameo` 里的 `spawnProbability` 常量临时改为 `1.0`（跳过随机判定，面板一打开必出现），验证交互无误后，在正式发布前改回 `0.10` 定稿。这是构建阶段的一次性常量调整，不引入额外的调试开关/环境变量机制。

## 风险与待观察点

- Header 空白区域宽度有限，需要在实现时确认 5 帧猫图标缩小到该区域后仍可辨认（必要时等比缩小到比菜单栏 18×18 更小的尺寸）。
- `.cat` 加入 `MenuBarDisplayMode.allCases` 后，任何遍历该 `allCases` 的地方（目前已知仅 `GeneralSettingsView` 一处）都要同步排除，避免猫模式意外出现在其他遍历场景（如预览图逻辑）。

## 范围外（Out of Scope）

- 多角色 runner、自定义图片、速度偏好开关。
- 猫模式的设置页 UI、开关、说明文案。
- 客串组件的单元测试之外的 UI 自动化测试（沿用项目现状，无 UI 测试新增要求）。
