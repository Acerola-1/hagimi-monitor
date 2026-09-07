## Why

蓝牙模块已经组合 IOBluetooth、CoreBluetooth 与 system_profiler 三路数据，但目前仍存在设备类型误判、同名设备错误持久绑定、电量越界或停留在首次读数、停止后的旧回调重新发布，以及 App Store 构建引用非公开电量 getter 等风险。需要把设备身份、读数时效、生命周期和渠道边界收紧，才能在不伪造数据的前提下稳定覆盖常见经典蓝牙与标准 BLE 外设。

## What Changes

- 修正 Class of Device 位域解析与电量范围校验，合法支持 0%–100%，拒绝异常值污染缓存。
- 将设备身份合并改为无歧义的一对一关联；为持久绑定增加失效与重新学习机制，避免同名设备串电量。
- 为标准 BLE Battery Service 同时支持通知与低频主动读取，并以确定规则处理多 Battery Service 实例。
- 区分 profiler 成功空结果与执行失败，保留最近一次有效结果，限制并发探针，并丢弃已停止会话的迟到回调。
- 重新定义控制器状态的证据优先级，使最新的关闭、开启、授权及不支持状态不会被旧快照覆盖。
- 将未公开的 IOBluetooth 电量 getter 限制在 Direct 渠道；App Store 渠道只依赖公开 API 并对不可读取的电量自然降级。
- 收紧设备日志隐私，并完善蓝牙设备行、电量与展开状态的辅助功能语义。
- 建立单元测试、双 scheme 构建检查和跨协议实机矩阵，明确标准协议覆盖范围与厂商私有协议的降级边界。

## Capabilities

### New Capabilities

- `bluetooth-device-monitoring`: 定义蓝牙控制器状态、已连接设备发现、跨数据源身份合并、电量读取与时效、渠道能力边界、隐私降级及面板呈现行为。

### Modified Capabilities

无。

## Impact

- 主要影响 `BluetoothBatterySampler`、`BLEBatteryReader`、蓝牙相关模型与测试。
- 可能调整 `MonitorStore` 的蓝牙状态接入，以及蓝牙设备列表的辅助功能描述；现有视觉结构保持不变。
- App Store 版将不再调用未公开的 IOBluetooth 电量 getter，部分只通过该接口提供电量的经典蓝牙设备会显示“电量不可用”；Direct 版保留该数据源作为系统侧兜底。
- 不新增第三方依赖，不尝试通用解析厂商私有蓝牙电量协议，也不通过持续无过滤扫描把附近设备当作已连接设备。
