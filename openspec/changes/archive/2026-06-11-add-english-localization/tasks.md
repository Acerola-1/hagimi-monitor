## 1. Sampler 指标 key 英文化

- [x] 1.1 CPUSampler: 指标 name 改为英文 key（system, user, idle, uptime, temperature；temperature 遵守温度功能可用性）
- [x] 1.2 GPUSampler: 指标 name 改为英文 key（gpu-memory, allocated, render, tiler, temperature；temperature 遵守温度功能可用性）
- [x] 1.3 MemorySampler: 指标 name 改为英文 key（used, pressure, swap-used, total）
- [x] 1.4 StorageSampler: 指标 name 改为英文 key（used, free, total）
- [x] 1.5 NetworkSampler: 指标 name 改为英文 key（ip-address, upload, download）
- [x] 1.6 BatterySampler: 指标 name 改为英文 key（charging-power, health, cycle-count, temperature, adapter, power），状态值改为英文 key
- [x] 1.7 MemorySampler: 压力等级 title 改为英文 key（normal, warning, critical）
- [x] 1.8 Utils.swift placeholderModule: 指标 name 改为英文 key

## 2. Models 层英文化

- [x] 2.1 MonitorModels: `HaloRingSource.title` 改为 `String(localized:)`
- [x] 2.2 MonitorModels: `MonitorKind.title` 改为 `String(localized:)`
- [x] 2.3 MonitorModels: `MonitorKind.availableMetrics` id 改为英文 key，title 改为 `String(localized:)`
- [x] 2.4 MonitorModels: `MonitorSeverity.title` 改为 `String(localized:)`
- [x] 2.5 MonitorModels: `MonitorModule.placeholder` 指标 name 改为英文 key
- [x] 2.6 MonitorSettings: `enabledMetrics` 持久化 key 改为英文，添加按模块执行的中文→英文迁移逻辑
- [x] 2.7 MonitorSettings: 主题/配色枚举 title 改为 `String(localized:)`
- [x] 2.8 MonitorSettings: 迁移逻辑处理旧中文 key 与新英文 key 混合存在、去重、最多 4 项上限、`resetMetrics(for:)` 默认值恢复

## 3. View 层英文化

- [x] 3.1 MonitorPanelView: 硬编码中文文案改为 `String(localized:)`（活动监视器、设置、系统盘、网络、电源等）
- [x] 3.2 MonitorPanelView: 新增统一 metric label helper，按 `metric.<kind>.<id>` 翻译，禁止直接用 `String(localized: metric.name)`
- [x] 3.3 MonitorPanelView: `NetworkGlassRow` 展示逻辑增加翻译
- [x] 3.4 MonitorPanelView: `BatteryGlassRow` 展示逻辑增加翻译（电池状态、充电中、外接电源等）
- [x] 3.5 MonitorPanelView: `StorageVolumeDetailList` 卷名称和标签增加翻译
- [x] 3.6 HagimiMonitorApp: 菜单栏按钮文案改为 `String(localized:)`
- [x] 3.7 MonitorPanelView: 验证跨模块重名指标（used/total/temperature）展示为对应模块语义

## 4. Settings View 英文化

- [x] 4.1 SettingsSidebar: 侧栏导航项改为 `String(localized:)`
- [x] 4.2 GeneralSettingsView: 所有文案改为 `String(localized:)`
- [x] 4.3 ModuleSettingsView: 所有文案改为 `String(localized:)`
- [x] 4.4 AboutSettingsView: 所有文案改为 `String(localized:)`
- [x] 4.5 DisplayModuleSettingsView: 所有文案改为 `String(localized:)`（如存在）

## 5. Localizable.xcstrings 翻译填充

- [x] 5.1 添加所有 Sampler 指标名称的中英文翻译（~40 个 key）
- [x] 5.2 添加所有 UI 文案的中英文翻译（~30 个 key）
- [x] 5.3 添加所有设置页面文案的中英文翻译（~20 个 key）
- [x] 5.4 添加错误提示和状态文本的中英文翻译（~10 个 key）
- [x] 5.5 验证所有 `String(localized:)` 调用在 xcstrings 中均有对应 key
- [x] 5.6 添加 CPU/GPU 温度相关翻译 key（metric.cpu.temperature / metric.gpu.temperature），并确认默认勾选状态遵守 `isDefault`

## 6. UpdateChecker 英文化

- [x] 6.1 UpdateChecker: 所有错误提示文案改为 `String(localized:)`
- [x] 6.2 UpdateChecker: 状态描述文案改为 `String(localized:)`

## 7. docs 官网双语

- [x] 7.1 创建 `docs/zh/index.html`，复制当前 `docs/index.html` 内容
- [x] 7.2 创建 `docs/en/index.html`，翻译所有文案为英文
- [x] 7.3 修改 `docs/index.html` 为语言检测重定向页面（自动检测 + localStorage 优先）
- [x] 7.4 在 zh 和 en 页面右上角添加语言切换按钮
- [x] 7.5 语言切换按钮写入 localStorage 并跳转
- [x] 7.6 修正语言页资源路径：`images/...`、favicon、截图、Star chart 等在 `docs/zh/` 和 `docs/en/` 下均可加载
- [x] 7.7 为 zh/en 页面补齐 `html lang`、本地化 title/description、`hreflang`、canonical、JSON-LD
- [x] 7.8 根 `docs/index.html` 的 localStorage 读取使用 `try/catch`，并提供 `<noscript>` 中英文入口

## 8. README 双语

- [x] 8.1 创建 `README.en.md`，翻译原 README.md 为英文
- [x] 8.2 在 README.md 顶部添加英文版本链接

## 9. 验证与清理

- [ ] 9.1 系统语言切英文，验证所有界面文案显示英文
- [ ] 9.2 系统语言切中文，验证所有界面文案显示中文
- [ ] 9.3 验证设置中的指标勾选状态在语言切换后保持不变
- [ ] 9.4 验证旧版中文 key 的设置数据正确迁移到英文 key
- [x] 9.5 构建项目，确保无编译错误
- [ ] 9.6 运行测试，确保无回归
- [ ] 9.7 单元测试覆盖 enabledMetrics 中文→英文迁移：CPU/GPU 温度、跨模块重名 key、混合旧/新 key、超过 4 项上限
- [ ] 9.8 验证 docs/zh/ 与 docs/en/ 的图片、favicon、导航锚点、语言切换、无 JS 入口均可用
