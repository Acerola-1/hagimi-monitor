## Purpose

Provides granular, component-level real-time power telemetry for internal display, CPU, and GPU via private libIOReport on non-sandboxed Direct distribution builds, complete with UI presentation, settings customization, and dual-language localization.

## ADDED Requirements

### Requirement: libIOReport 分项功耗采样与流向红线
在 Direct（非沙盒）版本中，系统 SHALL 通过 `libIOReport` 差分采样读取内建显示屏、CPU 与 GPU 的实时功耗指标；同时修复电池放电负电流在 UInt64 解析下的溢出问题。**电池充放电流向判定 SHALL 严格仅依据 IOPS 状态键（`kIOPSIsChargingKey`/`kIOPSPowerSourceStateKey`），绝不以电流或功率符号判定流向**。

#### Scenario: 成功读取分项功耗
- **WHEN** 应用以 Direct 目标运行且处于 Apple Silicon 硬件上
- **THEN** 电池模块成功采样屏幕功耗、CPU 功耗、GPU 功耗三个指标
- **AND** 数值单位均为瓦特（W），精度为小数点后一位

#### Scenario: 采样基线首帧与异常保护
- **WHEN** 处于应用启动首帧、系统睡眠恢复或单次差分间隔超过 30 秒
- **THEN** 系统暂不输出瞬态差分值，并在下一个采样周期重新建立能量基线
- **AND** 避免输出负数或因计数器溢出导致的异常超大功耗

#### Scenario: 电池负电流补码修复不破坏流向
- **WHEN** 设备在电池供电下放电且系统底层上报负瞬时电流
- **THEN** 电流与功率数值正确转换为正数幅值展示，消除数万 mA 溢出大数
- **AND** 流向判定依然正确显示为放电态

### Requirement: 分项功耗展开区 UI 呈现与沙盒隔离
分项功耗指标 SHALL 在 Direct 版本的电池/电源展开区指标格中呈现，App Store 沙盒版本 SHALL 自动隐藏分项指标，不产生留白或假数据。

#### Scenario: 展开区呈现分项指标
- **WHEN** 用户在 Direct 版展开电池/电源模块且开启了分项功耗开关
- **THEN** 展开区网格按登记顺序渲染屏幕功耗、CPU 功耗与 GPU 功耗指标格
- **AND** 在沙盒 App Store 版本中这些指标完全不渲染

### Requirement: 分项功耗设置开关与静态登记
分项功耗指标 SHALL 在设置页面的电源模块中支持独立开关并持久化，在中英双语 `Localizable.xcstrings` 中齐备本地化文案，并在指标格静态宽度表中按 120pt 半格预算登记最坏值契约并通过构建期审计。

#### Scenario: 设置中配置分项功耗与本地化
- **WHEN** 用户在设置中打开电源模块配置
- **THEN** 屏幕功耗、CPU 功耗、GPU 功耗可独立勾选或取消勾选
- **AND** 在中英文环境下均显示对应规范文案
- **AND** 勾选状态持久化保存，重启应用后维持选择
