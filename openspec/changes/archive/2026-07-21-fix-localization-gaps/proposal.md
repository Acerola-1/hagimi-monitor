## Why

项目支持中英日三语，但近期新增的「媒体键接管」「快速呼出」「面板钉住」等功能遗漏了日语翻译（19 个 key），同时源码中存在多处硬编码字符串未走 `String(localized:)`，导致非中文用户看到原始中文或英文。此外 `MonitorSettings` 迁移映射使用中文 key 匹配旧版 ID，非中文系统下迁移会失败。

## What Changes

- 补全 19 个缺失的日语翻译 key（`mediaKey.*` 10 个 + `panel.pin/unpin/close` 3 个 + `settings.quick-access.*` 5 个 + `settings.sidebar.beta-badge` 1 个）
- 修复源码中 3 处 Sampler 的硬编码中文 `"无法读取"` → `String(localized:)`
- 修复 `MonitorPanelView` 中 `Text("SYSTEM · LIVE")` → 引用 xcstrings 已有 key
- 修复 `AboutSettingsView` 中 `Label("Releases")` 和 `Text("© 2026 Acerola")` → 引用 xcstrings 已有 key
- 修复 `MonitorSettings` 迁移映射中的中文 key → 使用英文标识符匹配，确保跨语言迁移正确
- 补充 `HaloRingSource.title` 中 `.cpu`/`.gpu` 的 `String(localized:)` 调用，与 `.combined`/`.memory` 保持一致
- 为 `MenuBarMetricKind.menuBarPrefix` 添加本地化支持

## Capabilities

### New Capabilities

- `localization-completeness`: 确保所有用户可见文本通过 `String(localized:)` 引用，xcstrings 三语翻译完整无遗漏

### Modified Capabilities

- `menu-bar`: `MenuBarMetricKind.menuBarPrefix` 从硬编码英文缩写改为本地化 key
- `monitor-panel`: 面板标题 `"SYSTEM · LIVE"` 改为本地化引用
- `settings-window`: 关于页硬编码文本改为本地化引用

## Impact

- `HagimiMonitor/Localizable.xcstrings` — 新增/补全约 25+ 条翻译
- `HagimiMonitor/Samplers/GPUSampler.swift` — 1 处硬编码改本地化
- `HagimiMonitor/Samplers/MemorySampler.swift` — 1 处硬编码改本地化
- `HagimiMonitor/Samplers/StorageSampler.swift` — 1 处硬编码改本地化
- `HagimiMonitor/MonitorPanelView.swift` — 1 处硬编码改本地化
- `HagimiMonitor/Views/Settings/AboutSettingsView.swift` — 2 处硬编码改本地化
- `HagimiMonitor/MonitorSettings.swift` — 迁移映射中文 key 改英文标识符
- `HagimiMonitor/MonitorModels.swift` — `HaloRingSource.title` 补充本地化
- `HagimiMonitor/MenuBarDisplayModels.swift` — `menuBarPrefix` 改本地化
