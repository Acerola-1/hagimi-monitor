## 1. 补全 xcstrings 日语翻译

- [x] 1.1 为 `mediaKey.*` 系列 10 个 key 补充日语翻译（brightness-toggle, volume-toggle, show-osd, section-title, permission-title, permission-explanation, status-authorized, status-not-authorized, refresh-permission, open-system-settings）
- [x] 1.2 为 `panel.pin`、`panel.unpin`、`panel.close` 3 个 key 补充日语翻译
- [x] 1.3 为 `settings.quick-access` 系列 5 个 key 补充日语翻译（quick-access, press-key, record, recording, clear）
- [x] 1.4 为 `settings.sidebar.beta-badge` 补充日语翻译

## 2. 修复源码硬编码字符串

- [x] 2.1 GPUSampler.swift: 将 `summary: "无法读取"` 改为 `summary: String(localized: "sampler.unavailable")`，并在 xcstrings 中添加该 key 的中英日翻译
- [x] 2.2 MemorySampler.swift: 将 `summary: "无法读取"` 改为 `summary: String(localized: "sampler.unavailable")`
- [x] 2.3 StorageSampler.swift: 将 `summary: "无法读取"` 改为 `summary: String(localized: "sampler.unavailable")`
- [x] 2.4 MonitorPanelView.swift: 将 `Text("SYSTEM · LIVE")` 改为 `Text(String(localized: "SYSTEM · LIVE"))`，并在 xcstrings 中为该 key 补充日语翻译
- [x] 2.5 AboutSettingsView.swift: 将 `Label("Releases", systemImage: "shippingbox")` 改为 `Label(String(localized: "Releases"), systemImage: "shippingbox")`，并在 xcstrings 中为该 key 补充日语翻译
- [x] 2.6 AboutSettingsView.swift: 将 `Text("© 2026 Acerola")` 改为 `Text(String(localized: "© 2026 Acerola"))`，并在 xcstrings 中为该 key 补充日语翻译

## 3. HaloRingSource.title 本地化一致性

- [x] 3.1 MonitorModels.swift: 将 `HaloRingSource.title` 的 `.cpu` 分支从 `"CPU"` 改为 `String(localized: "ring-source.cpu")`
- [x] 3.2 MonitorModels.swift: 将 `HaloRingSource.title` 的 `.gpu` 分支从 `"GPU"` 改为 `String(localized: "ring-source.gpu")`
- [x] 3.3 在 xcstrings 中添加 `ring-source.cpu` 和 `ring-source.gpu` 两个 key 的中英日翻译

## 4. MenuBarMetricKind.menuBarPrefix 本地化

- [x] 4.1 MenuBarDisplayModels.swift: 将 `menuBarPrefix` 属性中 7 个硬编码缩写改为 `String(localized:)` 引用（cpu-usage, gpu-usage, memory-usage, battery-level, cpu-temperature, storage-free, system-power）
- [x] 4.2 在 xcstrings 中添加 `menu-bar-metric-prefix.*` 系列 7 个 key 的中英日翻译

## 5. 迁移映射跨语言兼容

- [x] 5.1 MonitorSettings.swift: 在 `migrateMetrics` 映射字典中添加旧版英文 key 的映射条目（如 "System" → "system", "User" → "user"），与现有中文映射合并
- [x] 5.2 考虑添加旧版日文 key 的映射 — 项目从未发布过日文版，无需添加日文迁移映射

## 6. 验证

- [x] 6.1 构建项目确认无编译错误
- [x] 6.2 检查 xcstrings 中所有 key 的三语翻译完整性（无遗漏）
- [x] 6.3 检查源码中不再有用户可见的硬编码中文字符串
