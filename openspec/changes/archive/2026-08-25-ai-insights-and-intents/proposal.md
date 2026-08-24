# Proposal: AI Insights & App Intents（A4 + A8）

> 状态：**暂缓（Hold）**——A8 依赖 Apple Intelligence 在中国大陆落地，用户决定上线后立即执行。
> 注意：A4（App Intents）本身**不依赖** Apple Intelligence，如需提前落地可拆出单独 change；本计划保持两者一体以便 A8 上线时连贯实施。

## Why

- **A4 · App Intents**：把监控指标暴露给快捷指令 / Spotlight / Siri。macOS 27 的快捷指令支持自然语言创建自动化，"CPU 超过 80% 时通知我"这类需求可由用户自助组合，是零成本的生态扩展点。
- **A8 · AI 诊断摘要**：用 macOS 26+ 的 Foundation Models（端侧模型）结合 top 进程、事件时间线、实时指标，生成一句话诊断（"CPU 高是因为 Xcode 正在编译"）。这是竞品 Stats/iStat 都没有的差异化能力，且数据完全不出设备。
- 立项背景（2026-08 需求评审）：用户认可两项提议，但国行 Mac 的 Apple Intelligence 未上线，A8 无法测试；决定作为 openspec 计划留档，国行 AI 上线后立即开展。

## What Changes

### Phase 1 — App Intents 指标暴露（双渠道，无 AI 依赖）
- 新增 `AppIntents` 集成：只读查询意图（获取指定模块当前值 / 全模块快照），模块与指标作为 App Entities 可被引用；
- 出现在快捷指令 App 与 Spotlight 建议中；不注册任何写入/控制类意图；
- 意图在主进程内执行，直接读现有 `MonitorStore` 最新采样，无需新增权限。

### Phase 2 — AI 诊断摘要（双渠道，依赖 Apple Intelligence 可用性）
- 运行时检测 `SystemLanguageModel` 可用性（设备支持 + 用户已启用 + 地区可用），不可用时功能整体隐藏，不出现死开关；
- 面板新增可选「AI 诊断」卡片（设置开关，默认关）：把最近 N 分钟指标快照 + top 进程 + 事件时间线条目序列化为提示上下文，请求端侧模型生成 1~2 句诊断；
- 摘要按需生成（点击刷新 / 事件触发），带生成时间与"端侧生成"标识；失败/超时静默回退为纯数据展示。

## Non-goals
- 不接入任何云端模型 / 不上传任何指标数据（Foundation Models 本身即端侧）；
- 不做自然语言**控制**（改设置、切模式）——只读与解释；
- 不做多轮对话、不做独立 Siri 集成界面；
- Phase 2 不承诺中国大陆可用性——以运行时 availability 为准。

## 渠道
App Store 与 Direct 双渠道同一实现：App Intents 沙盒安全；Foundation Models 为公开框架，与沙盒无关，差异仅在设备/地区可用性。
