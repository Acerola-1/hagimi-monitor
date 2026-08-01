## Why

HagimiMonitor 当前覆盖了 CPU / GPU / 内存 / 存储 / 网络 / 电池 / 电源七类传感器,**唯独缺风扇转速**——这是热管理反馈链的最后一环:用户已经能看到 CPU 温度,却看不到系统为散热付出的风扇响应。多风扇机型(Mac Pro / Mac Studio)尤其需要这一指标。

但风扇不是普通传感器:
- **机型依赖**:MacBook Air 等无风扇机型根本没有该指标,直接显示会出丑
- **数量可变**:1 风扇(老款 iMac / Mac mini)到 N 风扇(Mac Pro 8 风扇)不等
- **菜单栏 vs 面板的展示需求不同**:菜单栏只能塞 1 个数字,面板可以铺开所有风扇

参考开源实现 [exelban/Stats](https://github.com/exelban/stats)(本机 `docs/` 未归档源码,已 clone 到 `/tmp/stats` 临时分析),其 `SMC/smc.swift` + `Modules/Sensors/readers.swift` 的处理模式被广泛验证:用 SMC `FNum` 检测风扇数,用 `F0Ac`/`F1Ac`/... 读 RPM,无风扇机型直接跳过加载。

## What Changes

### 数据层:SMC 风扇读取
- `SMCReader` 新增 `fanCount() -> Int?`(读 `FNum`)和 `maxFanRPM() -> Int?`(读 `F0Ac`...`F{N-1}Ac` 取最大值)
- 新增 `FanSampler`(`HagimiMonitor/Samplers/FanSampler.swift`),周期采样并发布到 `MonitorStore`
- `MonitorStore` 暴露 `fanAvailable: Bool`(fanCount > 0)与 `fanRPMs: [FanInfo]`(各风扇原始数据)

### 菜单栏指标
- `MenuBarMetricKind` 新增 `case fanSpeed`,默认 4 字符格式 `"1200"`(右对齐数字,无单位,9999 作安全上限)
- `MenuBarMetricFormatter` 新增 `fanRPM(_:) -> String`
- 菜单栏中"风扇"选项**仅在 `fanAvailable` 为 true 时出现在 `userSelectableCases` 列表中**,无风扇机型设置里看不到该选项
- `userSelectableCases` 由 `static let` 改为 `static func(hasFan: Bool)`,这是本次变更对现有架构的**唯一结构性改动**

### 面板行(GPU 和内存之间,顺序固定)
- `MonitorModule.Kind` 新增 `case .fan`,主行复用 `MetricGlassRow` 模板:`🌀 Fan: <max RPM> RPM + sparkline`
- 面板默认隐藏风扇行(避免无风扇机型显示空行),仅 `fanAvailable` 为 true 时插入到 GPU 行下方
- 展开后列出所有风扇,每行:`<name> <current RPM> <min-max 条>`
- `MonitorModule` 扩展 `fans: [FanInfo]?` 字段(仅 fan 模块有值)
- 新增 `FanInfo` 结构:`id`, `name`, `currentRPM`, `minRPM`, `maxRPM`

### 设置联动
- `GeneralSettingsView` 的指标选择列表从 `userSelectableCases` 改 `userSelectableCases(hasFan:)`
- `MonitorStore` 暴露 `fanAvailable`,UI 订阅并实时隐藏/显示选项
- 已选中 `fanSpeed` 的用户从有风扇机迁移到无风扇机时,选项消失但**不自动移除用户已选**(降级为 unavailable,菜单栏显示占位)

### Capabilities

#### New Capabilities
- `fan-rpm-display`: 风扇转速指标端到端支持——SMC 采样、菜单栏单值显示、面板行 + 展开列所有风扇、设置联动隐藏/降级。

#### Modified Capabilities
- `menu-bar-metric-display`: 增加 `fanSpeed` 到可选指标列表,以及对应的"无风扇机型自动隐藏"行为。
- `menu-bar`: 菜单栏布局不改变(已选指标数 / 顺序 / 4 字符定宽等约束不变),仅新增可选 kind。
- `monitor-panel`: 在 GPU 和内存之间插入风扇行(仅可用机型可见),展开样式与 CPU/GPU 等现有 MetricGlassRow 行为一致。

## Impact

- **新增文件**:
  - `HagimiMonitor/Samplers/FanSampler.swift`(~50 行)
- **修改文件**:
  - `HagimiMonitor/Samplers/SMC.swift`(+ `fanCount()` / `maxFanRPM()`,~30 行)
  - `HagimiMonitor/MonitorModels.swift`(加 `fanAvailable` / `fanRPMs` / `FanInfo`,~25 行)
  - `HagimiMonitor/MenuBarDisplayModels.swift`(加 `case fanSpeed` + formatter + `userSelectableCases` 改函数,~30 行)
  - `HagimiMonitor/MenuBarStatusLabel.swift`(加 `.fanSpeed` 预留分支,~5 行)
  - `HagimiMonitor/MonitorPanelView.swift`(加 `case .fan` 主行 + `FanList` 展开视图,~80 行)
  - `HagimiMonitor/Views/Settings/GeneralSettingsView.swift`(选单传 `hasFan` 参数,~5 行)
  - `HagimiMonitor/Localizable.xcstrings`(中英文 strings,~20 项)
- **架构改动**:仅 `userSelectableCases` 由 `static let` → `static func`,全局检索调用点并传 `hasFan`。
- **依赖**:无新外部依赖;SMC 基础设施已有,仅复用 `IOServiceGetMatchingServices("AppleSMC")`。
- **构建**:HagimiMonitor 与 HagimiMonitorDirect 两个 scheme 编译通过。App Store 沙盒版(`ENABLE_APP_SANDBOX = YES`)下 SMC 风扇读取在 macOS 13+ 已无需特殊 entitlement(走 `AppleSMC` IOService 公共接口,与你已有 CPU 温度路径一致)。
- **平台兼容**:Apple Silicon 全系可用;Intel Mac 若用户的 `SMC` 路径已通(参考 Stats 实现),风扇读取同源,无需特殊处理。MacBook Air / 12" MacBook 等无风扇机型:FNum 返回 nil,`fanAvailable = false`,UI 全部隐藏,不影响其它功能。
- **在途改动协调**:无。`harden-code-quality` P0 已 commit(bdd96faa),P1/P2 暂未动;本次提案独立。
