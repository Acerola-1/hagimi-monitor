## Context

蓝牙模块当前组合 IOBluetooth、CoreBluetooth 与 system_profiler 三路数据源，但存在设备类型误判、同名设备错误绑定、电量越界、停止后旧回调重新发布、App Store 引用非公开 API 等问题。需要分阶段收紧正确性、可靠性、覆盖范围与代码结构。

## Goals / Non-Goals

**Goals:**

- 修正 Class of Device 位域解析与电量范围校验
- 实现无歧义的设备身份合并与持久绑定失效机制
- 隔离 App Store 私有 getter，确保渠道合规
- 支持 BLE 设备的 Notify 与低频主动读取
- 区分探针成功空结果与执行失败，保留最近有效数据
- 增加生命周期 token，丢弃停止后的旧回调
- 多 Battery Service 实例确定聚合
- 拆分 800 行采样器为职责清晰的模块
- 收紧日志隐私，完善无障碍语义

**Non-Goals:**

- 不尝试通用解析厂商私有蓝牙电量协议
- 不通过持续无过滤扫描提高覆盖率
- 不在本轮扩大 UI 范围（如分别显示左/右/充电仓电量）

## Decisions

### Decision 1: 分四阶段执行

- **第一阶段**：修复明确问题（CoD 解析、电量校验、同名绑定、渠道隔离）
- **第二阶段**：提高读数可靠性（BLE Notify/Read、探针结果区分、生命周期 token、控制器状态、绑定失效）
- **第三阶段**：扩大覆盖能力（多 Battery Service、名称类型判断优化）
- **第四阶段**：结构与隐私整理（拆分采样器、线程边界、日志隐私、无障碍）

理由：先正确性再扩展，符合小步验证原则；每阶段完成后双版构建验证。

### Decision 2: Class of Device 解析使用 SDK 常量

依据 `kBluetoothDeviceClassMinorPeripheral1*` 常量：
- Keyboard: 0x10
- Pointing: 0x20
- Combo: 0x30

低位掩码 0x3C（而非错误的 0xC0）。

### Decision 3: 电量校验统一为 0-100

GATT 2A19 和 IOBluetooth 均只接受 0-100，拒绝 101-255。无效数据不覆盖最近有效值。

### Decision 4: 同名设备绑定要求两侧唯一

只在 IO 侧和 BLE 侧均唯一时才允许学习绑定。相似名称匹配要求唯一最佳候选，且一个候选不能被多个快照消费。

### Decision 5: 私有 getter 用 DIRECT_DISTRIBUTION 条件编译

`batteryPercentSingle`、`batteryPercentCombined` 等 KVC getter 只在 `#if DIRECT_DISTRIBUTION` 下编译。App Store 版接受部分经典蓝牙设备无法显示电量的限制。

### Decision 6: 探针结果引入明确类型

`ProbeResult` 枚举：`.success(snapshot)` / `.failure`。失败时保留最近有效结果，成功空列表时才清空。

### Decision 7: 生命周期 generation token

`start()` 递增 generation，所有异步回调捕获当前 generation，`stop()` 后到达的回调因 generation 不匹配被丢弃。

### Decision 8: 多 Battery Service 聚合规则

按"外设 + service instance"保存读数。UI 只显示一个数字时，取全部有效读数的最低值（或已佩戴单元的最低值，如能识别）。

## Risks / Trade-offs

- **App Store 电量覆盖下降**：移除私有 getter 后，部分经典蓝牙耳机只能显示设备无法显示电量 → 接受该限制，Direct 版保留兜底
- **重构风险**：拆分 800 行采样器可能引入回归 → 分阶段执行，每阶段双版构建 + 测试验证
- **多 Battery Service 复杂度**：聚合规则可能不符合所有设备行为 → 先实现最低值聚合，后续根据实测调整
