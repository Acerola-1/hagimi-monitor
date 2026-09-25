# game-hud Tasks

> 约定：本 change 只交付计划。**Phase 1 门槛已于 2026-09-25 跑完**，结论见 `tmp/game-hud-probe/gate-conclusions/conclusions.json`。
> 涉及渠道差异的改动按 AGENTS.md 核对两个 target；验证产物放 `tmp/`，不提交。

## Phase 1: 能力门槛验证（已完成，1.5 待真实游戏复验）

- [x] 1.1 扩展 `prototypes/game-hud-probe/` 探针设备，验证帧率采集通路
  - **结论：受控进程 stderr 完整可用**；`metal-HUD` 行格式为 `帧号,图形内存,进程内存,(present interval,gpu time)*N`，每秒一行约 60 样本
  - 60FPS 目标实测解析出 59.92 FPS，与探针前次记录一致
  - **统一日志不可用**：`log stream` 可见事件但逐帧明细被隐去为 `<private>`（本轮复现确认）
  - **对已在运行的游戏不可用**：非我方启动的进程拿不到帧明细
  - 产物：`tmp/game-hud-probe/fps-route/`
- [x] 1.2 验证悬浮层窗口档位
  - **结论：`.floating` 已足够**压住另一进程的原生全屏，无需提升到 `.statusBar`
  - 原生全屏下浮窗完整可见且未夺焦
  - 产物：`tmp/game-hud-probe/levels/level-test.png`
- [x] 1.3 验证物理点击穿透
  - **结论：成立**。在浮窗正中心合成 CGEvent 点击，下层全屏游戏收到 `scene-mouse-down` 且 `keyWindow=true`
  - 基线对照：浮窗外点击同样被游戏收到，证明事件通路有效
  - 产物：`tmp/game-hud-probe/levels/scene.jsonl`
- [x] 1.4 验证官方 HUD 按游戏启用的等效通路
  - **结论：`NSWorkspace` 传环境变量被系统丢弃**。同一场景程序直接启动时 `hudEnvironment=1` 生效，经 `NSWorkspace` 启动时标记 `absent`
  - 全局键 `MetalForceHudEnabled` 当前不存在，未被污染
  - 实现须走「受控启动」或「仅手动提示」，**不得写全局偏好**
- [ ] 1.5 用真实游戏复测沙盒浮窗与指标
  - 待办：至少覆盖一个真实 macOS 游戏（含 Steam 原生）
  - 复核沙盒可用指标清单在真实游戏下是否一致
- [x] 1.6 汇总门槛结论并回填 `design.md`
  - 结论已落 `tmp/game-hud-probe/gate-conclusions/conclusions.json`，design 的 Context/决策 1/Risks/Open Questions 已同步

> **门槛结论对后续阶段的影响：**
> - 帧率曲线范围受限（只能覆盖受控启动的游戏）→ **待用户拍板**（design Open Questions 第 1 条），Phase 6.3 在此之前不实现帧率部分
> - 窗口档位已定：`.floating` + `ignoresMouseEvents` + `.canJoinAllApplications`/`.fullScreenAuxiliary`
> - 官方 HUD 辅助须避开 `NSWorkspace` 环境传递
> - Phase 2、3 不受门槛影响，可直接推进

## Phase 2: 数据层

- [ ] 2.1 新建 `GameHUDMetricCatalog`
  - 定义 HUD 可用指标目录，**复用既有指标 ID**，映射见 `specs/game-hud/spec.md` 的候选指标表
  - 排除 IP/SSID/蓝牙/电池健康与循环/电压电流容量等与游戏无关项
  - 渠道过滤以运行时可读性为准（注意：`DISPLAY_CONTROL` 两个渠道都有，仅 `DIRECT_DISTRIBUTION` 是官网独有）
  - 文件：`HagimiMonitor/GameHUD/GameHUDMetricCatalog.swift`
- [ ] 2.2 新建 `GameHUDMetricsAdapter`
  - 从 `MonitorStore` 的 `@Published private(set) var modules: [MonitorModule]` 按 `kind` 查找读取
  - 按用户勾选与目录可用性过滤，输出悬浮层渲染所需的数据结构
  - 已勾选但本次无读数 → 值置 `nil`（渲染为 `—`），不填 0
  - `gpu-memory` / `allocated` 保留「驱动聚合」语义标注
  - 文件：`HagimiMonitor/GameHUD/GameHUDMetricsAdapter.swift`
- [ ] 2.3 新建 `GameHUDSampleHistory`
  - 滚动历史缓冲，供 CPU/GPU 占用曲线使用（语义为整机占用，**不是帧率**）
  - 复用既有滚动数组约定；如需环形缓冲按需引入，避免无谓抽象
  - 文件：`HagimiMonitor/GameHUD/GameHUDSampleHistory.swift`

## Phase 3: 设置层

- [ ] 3.1 扩展 `MonitorSettings`
  - 新增总开关、已勾选指标集合、用户添加名单、排除名单、角落、水平/垂直偏移
  - 按既有 `Keys` 约定命名持久化键（前缀 `settings.gameHUD.`），并按既有一次性迁移模式处理存量用户
  - 文件：`HagimiMonitor/MonitorSettings.swift`
- [ ] 3.2 新建 `GameHUDSettingsView`
  - 设置组顺序：总开关 → 监控项目 → 应用名单 → 悬浮层布局（官网渠道追加官方 HUD 说明组）
  - 监控项目列表只渲染本渠道与当前硬件可用项；沙盒渠道不出现、不灰显 CPU 温度与分项功耗
  - 应用名单支持添加/移除/排除；不依赖每次进页全量枚举系统已安装应用
  - 文件：`HagimiMonitor/Views/Settings/GameHUDSettingsView.swift`
- [ ] 3.3 注册设置路由与侧栏入口
  - 在 `SettingsRoute` 增加 case，并在 `SettingsSidebar` 既有「扩展」分组内新增条目
  - 图标注：侧栏分组 key 已存在为 `settings.sidebar.extensions`
  - 文件：`HagimiMonitor/Views/Settings/SettingsSidebar.swift`、`SettingsRootView.swift`

## Phase 4: 工具区

- [ ] 4.1 扩展工具条目枚举
  - 在 `QuickToolKind`（**位于 `HagimiMonitor/Views/Panel/QuickToolsPopover.swift`，不在 QuickToolsStore.swift**）新增 case 及 `storageKey` / `titleKey` / `symbol`
  - 在 `MonitorSettings` 补一次性迁移，向存量用户的 `visibleQuickTools` 并入新 case（用户手动关过的不复活）
  - 文件：`HagimiMonitor/Views/Panel/QuickToolsPopover.swift`、`MonitorSettings.swift`
- [ ] 4.2 接入按钮行为与状态
  - 按钮切换与设置页同源的总开关；不打开设置窗口
  - 显示数秒后自动消失的状态提示
  - 文件：`HagimiMonitor/Views/Panel/QuickToolsPopover.swift`、`QuickToolsStore.swift`
- [ ] 4.3 设置页工具卡片
  - 在 `QuickToolsSettingsView` 中显示 Game HUD 条目与其显隐
  - 文件：`HagimiMonitor/Views/Settings/QuickToolsSettingsView.swift`

## Phase 5: 游戏识别与状态机

- [ ] 5.1 新建 `GameHUDGameList`
  - 内置候选 bundle ID 名单 + 用户添加/排除名单的合并判定（排除优先）
  - 判定 SHALL NOT 以「使用了 Metal/OpenGL」为条件
  - 文件：`HagimiMonitor/GameHUD/GameHUDGameList.swift`
- [ ] 5.2 新建 `GameHUDSessionController`
  - 监听前台应用切换，维护 idle / monitoring / displaying / hidden 状态
  - 项目内此前**没有**前台应用识别与名单的现成实现，属全新代码
  - 游戏失去前台只隐藏不销毁窗口
  - 文件：`HagimiMonitor/GameHUD/GameHUDSessionController.swift`
- [ ] 5.3 接入应用生命周期
  - 在既有入口启动会话控制器，与总开关保持同步
  - 文件：`HagimiMonitor/AppDelegate.swift` 或应用初始化处

## Phase 6: 悬浮层

- [ ] 6.1 新建 `GameHUDPanelController`
  - 独立 `NSPanel`（borderless + nonactivatingPanel），**不复用 `PinnedPanelController` 的配置**——后者没有 `ignoresMouseEvents`，且 `collectionBehavior` 为 `[.moveToActiveSpace, .fullScreenAuxiliary]`，不含 `.canJoinAllApplications`
  - 档位按 Phase 1.2 实测结论：`level = .floating`（已足够压住原生全屏，无需 `.statusBar`）
  - `collectionBehavior` 含 `.canJoinAllApplications`、`.fullScreenAuxiliary`；`ignoresMouseEvents = true`；不成为 key window
  - 窗口尺寸遵循固定契约，不随勾选数量变化
  - 文件：`HagimiMonitor/GameHUD/GameHUDPanelController.swift`
- [ ] 6.2 新建 `GameHUDView`
  - 只渲染已勾选项的值与单位；无读数显示 `—`
  - 颜色使用 `MonitorPalette` 既有令牌，不新增数值
  - 文件：`HagimiMonitor/GameHUD/GameHUDView.swift`
- [ ] 6.3 曲线渲染
  - **帧率部分阻塞于用户决策**（design Open Questions 第 1 条）：帧率只能从受控启动进程的 stderr 取得，对已运行游戏无效。用户答复前不实现帧率曲线
  - 先行实现 CPU/GPU 占用曲线，且文案不得暗示为帧率
  - 复用既有绘图实现（项目已有 `SparklineChart`）或按其约定扩展
  - 文件：`HagimiMonitor/GameHUD/GameHUDCurveView.swift`

## Phase 7: 官网渠道官方 HUD 辅助（实现范围受 Phase 1.4 结论约束）

- [ ] 7.1 实现按游戏的启用辅助
  - 只编译进 `HagimiMonitorDirectOnly/`
  - **不得依赖 `NSWorkspace` 传递环境变量或参数**——Phase 1.4 实测确认被系统丢弃
  - 可选路径：以受控环境重新启动目标游戏（需先验证），或仅生成供用户手动使用的说明
  - 不写全局偏好、不注入游戏、不自动结束或重启游戏
  - 文件：`HagimiMonitorDirectOnly/GameHUD/OfficialHUDHelper.swift`
- [ ] 7.2 接入设置页
  - 仅官网渠道显示该设置组
  - 文件：`HagimiMonitor/Views/Settings/GameHUDSettingsView.swift`

## Phase 8: 本地化

- [ ] 8.1 补充 `HagimiMonitor/Localizable.xcstrings`
  - 设置页文案、指标名称、工具按钮标签与状态提示、应用名单说明
  - **复用既有指标名称 key**，不新增同义 key
  - 按 JSON 结构编辑，避免无关重排
  - 文件：`HagimiMonitor/Localizable.xcstrings`

## Phase 9: 双渠道验证

- [ ] 9.1 双渠道构建
  - App Store（`HagimiMonitor`）与 Direct（`HagimiMonitorDirect`）均构建通过
  - 使用各自独立 DerivedData（`tmp/dd-appstore`、`tmp/dd-direct`）
- [ ] 9.2 运行 `MetricWidthAuditTests`
  - 若 HUD 新增指标或改动长标签，按 AGENTS.md 核对最坏值契约
- [ ] 9.3 悬浮层实机验证
  - 窗口化、无边框、原生全屏三种模式下的可见性与点击穿透
  - 多显示器下显示在游戏所在屏幕
  - 截图存档
- [ ] 9.4 指标可用性验证
  - 沙盒渠道不出现 CPU 温度与分项功耗（不出现，而非灰显）
  - 已勾选但无读数的项目显示 `—`
  - GPU 内存项文案不出现「显存」类表述
- [ ] 9.5 状态机验证
  - 游戏进入/失去前台、退出、总开关切换的行为
  - 关闭总开关后悬浮层立即隐藏
- [ ] 9.6 如实记录未通过项
  - 未实机验收的能力不得标为通过
