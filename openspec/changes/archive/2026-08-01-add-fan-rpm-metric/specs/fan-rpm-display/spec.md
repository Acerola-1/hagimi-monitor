# fan-rpm-display Spec Delta

## ADDED Requirements

### Requirement: SMC 风扇采样接口
`SMCReader` SHALL 提供风扇转速采样接口：`fanCount() -> Int?` 读 SMC key `FNum` 返回机器物理风扇数（key 不存在或读取失败返回 nil）；`maxFanRPM() -> Int?` 在 `fanCount() > 0` 时循环读 `F0Ac`...`F{N-1}Ac` 取最大 RPM（任一 key 读失败跳过不抛错，全失败或最大值为 0 返回 nil）；`allFans()` 返回所有风扇的 (id, currentRPM, minRPM, maxRPM) 元组数组（任一字段读取失败用 0 占位）。`SMCReader` MUST 遵循 `FanSMCReading` 协议（fanCount / allFans）以支持测试注入 mock。

#### Scenario: 有风扇机型返回风扇数
- **WHEN** 机器装有风扇且 SMC key `FNum` 可读
- **THEN** `fanCount()` 返回正整数（如 2）
- **AND** `allFans()` 返回对应数量的风扇元组

#### Scenario: 无风扇机型返回 nil
- **WHEN** 机器无风扇（如 MacBook Air）或 `FNum` 读取失败
- **THEN** `fanCount()` 返回 nil
- **AND** `maxFanRPM()` 返回 nil

#### Scenario: 单个风扇 key 读取失败容错
- **WHEN** 多风扇机型中某个 `F{N}Ac` 读取失败
- **THEN** 该风扇被跳过，其余风扇正常返回
- **AND** 不抛出错误

### Requirement: FanSampler 常驻周期采样
`FanSampler` MUST 以 2 秒周期采样风扇数据（风扇响应慢，无需高频），SHALL 缓存 `fanCount` 结果不在后续采样中重复读 `FNum`（机器静态属性）。`FanSampler` MUST 在 `MonitorStore.init()` 中启动并常驻运行，不随面板显隐启停，以支持后台告警。每次采样后 MUST 发布 `fans: [FanInfo]` 与 `available: Bool`（fanCount > 0）。

#### Scenario: 常驻运行不随面板启停
- **WHEN** 用户关闭面板但应用仍在运行
- **THEN** FanSampler 继续 2 秒周期采样
- **AND** 后台告警服务持续工作

#### Scenario: fanCount 仅读一次
- **WHEN** FanSampler 进行多次周期采样
- **THEN** `FNum` 仅在首次采样时读取
- **AND** 后续采样复用缓存的 fanCount

### Requirement: 风扇健康状态判定
`FanStatus` 枚举 SHALL 定义四种状态 `normal` / `warning` / `fault` / `unknown` 并遵循 `Comparable`（按严重度排序）。`FanInfo.status` MUST 根据当前 RPM 与 maxRPM 判定：`maxRPM <= 0` → `unknown`（传感器数据不足）；`currentRPM == 0` → `fault`（停转）；`currentRPM > maxRPM` → `fault`（传感器读数异常）；`currentRPM >= 85% * maxRPM` → `warning`（接近满载）；其余 → `normal`。`FanInfo.overallStatus(of:)` MUST 返回多风扇中最差的状态。

#### Scenario: 各状态分支判定
- **WHEN** maxRPM=3000、currentRPM 分别为 0 / 3100 / 2600 / 1500
- **THEN** 状态依次判定为 fault / fault / warning / normal

#### Scenario: 传感器数据不足
- **WHEN** maxRPM <= 0
- **THEN** 状态判定为 unknown

#### Scenario: 多风扇取最差值
- **WHEN** 三风扇状态分别为 normal / warning / fault
- **THEN** `overallStatus(of:)` 返回 fault

### Requirement: 风扇状态发布与同步
`FanSampler` MUST 在每次采样后发布 `status: FanStatus`（取所有风扇最差值）。`MonitorStore` MUST 暴露 `@Published fanStatus: FanStatus` 与 `fanAvailable: Bool` 供 UI 订阅，并订阅 `FanSampler.$status` 同步到 `fanStatus`。

#### Scenario: 采样后状态即时发布
- **WHEN** FanSampler 完成一次采样且某风扇从 normal 变为 warning
- **THEN** `FanSampler.status` 发布为 warning
- **AND** `MonitorStore.fanStatus` 同步更新为 warning

### Requirement: 风扇异常告警
`FanAlertService` MUST 订阅 `FanSampler.$status`，在状态「升级」（更严重）时发送 macOS 用户通知；同一级别 MUST NOT 重复通知；状态从 `warning`/`fault` 恢复到 `normal` 时 MUST 发送恢复通知；`unknown` 状态 MUST NOT 触发任何通知。首次 attach 时 MUST 请求 `UNUserNotificationCenter` 授权（.alert + .sound），被拒后静默跳过。`fault` 告警 MUST 使用 `.defaultCritical` 声音，`warning` 告警 MUST 使用 `.default` 声音。通知正文 MUST 含当前 max RPM 数据。

#### Scenario: 状态升级触发告警
- **WHEN** 风扇状态从 normal 升级到 warning
- **THEN** 发送 warning 通知，使用 `.default` 声音，正文含当前 max RPM

#### Scenario: 同级别不重复
- **WHEN** 风扇状态持续为 warning（多次采样）
- **THEN** 仅首次升级时通知一次，不重复发送

#### Scenario: 恢复通知
- **WHEN** 风扇状态从 warning 恢复到 normal
- **THEN** 发送恢复通知

#### Scenario: unknown 不告警
- **WHEN** 状态为 unknown
- **THEN** 不触发任何通知

#### Scenario: 授权被拒静默
- **WHEN** 用户拒绝通知授权
- **THEN** 不发送通知且不崩溃

### Requirement: 菜单栏风扇指标
`MenuBarMetricKind.fanSpeed` MUST 在 `fanAvailable == true` 时出现在 `userSelectableCases(hasFan:)` 列表，`fanAvailable == false` 时 MUST NOT 出现。`MenuBarMetricFormatter.fanRPM(_:)` MUST 输出 4 字符右对齐数字（`%4d` 格式，> 9999 cap 到 9999，nil 走 `unavailable` 占位）。菜单栏渲染 MUST 沿用 `MenuBarStatusLabel` 的 4 字符定宽 + 等宽数字机制，数字变化 MUST NOT 引起菜单栏宽度抖动。

#### Scenario: 有风扇时可选
- **WHEN** `fanAvailable == true`
- **THEN** 菜单栏指标选择器包含风扇选项

#### Scenario: 无风扇时不可选
- **WHEN** `fanAvailable == false`
- **THEN** 菜单栏指标选择器不包含风扇选项

#### Scenario: RPM 格式化与定宽
- **WHEN** 风扇 RPM 为 2540 / nil / 12000
- **THEN** 分别渲染为 "2540" / unavailable 占位 / "9999"（cap）
- **AND** 菜单栏宽度不因数值变化抖动

### Requirement: 面板风扇行渲染
`MonitorModule.Kind.fan` MUST 仅在 `fanAvailable == true` 时插入面板模块列表，位置固定在 GPU 之后、内存之前。主行 MUST 复用 `MetricGlassRow` 模板（fan.fill 图标 + "Fan" 标题 + 当前 max RPM + 可选 sparkline）。多风扇机型（>= 2）主行 MUST 可点击展开，展开后按实际风扇数量动态渲染行数（无占位行、无固定上限），每行显示 name / currentRPM / min-max 比例条 / 状态指示点。状态指示点 MUST 按 `FanStatus.severity` 着色（fault=红 / warning=橙 / normal=绿 / unknown=灰）；RPM 数值与比例条 MUST 在 fault/warning 状态用 severity 色，normal/unknown 用模块默认色。单风扇机型（= 1）MUST NOT 显示展开区，点击主行 MUST NOT 触发展开。无风扇机型 MUST NOT 出现风扇行。

#### Scenario: 插入位置固定
- **WHEN** 机器有风扇且面板渲染
- **THEN** 风扇行出现在 GPU 之后、内存之前

#### Scenario: 多风扇展开
- **WHEN** 5 风扇机型用户点击风扇主行
- **THEN** 展开区渲染 5 行，每行含 name / currentRPM / 比例条 / 状态点

#### Scenario: 单风扇不展开
- **WHEN** 单风扇机型用户点击风扇主行
- **THEN** 不触发展开（主行已展示 RPM）

#### Scenario: 无风扇不显示
- **WHEN** 无风扇机型呼出面板
- **THEN** 面板中无风扇行

#### Scenario: 状态着色
- **WHEN** 某风扇状态为 warning
- **THEN** 其状态点为橙、RPM 数值与比例条用 severity 色

### Requirement: 设置页风扇选项联动
`GeneralSettingsView` 的指标选择 Picker MUST 调用 `userSelectableCases(hasFan: store.fanAvailable)`，选项随 `fanAvailable` 变化动态隐藏/显示。已选中 `fanSpeed` 的用户在 `fanAvailable` 变为 false 时，设置 MUST NOT 自动从 `menuBarMetricKinds` 移除已选项（降级为 unavailable 状态），等用户手动取消。菜单栏中已选但 unavailable 的 `fanSpeed` MUST 显示 `unavailable` 占位，不崩不消失。

#### Scenario: 选项随 fanAvailable 变化
- **WHEN** `fanAvailable` 从 true 变为 false
- **THEN** 设置页指标选择器中风扇选项隐藏

#### Scenario: 已选降级不消失
- **WHEN** 用户已选 fanSpeed 后 `fanAvailable` 变为 false
- **THEN** 已选项保留在 `menuBarMetricKinds` 中
- **AND** 菜单栏显示 unavailable 占位而非崩溃

### Requirement: 风扇文案本地化
所有新用户可见字符串 MUST 提供中英文双语支持，包括：菜单栏/面板字符串（`menu-bar-metric.fan-speed` / `menu-bar-metric-prefix.fan-speed` / `panel.module.fan` / `panel.fan.unavailable`）、风扇状态标题（`fan.status.normal` / `fan.status.warning` / `fan.status.fault` / `fan.status.unknown`）、告警通知标题与正文（`fan.alert.fault.title` / `fan.alert.fault.body` / `fan.alert.warning.title` / `fan.alert.warning.body` / `fan.alert.recovery.title` / `fan.alert.recovery.body`）。

#### Scenario: 中英文环境切换
- **WHEN** 系统语言为英文 / 简体中文
- **THEN** 菜单栏、面板、状态标题、告警通知均显示对应语言文案

### Requirement: 风扇功能测试覆盖
风扇功能 MUST 有单元/集成测试覆盖：`FanInfo.status` 全状态分支及边界值；`FanInfo.overallStatus(of:)` 空数组/单风扇/多风扇最差值聚合；`FanStatus` Comparable 排序与 severity 映射；`FanSampler` 注入 `MockFanSMCReader` 验证 available 门控/采样输出/命名规则/状态更新；`MenuBarMetricFormatter.fanRPM` 正常值/nil/0/9999/>9999 cap；`userSelectableCases(hasFan:)` hasFan=true/false 过滤行为。

#### Scenario: 测试套件全通过
- **WHEN** 运行完整测试套件
- **THEN** 所有风扇相关测试通过（TEST SUCCEEDED）
