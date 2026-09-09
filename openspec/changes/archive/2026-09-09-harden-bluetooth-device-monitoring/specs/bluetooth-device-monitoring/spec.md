## Purpose

定义蓝牙控制器状态、已连接设备发现、跨数据源身份合并、电量读取与时效、渠道能力边界、隐私降级及面板呈现行为。

## ADDED Requirements

### Requirement: 设备类型识别基于 Class of Device 位域

系统 SHALL 依据 Bluetooth SDK 的 `kBluetoothDeviceClassMinorPeripheral1*` 常量正确识别外设子类型（Keyboard: 0x10, Pointing: 0x20, Combo: 0x30），不得使用错误的 0xC0 掩码。

#### Scenario: 键盘设备识别

- **WHEN** 设备的 Class of Device 低位掩码为 0x10
- **THEN** 系统识别为键盘类型

#### Scenario: 鼠标设备识别

- **WHEN** 设备的 Class of Device 低位掩码为 0x20
- **THEN** 系统识别为指点设备

#### Scenario: 键鼠组合设备识别

- **WHEN** 设备的 Class of Device 低位掩码为 0x30
- **THEN** 系统识别为键鼠组合设备

### Requirement: 电量输入范围校验

系统 SHALL 只接受 0-100 范围内的电量值，拒绝 101-255 等异常值污染缓存。IOBluetooth 数据源 SHALL 接受合法的 0% 电量。

#### Scenario: GATT 2A19 合法电量

- **WHEN** BLE 设备上报电量值在 0-100 范围内
- **THEN** 系统接受该值并更新显示

#### Scenario: GATT 2A19 异常电量

- **WHEN** BLE 设备上报电量值在 101-255 范围内
- **THEN** 系统拒绝该值，不覆盖最近一次有效读数

#### Scenario: IOBluetooth 零电量

- **WHEN** 经典蓝牙设备上报电量为 0%
- **THEN** 系统接受该值并显示为 0%

### Requirement: 同名设备无歧义绑定

系统 SHALL 只在两侧均唯一时才允许同名设备学习绑定。两台相同型号、相同名称的设备不得任选一台并永久绑定。

#### Scenario: 两个同名 IO 设备与一个 BLE 快照

- **WHEN** 存在两个同名的 IOBluetooth 设备和一个 BLE 快照
- **THEN** 系统不进行学习绑定，避免错误关联

#### Scenario: 一个 IO 设备与两个同名 BLE 快照

- **WHEN** 存在一个 IOBluetooth 设备和两个同名的 BLE 快照
- **THEN** 系统不进行学习绑定，避免错误关联

### Requirement: App Store 渠道不使用私有 API

App Store 渠道 SHALL 只使用公开的 IOBluetooth 枚举与 CoreBluetooth 标准服务，不得引用 `batteryPercentSingle`、`batteryPercentCombined` 等非公开 KVC getter。

#### Scenario: App Store 构建检查

- **WHEN** 构建 App Store scheme
- **THEN** 二进制中不包含私有电量 getter 的 selector 字符串

### Requirement: BLE 设备支持 Notify 和低频主动读取

系统 SHALL 对标准 BLE Battery Service 同时支持通知订阅和低频主动读取。仅支持 Read 的设备 SHALL 按较低频率（30-60 秒）主动补读。

#### Scenario: 支持 Notify 的 BLE 设备

- **WHEN** BLE 设备的 2A19 特征支持 Notify
- **THEN** 系统订阅通知并实时更新电量

#### Scenario: 仅支持 Read 的 BLE 设备

- **WHEN** BLE 设备的 2A19 特征仅支持 Read
- **THEN** 系统按 30-60 秒频率主动读取电量

### Requirement: 探针结果区分成功与失败

系统 SHALL 区分 system_profiler 探针的成功空结果和执行失败。超时、启动失败、异常 JSON 不得清空最近一次成功结果。

#### Scenario: 探针超时

- **WHEN** system_profiler 探针执行超时
- **THEN** 系统保留最近一次有效结果，不清空设备列表

#### Scenario: 探针成功返回空列表

- **WHEN** system_profiler 探针成功执行但返回空设备列表
- **THEN** 系统清空 profiler 设备列表

### Requirement: 停止后丢弃旧回调

系统 SHALL 为 start/stop 生命周期增加 generation/session token。stop() 后到达的回调 MUST 被丢弃。

#### Scenario: 隐藏模块后旧探针回调

- **WHEN** 模块隐藏后旧的 profiler 探针完成
- **THEN** 系统丢弃该回调，不重新发布蓝牙设备状态

### Requirement: 控制器状态最新优先

系统 SHALL 使 CoreBluetooth 最新的 .poweredOff 状态立即覆盖旧的 profiler .on 快照。

#### Scenario: 蓝牙关闭

- **WHEN** CoreBluetooth 报告 .poweredOff
- **THEN** 系统立即更新控制器状态为关闭

### Requirement: 多 Battery Service 确定聚合

系统 SHALL 对多 Battery Service 实例使用确定的聚合规则（如最低电量）。

#### Scenario: 多 Battery Service 实例

- **WHEN** BLE 设备暴露多个 Battery Service 实例
- **THEN** 系统按确定规则聚合电量，不受回调顺序影响

### Requirement: 设备日志隐私保护

系统 SHALL 不在日志中使用 .public 隐私级别记录设备名称。

#### Scenario: 日志输出

- **WHEN** 系统记录蓝牙相关日志
- **THEN** 设备名称使用私有隐私级别

### Requirement: 无障碍语义完整

系统 SHALL 为每个蓝牙设备行提供设备名、设备类型和电量的组合标签。未上报电量 SHALL 读作本地化的"电量不可用"。

#### Scenario: VoiceOver 朗读设备行

- **WHEN** VoiceOver 聚焦到蓝牙设备行
- **THEN** 朗读设备名、类型和电量的组合信息
