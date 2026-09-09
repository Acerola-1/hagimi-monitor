## 1. 第一阶段：修复明确问题

- [x] 1.1 修正 Class of Device 类型识别：使用 SDK 常量 kBluetoothDeviceClassMinorPeripheral1*（Keyboard: 0x10, Pointing: 0x20, Combo: 0x30），低位掩码 0x3C；为键盘、鼠标、键鼠组合、手柄、数位板和未知类型补测试；验证 xcodebuild test 通过
- [x] 1.2 校验所有电量输入：GATT 2A19 只接受 0-100，IOBluetooth 接受 0%；无效数据不覆盖最近有效值；补充 0、100、101、255、空数据和读取错误测试；验证测试通过
- [x] 1.3 修复同名设备错误绑定：同名匹配只在两侧均唯一时允许学习绑定；相似名称要求唯一最佳候选且一个候选不能被多个快照消费；增加两个 IO 同名 + 一个 BLE、一个 IO + 两个 BLE 同名、两边各两台同名、已有绑定时改名等测试；重写 doesNotPairAmbiguousSimilarNames；验证测试通过
- [x] 1.4 隔离 App Store 私有 getter：batteryPercentSingle、batteryPercentCombined 等 KVC getter 限制在 #if DIRECT_DISTRIBUTION 下；App Store 渠道只用公开 IOBluetooth 枚举与 CoreBluetooth 标准服务；双 scheme 分别构建，确认 App Store 二进制不包含这些 selector 字符串；验证构建通过

## 2. 第二阶段：提高读数可靠性

- [x] 2.1 支持不提供 Notify 的 BLE 设备：首次发现 2A19 后立即读取；支持 Notify/Indicate 时订阅；仅支持 Read 时按 30-60 秒低频补读；首次读取失败时有限退避重试；不要每 10 秒重新做完整服务发现；验证测试通过
- [x] 2.2 区分探针成功和失败：引入 ProbeResult 枚举（.success(snapshot) / .failure）；超时、启动失败、异常 JSON、沙盒空骨架不清空最近成功结果；成功返回空设备清单时才允许清空；避免同一时间多个 system_profiler 进程；验证测试通过
- [x] 2.3 防止停止后旧回调重新发布：为 start/stop 增加 generation/session token；stop() 后到达的 profiler、BLE 和延迟重试回调丢弃；验证隐藏模块后旧探针不重新写回 MonitorStore；验证快速"隐藏→显示"不混入上一轮数据；验证测试通过
- [x] 2.4 修正控制器状态冲突：CoreBluetooth 最新 .poweredOff 立即覆盖旧 profiler .on 快照；各数据源状态带时间或 generation；测试蓝牙关闭、重新打开、权限拒绝、profiler 超时场景；验证测试通过
- [x] 2.5 处理绑定失效：永久绑定具备版本和最近使用时间；UUID 长期无法召回或明确冲突时移除绑定并重新学习；保留当前 [MAC: UUID] 数据兼容迁移；不因临时离线删除绑定；验证测试通过

## 3. 第三阶段：扩大覆盖能力

- [x] 3.1 明确支持边界：经典蓝牙耳机/音箱/键鼠设备清单可见；标准 GATT 180F/2A19 BLE 设备可读取电量；macOS 自身能提供电量的设备 Direct 版兜底；不通过长期无过滤扫描提高覆盖率；验证文档与代码注释一致
- [x] 3.2 支持多 Battery Service 实例：部分耳机分别暴露左耳、右耳、充电仓；不让多个回调随机覆盖一个 batteryByIdentifier 值；内部按"外设 + service instance"保存读数；UI 只显示一个数字时使用确定聚合规则（如最低电量）；验证测试通过
- [x] 3.3 改善名称和类型判断：优先级 CoD → profiler 元数据 → GAP Appearance → 名称推断；名称关键词只作最后兜底；不为无法确认的设备强行猜测类型；增加日文、中文和常见品牌型号样本；验证测试通过

## 4. 第四阶段：结构与隐私整理

- [x] 4.1 拆分约 800 行采样器：数据模型与解析器、设备身份合并器、IOBluetooth 数据源、profiler 探针、生命周期与发布协调器；合并和解析保持纯函数；验证双版构建通过
- [x] 4.2 明确线程边界：BluetoothBatterySampler 状态和 @Published 发布限定在主线程或 @MainActor；CoreBluetooth 状态只在其串行队列访问；避免无保护的 nonisolated(unsafe) 共享变量；验证无数据竞争警告
- [x] 4.3 收紧日志隐私：设备名称不用 .public；日常日志只记录设备数量、数据源状态和错误类别；调试构建设备名也默认私有隐私级别；验证日志输出符合隐私要求
- [x] 4.4 检查无障碍：每个设备行提供设备名、类型和电量的组合标签；电量条避免 VoiceOver 重复朗读；可展开行提供展开/收起状态和操作提示；未上报电量读作本地化"电量不可用"；验证 VoiceOver 朗读正确

## 5. 最终验证

- [x] 5.1 执行完整测试套件：xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug -destination 'platform=macOS' test；验证所有测试通过
- [x] 5.2 双版构建验证：xcodebuild App Store scheme 和 Direct scheme 分别构建；验证 BUILD SUCCEEDED
- [x] 5.3 验收矩阵场景覆盖：蓝牙关闭/打开、权限未决定/允许/拒绝、模块隐藏后重新显示、经典蓝牙耳机、标准 BLE 键鼠、BLE 仅 Read 无 Notify、私有协议设备、两台同名设备、设备改名和重连、电量 0/100、电量 101/255、profiler 超时或异常 JSON、多 Battery Service；验证所有场景符合预期
