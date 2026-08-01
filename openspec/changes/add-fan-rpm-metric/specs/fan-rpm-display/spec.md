# Capability: fan-rpm-display

## Purpose

为 HagimiMonitor 增加**风扇转速**端到端支持:SMC 采样、单值菜单栏指标、面板行 + 展开列所有风扇、设置联动隐藏/降级、**风扇健康状态监控与异常告警**。

## Requirements

### SMC Sampling

- `SMCReader.fanCount() -> Int?` MUST 读 SMC key `FNum`,返回机器物理风扇数;key 不存在或读取失败时返回 nil。
- `SMCReader.maxFanRPM() -> Int?` MUST 在 `fanCount() > 0` 时循环读 `F0Ac`...`F{N-1}Ac` 取最大 RPM;任一 key 读失败 MUST 跳过(不抛错);全部失败或最大值为 0 时返回 nil。
- `SMCReader.allFans()` MUST 返回所有风扇的 (id, currentRPM, minRPM, maxRPM) 元组数组;任一字段读取失败用 0 占位。
- `SMCReader` MUST 遵循 `FanSMCReading` 协议(fanCount / allFans),以支持测试注入 mock。
- `FanSampler` MUST 缓存 `fanCount` 结果,后续采样 MUST NOT 重复读 `FNum`(它是机器静态属性)。
- `FanSampler` MUST 周期采样,周期 SHOULD 为 2 秒(风扇响应慢,无需高频)。
- `FanSampler` MUST 在 `MonitorStore.init()` 中启动并常驻运行(不随面板显隐启停),以支持后台告警。

### Fan Health Status Monitoring

- `FanStatus` 枚举 MUST 定义四种状态:`normal` / `warning` / `fault` / `unknown`,并遵循 `Comparable`(按严重度排序)。
- `FanInfo.status` MUST 根据当前 RPM 与 maxRPM 判断状态:
  - `maxRPM <= 0` → `unknown`(传感器数据不足)
  - `currentRPM == 0` → `fault`(停转)
  - `currentRPM > maxRPM` → `fault`(传感器读数异常)
  - `currentRPM >= 85% * maxRPM` → `warning`(接近满载)
  - 其余 → `normal`
- `FanInfo.overallStatus(of:)` MUST 返回多风扇中最差的状态(用于整体风扇系统健康度)。
- `FanSampler` MUST 在每次采样后发布 `status: FanStatus`(取所有风扇最差值)。
- `MonitorStore` MUST 暴露 `@Published fanStatus: FanStatus` 供 UI 订阅。

### Alert Mechanism

- `FanAlertService` MUST 订阅 `FanSampler.$status`,在状态恶化时发送 macOS 用户通知。
- 告警 MUST 仅在状态「升级」(更严重)时触发;同一级别 MUST NOT 重复通知。
- 状态从 `warning`/`fault` 恢复到 `normal` 时 MUST 发送恢复通知。
- `unknown` 状态 MUST NOT 触发任何通知。
- 首次 attach 时 MUST 请求 `UNUserNotificationCenter` 授权(.alert + .sound);被拒后静默跳过。
- `fault` 告警 MUST 使用 `.defaultCritical` 声音;`warning` 告警 MUST 使用 `.default` 声音。

### Menu Bar Metric

- `MenuBarMetricKind.fanSpeed` MUST 在 `fanAvailable == true` 时出现在 `userSelectableCases(hasFan:)` 列表;`fanAvailable == false` 时 MUST NOT 出现。
- `MenuBarMetricFormatter.fanRPM(_:)` MUST 输出 4 字符右对齐数字:`%4d` 格式,> 9999 cap 到 9999,nil 走 `unavailable` 占位。
- 菜单栏中"风扇"指标的渲染 MUST 沿用现有 `MenuBarStatusLabel` 的 4 字符定宽 + 等宽数字机制,数字变化 MUST NOT 引起菜单栏宽度抖动。

### Panel Row

- `MonitorModule.Kind.fan` MUST 仅在 `fanAvailable == true` 时被插入面板模块列表;插入位置 MUST 固定在 GPU 之后、内存之前。
- 风扇主行 MUST 复用 `MetricGlassRow` 模板:icon(🌀 fan.fill)+ 标题 "Fan" + 当前 max RPM + 可选 sparkline。
- 风扇主行 MUST 可点击展开,展开后 MUST 列出所有风扇,每行 MUST 显示:name / currentRPM / min-max 比例条 / 状态指示点。
- 状态指示点 MUST 按 `FanStatus.severity` 着色:fault=红 / warning=橙 / normal=绿 / unknown=灰。
- RPM 数值与比例条 MUST 在 fault/warning 状态下使用 severity 色,normal/unknown 使用模块默认色。
- 单风扇机型(风扇数 = 1)MUST NOT 显示展开区(主行已展示 RPM,展开无意义);点击主行 MUST NOT 触发展开切换。
- 多风扇机型(风扇数 >= 2)展开区 MUST 按实际风扇数量动态渲染行数(无占位行、无固定行数上限)。
- 无风扇机型面板中 MUST NOT 出现风扇行(避免空行)。

### Settings Integration

- `GeneralSettingsView` 的指标选择 Picker MUST 调用 `userSelectableCases(hasFan: store.fanAvailable)`,选项 MUST 随 `fanAvailable` 变化动态隐藏/显示。
- 已选中 `fanSpeed` 的用户在 `fanAvailable` 变为 false 时,设置 MUST NOT 自动从 `menuBarMetricKinds` 移除已选项(降级为 unavailable 状态),等用户手动取消。
- 菜单栏中已选但 unavailable 的 `fanSpeed` MUST 显示 `unavailable` 占位(不崩、不消失)。

### Localization

- 所有新用户可见字符串 MUST 中英文双语支持:`menu-bar-metric.fan-speed` / `menu-bar-metric-prefix.fan-speed` / `panel.module.fan` / `panel.fan.unavailable`。
- 风扇状态标题 MUST 中英文双语支持:`fan.status.normal` / `fan.status.warning` / `fan.status.fault` / `fan.status.unknown`。
- 告警通知标题与正文 MUST 中英文双语支持:`fan.alert.fault.title` / `fan.alert.fault.body` / `fan.alert.warning.title` / `fan.alert.warning.body` / `fan.alert.recovery.title` / `fan.alert.recovery.body`。

### Testing

- `FanInfo.status` MUST 有单元测试覆盖所有状态分支(normal / warning / fault / unknown)及边界值。
- `FanInfo.overallStatus(of:)` MUST 有单元测试覆盖空数组、单风扇、多风扇最差值聚合。
- `FanStatus` Comparable 排序与 severity 映射 MUST 有单元测试。
- `FanSampler` MUST 有集成测试(注入 `MockFanSMCReader`):验证 available 门控、采样输出、命名规则、状态更新。
- `MenuBarMetricFormatter.fanRPM` MUST 有单元测试:正常值、nil、0、9999、>9999 cap。
- `userSelectableCases(hasFan:)` MUST 有单元测试:hasFan=true/false 的过滤行为。
