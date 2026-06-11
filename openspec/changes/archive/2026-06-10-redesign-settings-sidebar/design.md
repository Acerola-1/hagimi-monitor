## Context

当前 `SettingsView.swift` 基于 `TabView` 实现三 Tab 布局（常规 / 模块 / 关于），模块 Tab 内 6 个模块（CPU/GPU/内存/存储/网络/电池）以纵向列表共享一个面板。随着即将引入「指标可见性」「温度传感器」等子项级配置，纵向列状结构难以容纳每模块的多层子项。

项目仅兼容 macOS 26+ 和 Apple Silicon，可直接使用 `NavigationSplitView` 的最新 API（含 sidebar 玻璃效果），无需做版本回退。`MonitorSettings` 的存储层与本次改造无关，本次只重排 UI。

## Goals / Non-Goals

**Goals:**
- 用 `NavigationSplitView(sidebar:detail:)` 替换 `TabView`
- 左侧 sidebar 平铺三个一级项：「常规」「模块」「关于」，无分组标题
- 「模块」下嵌套 6 个子项，默认（且始终）展开
- 每个子模块拥有独立的右侧详情视图，当前阶段只承载现有「模块可见性开关」
- 左侧每一项配 SF Symbol 图标
- 为后续子项可见性扩展预留视图结构和命名

**Non-Goals:**
- 不在本次实现「子项可见性」「温度监控」等业务逻辑，只搭好布局承接位
- 不修改 `MonitorSettings` 持久化字段
- 不调整 `MonitorPanelView`、`MenuBar*`、任何 Sampler
- 不重写「关于」「常规」内已有控件，仅迁移容器
- 不引入新的本地化文案体系（沿用 `Localizable.xcstrings` 已有键，新增按需追加）

## Decisions

### D1: 使用 `NavigationSplitView(sidebar:detail:)` 而非 `HSplitView` 或 `NavigationView`
- **选择理由**：`NavigationSplitView` 是 macOS 13+ 的官方设置类窗口推荐组件，原生提供 sidebar 玻璃材质，自动适配 macOS 26 Liquid Glass；自带可拖拽分隔栏、记忆宽度、键盘导航
- **替代方案**：
  - `HSplitView`：更底层，需要自行处理玻璃和高亮态
  - `NavigationView`：已被弃用
- **代价**：sidebar 宽度对 macOS 26 默认是 180-260pt，需通过 `.navigationSplitViewColumnWidth` 微调

### D2: 路由用 `enum SettingsRoute: Hashable` 驱动 `List` 的 `selection`
- **选择理由**：枚举枚举所有可达详情，编译期穷举 `switch`，新增模块/页面时编译器报错提示
- **形态**：
  ```swift
  enum SettingsRoute: Hashable {
      case general
      case module(MonitorKind)
      case about
  }
  ```
- **替代方案**：用字符串 ID — 失去类型安全，新增项易遗漏 detail 分支

### D3: 「模块」一级项作为不可折叠的展开标题
- **选择理由**：用户明确要求子菜单默认展开且无分组标题，把「模块」做成视觉上的 section header（带 chevron-down 图标但不可交互），下方平铺 6 个子项
- **实现**：用 `Section { … } header: { Label("模块", systemImage: "square.grid.2x2") }`，header 不绑定 selection
- **替代方案**：用 `DisclosureGroup` — 默认展开但允许折叠，不符合用户「始终展开」的要求

### D4: 详情视图按职责拆文件
- 新增目录 `HagimiMonitor/Views/Settings/`，文件：
  - `SettingsSidebar.swift`：左侧导航列表 + 选中态绑定
  - `GeneralSettingsView.swift`：迁移现有「常规」Tab 内容
  - `AboutSettingsView.swift`：迁移现有「关于」Tab 内容
  - `ModuleSettingsView.swift`：根据传入的 `MonitorKind` 渲染对应模块详情；当前阶段仅承载「模块可见性开关」，预留 placeholder 区域便于后续扩展
- **选择理由**：拆出后单文件长度可控，每个详情视图独立测试与重排；命名清晰对应路由

### D5: 窗口尺寸 720×520，允许拖拽放大
- **选择理由**：sidebar ≈ 200pt，detail 至少需要 500pt 才不显局促；520pt 高度容纳 6+ 个表单行
- **实现**：在 `Settings { … }` 的根视图加 `.frame(minWidth: 640, minHeight: 480, idealWidth: 720, idealHeight: 520)`

### D6: SF Symbols 选型
- 常规：`gearshape`
- 模块（section header）：`square.grid.2x2`
- CPU：`cpu`
- GPU：`cpu.fill`（或 `display`，根据视觉效果二选一，实现时定）
- 内存：`memorychip`
- 存储：`internaldrive`
- 网络：`network`
- 电池：`battery.100`
- 关于：`info.circle`

## Risks / Trade-offs

- **[Risk] macOS 26 Beta API 行为可能不稳定**：`NavigationSplitView` 的 sidebar 玻璃在某些子版本有渲染问题 → **Mitigation**：明确依赖最新 Xcode 26.3 构建，CI 已使用；本地测试覆盖浅色 / 深色 / 跟随系统
- **[Risk] 现有「关于」Tab 中的更新检查按钮依赖 `EnvironmentObject`**：迁移后注入路径变化 → **Mitigation**：保持 `SettingsView` 根视图作为依赖注入边界，拆出的子视图通过现有的 `@EnvironmentObject`/`@ObservedObject` 接收
- **[Risk] 用户首次升级感知突变**：UI 形态大改 → **Mitigation**：在 `RELEASE_NOTES` 中说明；功能上保持向下兼容（所有现存设置项无丢失）
- **[Trade-off] sidebar 始终展开 6 个模块子项占用纵向空间**：放弃可折叠以换取「一眼可达」的导航效率，符合用户要求
