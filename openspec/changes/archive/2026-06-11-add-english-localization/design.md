## Context

Hagimi Monitor 目前所有用户界面文案均为中文硬编码，分布在：
- **Sampler 层**：指标名称（"系统"/"用户"/"闲置"...）直接作为展示文本和数据 key 使用
- **View 层**：设置页面、面板、错误提示等 UI 文案
- **docs/index.html**：纯中文静态页面
- **README.md**：纯中文文档

当前已有 `Localizable.xcstrings`（Xcode String Catalog），但仅包含 12 个 key 且只有 zh-Hans 翻译。大部分中文文本尚未接入本地化系统。

## Goals / Non-Goals

**Goals:**
- App 根据系统语言自动显示中文或英文
- Sampler 指标名称改用中性英文 key，展示层通过 `String(localized:)` 翻译
- 用户已有设置数据（`enabledMetrics`）在迁移后保持有效
- README 提供中英文双语版本
- docs 官网支持自动语言检测 + 手动切换，优先使用用户历史选择

**Non-Goals:**
- 支持除中英文以外的其他语言（为后续扩展预留结构）
- 运行时语言热切换（跟随系统，需重启 App）
- 在 App 内提供语言手动选择设置

## Decisions

### Decision 1: Sampler 指标名改用英文 key，并由展示层按模块翻译
**选择**：Sampler 返回的 `MonitorMetric.name` 从中文（"系统"）改为英文 key（"system"）。展示层不得直接使用 `String(localized: metric.name)`，必须通过统一 helper 结合模块上下文翻译，例如 `localizedMetricName(kind: .cpu, id: "system")` 解析为 `String(localized: "metric.cpu.system")`。

**理由**：
- 数据层和展示层解耦，符合国际化最佳实践
- 设置持久化（`enabledMetrics`）使用稳定的英文 key，不受语言切换影响
- 后续加日语、德语等语言时只需新增翻译，无需改代码
- `used`、`total`、`temperature` 等 id 会跨模块复用，模块上下文可避免翻译歧义

**替代方案**：保持中文 key，在 View 层做映射表。Rejected：映射表分散在多个 View 中，维护困难。

**实现约束**：
- `MonitorMetric.name` 暂时继续作为 `Identifiable.id` 使用时，单个模块内必须保持唯一。
- 需要支持 CPU/GPU 温度计划：CPU/GPU `temperature` 均使用同一个内部 id，但展示 key 分别为 `metric.cpu.temperature` / `metric.gpu.temperature`。
- 默认启用项按 `MetricSwitch.isDefault` 决定，不得把所有可用指标无条件默认勾选；温度等 optional 指标保持 unchecked by default。

### Decision 2: `Localizable.xcstrings` 作为唯一翻译源
**选择**：使用 Xcode String Catalog（`.xcstrings`）而非 `.strings` 文件。

**理由**：
- Xcode 15+ 原生支持，自动提取和同步代码中的 `String(localized:)`
- 支持变体（plural、device 等），为未来扩展预留能力
- 可视化编辑，翻译协作友好

### Decision 3: 设置数据迁移策略
**选择**：在 `MonitorSettings` 初始化时检查 `enabledMetrics` 中的 key，将旧版中文 key 映射到新版英文 key。迁移必须按模块执行，因为 `"温度"`、`"已用"`、`"总量"` 等中文 key 在不同模块中可能映射到相同英文 id 但不同本地化展示上下文。

**理由**：
- 避免用户升级后已勾选的指标全部丢失
- 迁移逻辑一次性，后续版本可移除

**映射表**：
```
CPU: "系统" → "system", "用户" → "user", "闲置" → "idle", "启动时间" → "uptime", "温度" → "temperature"
GPU: "GPU内存" → "gpu-memory", "已分配" → "allocated", "渲染" → "render", "分块" → "tiler", "温度" → "temperature"
Memory: "已用" → "used", "压力" → "pressure", "交换已用" → "swap-used", "总量" → "total"
Storage: "已用" → "used", "可用" → "free", "总量" → "total"
Network: "IP 地址" → "ip-address", "上传" → "upload", "下载" → "download"
Battery: "充电功率" → "charging-power", "健康度" → "health", "循环数" → "cycle-count", "温度" → "temperature", "适配器" → "adapter", "功耗" → "power"
```

**边界处理**：
- 如果旧中文 key 与新英文 key 混合存在，合并为英文 key set 并去重。
- 迁移后不得因旧数据超过 4 项而破坏当前最多 4 项选择约束；超出时保留前 4 个仍可用指标，并允许用户重新调整。
- `resetMetrics(for:)` 使用新版 `isDefault` 英文 id，不恢复旧中文 key。

### Decision 4: docs 官网语言方案
**选择**：根目录 `docs/index.html` 做轻量语言检测并重定向到 `docs/zh/` 或 `docs/en/`，右上角提供手动切换按钮，选择写入 localStorage。

**理由**：
- 两个完整页面各自维护，无运行时内容替换的闪烁问题
- 支持 SEO（每个语言独立 URL）
- localStorage 优先于浏览器语言，尊重用户选择

**替代方案**：单页 JS 动态替换内容。rejected：内容多时代码复杂，首次加载有语言检测延迟。

**实现约束**：
- `docs/zh/index.html` 与 `docs/en/index.html` 从 `docs/index.html` 下沉一层后，所有相对资源路径必须从 `images/...` 改为 `../images/...`，或改为站点根相对路径，避免图片和 favicon 失效。
- 两个语言页必须分别设置 `<html lang="zh-CN">` / `<html lang="en">`、本语言 `title` / `meta description`、`rel="alternate" hreflang="zh-CN"`、`rel="alternate" hreflang="en"`、canonical。
- JSON-LD 中 `description`、`offers.priceCurrency` 等语言/地区相关字段按页面语言维护。
- 根跳转页读取 localStorage 必须使用 `try/catch`，隐私模式或禁用存储时回退到 `navigator.languages` / `navigator.language`。
- 根跳转页提供 `<noscript>` 中文/英文链接，禁用 JS 时仍可进入站点。

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| Sampler key 改动导致设置数据丢失 | 初始化时做中文→英文 key 迁移 |
| 跨模块 metric id 重名导致翻译错误 | 所有 metric label 通过 `metric.<kind>.<id>` helper 翻译 |
| CPU/GPU 温度计划与本地化计划不一致 | 本计划同步包含 `temperature` id 与 CPU/GPU 温度本地化 key；默认是否勾选遵守各指标 `isDefault` |
| 英文翻译质量不佳 | 先提供基础翻译，后续通过社区 PR 迭代优化 |
| `Localizable.xcstrings` 文件体积增大 | 只有中英文两种语言，key 数量约 50-80 个，体积可控 |
| docs 维护两套页面导致更新不同步 | 内容结构一致，修改时同步更新两份，并通过 hreflang/canonical 显式维护语言关系 |
| docs 语言页资源路径失效 | 创建语言页时统一修正 `images/...` 到 `../images/...` 或根相对路径 |

## Migration Plan

1. **代码改动阶段**：Sampler、Models、Views 全部改为英文 key
2. **翻译填充阶段**：`Localizable.xcstrings` 新增英文翻译
3. **数据迁移阶段**：`MonitorSettings` 增加中文 key → 英文 key 的兼容逻辑
4. **文档阶段**：README.en.md + docs/en/index.html
5. **验证阶段**：系统语言切英文，检查所有界面文案

## Open Questions

- CPU/GPU 温度的 App Store target 可用性由 `add-cpu-gpu-temperature` 变更负责；本计划只负责温度指标 id 与文案本地化。
