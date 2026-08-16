# Design: AI Insights & App Intents

> 暂缓计划的技术预案。落地时先按 §0 验证一次 macOS 当前版本的框架状态（本计划写于 macOS 27 beta 期，Foundation Models 存在多条 known issue）。

## D1. App Intents（Phase 1）

- **意图集**（只读）：
  - `GetCurrentMetricIntent(module: ModuleEntity, metric: MetricEntity)` → 返回数值 + 单位 + 采样时间；
  - `GetSystemSnapshotIntent` → 返回全部模块摘要（供快捷指令做条件判断，如"CPU > 80%"）；
- **Entities**：`ModuleEntity`（cpu/gpu/memory/storage/network/battery/fan，动态查询当前启用模块）+ `MetricEntity`（每模块的可查询指标，来自设置里的指标定义）；
- **执行位置**：主进程前台执行（`openAppWhenRun = false`），直接读 `MonitorStore` 最新一帧，避免意图触发额外采样负载；
- **本地化**：意图标题/描述进 `Localizable.xcstrings`，中/英/日三语；
- **不含写入意图**：控制类动作（如风扇转速）永不注册为公开 intent，避免沙盒审核与安全争议。

## D2. Foundation Models（Phase 2）

- **可用性门控**（三级，任一不满足即隐藏整个功能入口）：
  1. 编译期 `#available(macOS 26, *)`；
  2. 运行时 `SystemLanguageModel.default.availability`（区分不可用原因：设备不支持 / 未启用 / 地区限制，用于设置页说明文案）；
  3. 用户设置开关（默认关，明示"端侧模型，数据不离开本机"）。
- **会话策略**：`LanguageModelSession` 按需创建、单轮问答、用完即弃；不维护多轮历史。
- **提示构造**：把最近 5 分钟指标快照（各模块值 + 趋势方向）、top 3 进程（名称/CPU/能耗估算）、近期事件（event-timeline 落地后）拼成紧凑 JSON 文本作为上下文；instructions 固定为"用 1~2 句中文解释当前系统状态的主因，只依据给定数据，不猜测"。
- **规避 27 beta 已知问题**：
  - 不用 tool calling / @Generable 复杂结构（release notes 报告 tool calling 过度调用、enum @Generable 弃用警告等问题）——只要求纯文本输出；
  - 不用 `onPrompt`（存在不被调用的已知问题）；
  - 生成加超时（建议 20s）与静默回退。
- **触发方式**：AI 诊断卡片手动刷新；event-timeline 落地后可选"异常事件自动生成一条解读"（仍受开关控制）。
- **UI**：卡片样式对齐面板现有 row 体系；内容区小字 + "端侧 AI 生成 · 时间" 页脚；生成中显示占位 shimmer。

## D3. 隐私与审核

- 全链路端侧；无任何网络 entitlement 依赖；
- App Store 审核口径：Foundation Models 为公开框架，沙盒可用；提交说明中注明无数据上传；
- 隐私标签（App Privacy）不因本功能变化。

## D4. 风险

| 风险 | 应对 |
|---|---|
| 国行 AI 上线时间未知 | Phase 1 可独立先行；整体 Hold |
| Foundation Models 首次使用需下载模型 | 首次点击时提示"系统正在准备模型"，轮询 availability |
| 模型输出不稳定/幻觉 | 提示词强约束 + "仅供参考"标识 + 只呈现不告警 |
| 框架在 27 正式版的行为变化 | 落地前重跑 §0 验证任务 |
