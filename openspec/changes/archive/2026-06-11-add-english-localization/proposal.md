## Why

Hagimi Monitor 目前所有用户界面文案、指标名称、错误提示均为中文硬编码，无法根据系统语言自动切换。随着项目开源并在 GitHub 上获得关注，英文用户无法正常使用。增加英文支持是扩大用户群体的必要步骤。

## What Changes

- **App 内部国际化**：将 Swift 代码中所有中文硬编码文本提取到 `Localizable.xcstrings`，新增英文翻译。Sampler 返回的指标名称改用中性英文 key（如 `"system"`），展示层必须结合模块上下文翻译为 `metric.<kind>.<id>`，避免 `used` / `temperature` 等跨模块重名 key 混淆。
- **设置数据迁移**：`enabledMetrics` 持久化 key 从中文改为英文，兼容旧数据，并处理旧 key 与新 key 混合存在、最多 4 项上限、默认值重置等边界。
- **README 双语**：新增 `README.en.md` 英文版本，原 `README.md` 保持中文。
- **产品官网双语**：`docs/` 目录拆分为 `docs/zh/index.html` 和 `docs/en/index.html`，根目录 `docs/index.html` 自动检测浏览器语言并重定向，支持右上角手动切换并持久化到 localStorage；语言页同步维护资源路径、SEO 元信息、`hreflang`、canonical、JSON-LD 与无 JS 降级入口。

## Capabilities

### New Capabilities
- `app-localization`: App 内部 UI 文案、指标名称、错误提示的英文化，基于系统语言自动切换。
- `docs-website-localization`: 产品官网（docs/index.html）支持中英文双语，自动检测 + 手动切换。

### Modified Capabilities
- `monitor-panel`: 指标名称从中文硬编码改为本地化 key，展示逻辑增加翻译层。
- `settings-window`: 设置页面所有文案改为本地化 key。

## Impact

- 所有 Sampler（CPUSampler、GPUSampler、MemorySampler、StorageSampler、NetworkSampler、BatterySampler）指标 name 字段改为英文 key。
- `MonitorModels.swift` 中 `availableMetrics` 的 id 和 title 改为本地化 key。
- `MonitorPanelView.swift` 中 `MetricDetailGrid`、`NetworkGlassRow`、`BatteryGlassRow` 等展示逻辑增加基于模块上下文的翻译。
- `MonitorSettings.swift` 中 `enabledMetrics` 持久化 key 迁移。
- `Localizable.xcstrings` 新增大量英文翻译条目。
- `docs/index.html` 增加语言检测重定向逻辑；`docs/zh/` 与 `docs/en/` 语言页修正相对资源路径并补齐 SEO 元信息。
