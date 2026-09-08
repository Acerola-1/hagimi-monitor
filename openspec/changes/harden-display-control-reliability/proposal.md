## Why

现有外接显示器控制在重复设置、睡眠/重配置、能力探测失败和多屏连接时可能漏发、误禁用或错误匹配；界面又无法区分真实读数与未确认目标，导致兼容性问题难以复现和定位。先建立可验证的控制链路、逐属性能力模型及诊断设施，为后续输入源和厂商扩展提供可靠基础。

## What Changes

- 为显示器身份、连接代次、每项控制能力、值来源和通信状态建立明确模型。
- 改造 DDC 调度：有界请求、最新目标合并、读取让位、过期请求拒绝、故障恢复；不把等待超时视为底层取消。
- 修复去重漏发、门禁解除缺少重放事件、断开后缓存残留和旧结果覆盖新会话。
- 按属性选择 DDC/Apple 原生/软件调光，亮度降级不影响音量和对比度；对未知能力提供手动兼容配置。
- 修复 Gamma 成功反馈、恢复状态与持久化语义；明确显示硬件亮度和软件压暗的区别。
- 加入按显示器配置的读取策略、通信延迟、范围覆盖、重试和诊断导出。
- 将媒体音量键目标绑定到音频输出，提供显式映射；无法确定或不能执行时不吞键。
- 补齐模拟传输、状态机、身份匹配、端到端编排测试以及硬件验收矩阵。
- 本轮保留 Apple Silicon、现有双渠道边界及三个主要参数；不新增输入切换、硬件静音 VCP、电源、RGB、KVM/PBP、自动亮度、通用遮罩或 USB 私有协议后端。这些作为独立后续变更，不属于本轮完成条件。

## Capabilities

### New Capabilities

- `display-control-session`: 设备身份与连接生命周期、命令调度、值来源、恢复和轮询行为。
- `display-control-compatibility`: 逐属性能力、控制后端、兼容配置及媒体键目标路由。
- `display-control-diagnostics`: 状态说明、诊断导出和可复现的兼容性证据。

### Modified Capabilities

- `display-control-correctness`: 软件调光真实结果与恢复、门禁重放覆盖、音量恢复优先级及身份隔离；保留 HDMI 祖先节点适配要求。

## Impact

- 主要文件：`HagimiMonitorDirectOnly/DisplayControlController.swift`、`DisplayDDCBridge.swift`、`DDCEnvironmentGate.swift`、`DDCCapabilityStore.swift`、`DisplayClassifier.swift`、`GammaDimmingController.swift`、`DDCRawConversion.swift`、`MediaKeyController.swift`、`AudioOutputDetector.swift`。
- 共享接线：`HagimiMonitor/Views/Panel/DisplaySection.swift`、显示器相关设置、`Localizable.xcstrings`、`AppDelegate.swift` 的退出恢复；均维持控制代码的条件编译边界。
- 新增纯逻辑及注入式测试，按 Direct scheme 测试；两渠道独立构建，最终重启供用户目测。
- 不引入常驻第三方工具，不以替换 DDC 库作为默认方案，不增加外部联网和自动上传。持久化采用版本化兼容迁移，不复用有歧义的旧屏幕配置。
- 与现有面板动画变更并行存在：只调整显示器控制接线与必要状态展示，不重写运动、几何或卡片系统。
