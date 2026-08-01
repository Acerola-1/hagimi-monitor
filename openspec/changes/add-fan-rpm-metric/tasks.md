## 1. SMC Sampling Layer

- [x] 1.1 `SMCReader` 新增 `func fanCount() -> Int?`,读 SMC key `FNum`,返回 Int(无风扇返回 nil)
- [x] 1.2 `SMCReader` 新增 `func maxFanRPM() -> Int?`,内部循环读 `F0Ac`...`F{N-1}Ac` 取最大 RPM,任一读取失败跳过(不抛错)
- [x] 1.3 `SMCReader` 新增 `func allFans() -> [(id, currentRPM, minRPM, maxRPM)]`,返回所有风扇完整数据
- [x] 1.4 `FanSMCReading` 协议抽取(fanCount / allFans),`SMCReader` 遵循该协议,支持测试注入 mock
- [x] 1.5 `struct FanInfo: Identifiable, Equatable { id, name, currentRPM, minRPM, maxRPM }` —— 放在 `MonitorModels.swift`
- [x] 1.6 `FanSampler` 新建 `HagimiMonitor/Samplers/FanSampler.swift`:
  - `let smcReader: FanSMCReading?`(协议类型,可注入 mock)
  - 2 秒采样周期
  - `@Published var fans: [FanInfo]` 与 `available: Bool`(fanCount > 0)
  - `@Published var status: FanStatus`(每次采样后更新)
- [x] 1.7 `MonitorStore` 新增 `@Published var fans` / `@Published var fanStatus` 与 `var fanAvailable`
- [x] 1.8 `MonitorStore.init()` 实例化 `FanSampler` 并 `start()`(常驻运行,不随面板显隐启停);`FanAlertService.shared.attach(to:)`
- [x] 1.9 `HagimiMonitor` 与 `HagimiMonitorDirect` 两个 scheme 编译通过

## 2. Fan Health Status Monitoring

- [x] 2.1 `FanStatus` 枚举:`normal` / `warning` / `fault` / `unknown`,遵循 `Comparable`
- [x] 2.2 `FanStatus.rank` / `.severity` / `.title` 属性
- [x] 2.3 `FanInfo.status` 计算属性:基于 RPM vs maxRPM 判断(maxRPM<=0→unknown / RPM==0→fault / RPM>maxRPM→fault / RPM>=85%maxRPM→warning / 其余→normal)
- [x] 2.4 `FanInfo.overallStatus(of:)` 聚合方法:取多风扇最差状态
- [x] 2.5 `FanSampler.sample()` 每次采样后更新 `status` 发布属性
- [x] 2.6 `MonitorStore` 订阅 `fanSampler.$status` 同步到 `fanStatus`

## 3. Alert Mechanism

- [x] 3.1 `FanAlertService` 新建 `HagimiMonitor/Samplers/FanAlertService.swift`
- [x] 3.2 订阅 `FanSampler.$status`,状态升级时发 `UNUserNotification`
- [x] 3.3 去重策略:仅状态升级时触发,同级别不重复;恢复时发恢复通知
- [x] 3.4 首次 attach 请求通知授权(.alert + .sound)
- [x] 3.5 fault 用 `.defaultCritical` 声音,warning 用 `.default` 声音
- [x] 3.6 通知正文含当前 max RPM 数据

## 4. Menu Bar Metric Kind

- [x] 4.1 `MenuBarMetricKind` 新增 `case fanSpeed`
- [x] 4.2 `MenuBarMetricKind` 的 `symbol` 加 `case .fanSpeed: "fan.fill"`
- [x] 4.3 `MenuBarMetricKind` 的 `title` / `menuBarPrefix` 加 `case .fanSpeed`
- [x] 4.4 `userSelectableCases` 由 `static let` 改为 `static func userSelectableCases(hasFan: Bool)`
- [x] 4.5 全局检索 `userSelectableCases` 调用点,统一改为传 `hasFan: store.fanAvailable`
- [x] 4.6 `MenuBarMetricFormatter` 加 `static func fanRPM(_ rpm: Int?) -> String`(`%4d` 格式,>9999 cap,nil 走 unavailable)
- [x] 4.7 `MenuBarStatusLabel.reservedNumericValue` 加 `case .fanSpeed: "9999"`

## 5. Panel Row (GPU 与内存之间)

- [x] 5.1 `MonitorModule.Kind` 新增 `case .fan`,位置在 `.gpu` 之后 / `.memory` 之前
- [x] 5.2 `MonitorModule` 加 `fans: [FanInfo]?` 可选字段
- [x] 5.3 `MonitorStore.applyFanModule()` 合成 `.fan` 模块并插入 allModules(GPU 之后、内存之前)
- [x] 5.4 `MetricGlassRow` 的 `trailingView` 加 `case .fan:` 分支
- [x] 5.5 `FanList` 视图:按实际风扇数量动态渲染行数(无占位行),每行 name / currentRPM / min-max 比例条
- [x] 5.6 `FanList` 加状态指示点(按 `FanStatus.severity` 着色)
- [x] 5.7 `FanList` RPM 数值与比例条在 fault/warning 状态用 severity 色
- [x] 5.8 单风扇(fans.count <= 1)禁用展开区:主行已展示 RPM,点击不触发展开
- [x] 5.9 `visibleModules` 过滤修复:`.fan` 绕过 `visibleKinds` 门控(由 `applyFanModule` 的 `fanAvailable` 自动控制)

## 6. Settings UI 联动

- [x] 6.1 `GeneralSettingsView` 的指标选择 Picker 调用 `userSelectableCases(hasFan:)`
- [x] 6.2 已选 `fanSpeed` 的用户降级为 unavailable(不自动移除)
- [x] 6.3 菜单栏中已选但 unavailable 的 `fanSpeed` 显示占位(不崩)

## 7. Localization

- [x] 7.1 `Localizable.xcstrings` 加菜单栏 / 面板风扇 strings(中英文)
- [x] 7.2 风扇状态标题:`fan.status.normal` / `fan.status.warning` / `fan.status.fault` / `fan.status.unknown`
- [x] 7.3 告警通知标题与正文:`fan.alert.fault.title` / `fan.alert.fault.body` / `fan.alert.warning.title` / `fan.alert.warning.body` / `fan.alert.recovery.title` / `fan.alert.recovery.body`

## 8. Tests

- [x] 8.1 `FanStatusTests`:`FanInfo.status` 全分支覆盖(normal / warning / fault / unknown + 边界值)
- [x] 8.2 `FanOverallStatusTests`:空数组 / 单风扇 / 多风扇最差值聚合
- [x] 8.3 `FanStatusComparableTests`:Comparable 排序 + severity 映射
- [x] 8.4 `FanSamplerTests`:注入 `MockFanSMCReader`,验证 available 门控 / 采样输出 / 命名规则 / 状态更新
- [x] 8.5 `FanRPMFormatterTests`:正常值 / nil / 0 / 9999 / >9999 cap
- [x] 8.6 `FanSelectableCasesTests`:`userSelectableCases(hasFan:)` 过滤行为
- [x] 8.7 全部 35 个测试通过

## 9. Verification

- [x] 9.1 `HagimiMonitor` scheme 编译通过
- [x] 9.2 `HagimiMonitorDirect` scheme 编译通过
- [x] 9.3 完整测试套件通过(TEST SUCCEEDED)
- [x] 9.4 `./launch.sh dev direct` 构建并启动成功,app 稳定运行无崩溃
- [x] 9.5 FanSampler 在 init 中常驻启动,后台 2s 采样 + 告警服务运行
- [ ] 9.6 真机验证(借 Mac Pro 或 Studio):多风扇场景,主行 max RPM 正确,展开 5 行样式
- [ ] 9.7 验证 MacBook Air(无风扇):设置无风扇选项,面板无风扇行
- [ ] 9.8 提交 commit,`openspec archive add-fan-rpm-metric`
