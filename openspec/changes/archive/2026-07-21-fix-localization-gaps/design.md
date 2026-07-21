## Context

项目 `Localizable.xcstrings` 支持 zh-Hans（源语言）、en、ja 三语，共 308 个 key。英语翻译完整，但日语缺失 19 个 key，集中在近期新增的「媒体键接管」「快速呼出」「面板钉住」三个功能。同时源码中存在 8 处硬编码用户可见字符串，其中 3 处 Sampler 的中文占位文本会直接显示给非中文用户。

## Goals / Non-Goals

**Goals:**
- 补全 19 个缺失的日语翻译
- 消除源码中所有用户可见硬编码字符串，统一走 `String(localized:)`
- 修复 `MonitorSettings` 迁移映射的跨语言兼容性
- 保持改动最小化，不改变 UI 布局或交互逻辑

**Non-Goals:**
- 不增加第四种语言支持
- 不重构本地化架构（不引入 Strings Catalog 以外的新机制）
- 不修改 `MemoryPressureState.title` 的回退逻辑（现有 `localizedMemoryPressure()` 已可正确本地化）
- 不修改品牌名硬编码（`HagimiMonitor` 在 `.help()`、`NSMenu(title:)`、`setAccessibilityTitle()` 中的使用 — 品牌名通常不翻译）

## Decisions

### Decision 1: Sampler 占位文本使用共享 key
三个 Sampler 中的 `"无法读取"` 改为 `String(localized: "sampler.unavailable")`，使用同一个 key。理由：三个 Sampler 的占位文本语义相同，共享 key 减少翻译维护量。

**替代方案**：为每个模块创建独立 key（`sampler.gpu.unavailable` 等）—— 过度设计，当前无需区分。

### Decision 2: MenuBarMetricKind.menuBarPrefix 添加本地化 key
为每个指标前缀创建 `menu-bar-metric-prefix.<id>` 格式的 key（如 `menu-bar-metric-prefix.cpu-usage`），而非复用已有的 `menu-bar-metric.<id>` key。理由：前缀是缩写形式（如 "MEM" vs "Memory Usage"），需要独立的翻译条目以适应不同语言的缩写习惯。

**替代方案**：复用现有 `menu-bar-metric.*` key —— 这些 key 的翻译是完整形式（如 "CPU Usage"），不适合菜单栏空间受限的前缀显示。

### Decision 3: 迁移映射扩展为多语言映射
将 `MonitorSettings.migrateMetrics` 中仅中文→英文的映射扩展为同时支持旧版中文 key 和旧版英文 key。具体做法：在现有映射字典中添加英文 key 的映射条目。

**替代方案**：删除中文映射仅保留英文 —— 会破坏从旧中文版升级用户的设置。使用合并映射更安全。

### Decision 4: HaloRingSource.title 的 CPU/GPU 使用本地化 key
为 `HaloRingSource` 的 `.cpu` 和 `.gpu` 分支创建 `ring-source.cpu` 和 `ring-source.gpu` 两个新 key，与已有的 `ring-source.combined` 和 `ring-source.memory` 保持一致模式。

### Decision 5: "SYSTEM · LIVE" 和 "Releases" / "© 2026 Acerola" 使用已有 key
xcstrings 中已有 `SYSTEM · LIVE`、`Releases`、`© 2026 Acerola` 三个 key（含 en 翻译），但代码中未通过 `String(localized:)` 引用。直接修改代码引用这些已有 key，同时补充缺失的日语翻译。

## Risks / Trade-offs

- [菜单栏前缀本地化可能导致文本溢出] → 日语缩写通常较短，风险低；若出现溢出，现有面板宽度约束已有截断处理
- [迁移映射扩展增加代码量] → 影响微小，迁移函数仅初始化时调用一次
- [品牌名 HagimiMonitor 不翻译] → 这是行业惯例（macOS 系统应用名称也不翻译），风险极低
