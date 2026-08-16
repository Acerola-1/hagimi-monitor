# Tasks: AI Insights & App Intents

> 状态：**全部未开始（Hold）**。触发条件：国行 Apple Intelligence 上线（Phase 2）；Phase 1 如决定提前，拆为独立 change 后按 §1 推进。

## 0. 前置验证（解除 Hold 后第一件事）
- [ ] 在目标系统（届时正式版 macOS）验证 `SystemLanguageModel.default.availability` 的国行返回值与错误原因枚举
- [ ] 跑通最小 `LanguageModelSession` 单轮问答 Demo，确认纯文本输出稳定、无 release notes 中的 known issue 复现
- [ ] 确认快捷指令 App 中能发现本 App 意图（沙盒 target 与 Direct target 各验一次）

## 1. Phase 1 · App Intents（双渠道）
- [ ] `HagimiMonitor/Intents/MonitorIntents.swift`：`GetCurrentMetricIntent` / `GetSystemSnapshotIntent`（只读，读 `MonitorStore` 最新帧）
- [ ] `ModuleEntity` / `MetricEntity` 动态查询（跟随设置里的启用模块与指标）
- [ ] 意图标题/描述/结果文案进 `Localizable.xcstrings`（中/英/日）
- [ ] 快捷指令实测：「CPU 占用超过 80% 时通知我」自动化可搭建并生效

## 2. Phase 2 · AI 诊断摘要（双渠道，依赖国行 AI）
- [ ] 可用性门控三级检测（编译期 / availability / 设置开关），不可用时入口整体隐藏
- [ ] `HagimiMonitor/Insights/SystemInsightGenerator.swift`：快照+进程+事件 → 提示构造 → 单轮生成 → 超时回退
- [ ] 设置页开关（默认关）+ 不可用原因说明文案
- [ ] 面板 AI 诊断卡片：内容区 + 「端侧 AI 生成 · 时间」页脚 + 生成中占位
- [ ] （event-timeline 落地后）异常事件自动解读开关

## 3. 验收
- [ ] 关闭 Apple Intelligence 的测试机上：App Store / Direct 两版均无 AI 入口、无崩溃
- [ ] 隐私自查：抓包确认生成过程零网络请求
- [ ] 三语本地化完整性检查
