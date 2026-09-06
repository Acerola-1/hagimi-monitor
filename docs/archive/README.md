# 历史技术文档与研究档案 (Docs Archive)

本目录归档了 HagimiMonitor 研发过程中的历史调研报告、技术原型方案、性能瓶颈分析以及早期的动画探索过程。
这些文档作为项目技术演进的客观背景资料保留，但**不代表当前生产代码的设计现状**；当前生效的架构与开发规范请以项目根目录 [`AGENTS.md`](../../AGENTS.md) 及 `openspec/` 目录中的活跃规范为准。

---

## 目录索引

### 1. animation-research/ — 面板展开动画专项探索与历史档案
记录了项目在探索菜单栏面板展开/收起“果冻弹簧与窗口平滑贴合”过程中经历的早期技术瓶颈、多次方案尝试与性能度量分析。本轮单宿主统一运动与几何重构（`refactor-panel-expansion-single-host`）已彻底解决该问题。

| 文档 | 产生时间 | 说明与结论 |
|---|---|---|
| [`关于面板动画的现状.md`](./animation-research/关于面板动画的现状.md) | 2026-08 | 历史问题简报：定义了低刷新率、高负载下动画掉帧的本质原因（旧双宿主递归布局与窗口双补间冲突），提出了新架构的硬性验收指标。 |
| [`面板动画尝试档案.md`](./animation-research/面板动画尝试档案.md) | 2026-08 | 四轮历史尝试记录：详述了 2026-08 期间尝试通过 Timer 轮询驱动、CA 动画补间、局部 spring 调度等修补式方案的失败原因与教训。 |
| [`面板展开动画性能分析-2026-08-21.md`](./animation-research/面板展开动画性能分析-2026-08-21.md) | 2026-08-21 | 性能基准测试与堆栈分析：通过 `AutotestPerfMeter` 和系统 `sample` 采样主线程，定位出昂贵叶子视图在窗口尺寸变化时被逐帧递归协商的瓶颈。 |
| [`面板展开动画重构CodeReview报告.md`](./animation-research/面板展开动画重构CodeReview报告.md) | 2026-08 | 早期方案二（预测高度 + 窗口双补间）的代码评审报告，记录了当时在截断、多屏与多卡片连续展开时的边界问题。 |

---

## 2. hardware-research/ — 硬件监控与模块功能调研报告
记录了各个硬件监控模块（电源流向、SMC 风扇、蓝牙外设、历史统计）在技术选型与沙盒边界探测阶段的调研成果。相关结论已在生产采样器（`HagimiMonitor/Samplers/`）与双渠道分发架构中固化。

| 文档 | 涉及模块 | 说明与现状 |
|---|---|---|
| [`macOS26原生菜单栏监控应用SwiftUI实现参考.md`](./hardware-research/macOS26原生菜单栏监控应用SwiftUI实现参考.md) | 架构原型 | 项目早期的 SwiftUI 原型方案（当时基于原生 `MenuBarExtra`），后被自研常驻 `NSPanel` + `FluidPanelController` 架构取代。 |
| [`电源模块数据挖掘报告.md`](./hardware-research/电源模块数据挖掘报告.md) | 电源/电池 | 梳理了 IORegistry `AppleSmartBattery` 与 IOPMPowerSource 的核心只读键值，确立了放电/充电电流与功率计算口径。 |
| [`电源流向图改造与功能扩展需求分析报告.md`](./hardware-research/电源流向图改造与功能扩展需求分析报告.md) | 电源/电池 | `PowerFlowDiagram` 矢量流向图的设计需求与三种供电拓扑（适配器供电、电池放电、双向旁路）的状态定义。 |
| [`风扇监控功能部署说明与用户操作手册.md`](./hardware-research/风扇监控功能部署说明与用户操作手册.md) | 风扇 | 风扇模块的用户指南与说明，明确了只读监控与多风扇布局的展示规范。 |
| [`风扇监控功能项目评估报告.md`](./hardware-research/风扇监控功能项目评估报告.md) | 风扇 | 实测确立了核心技术红线：Apple Silicon 上用户态写 SMC 被系统 `thermalmonitord` 拦截（`kIOReturnNotPermitted`），风扇调速不可行，转为纯只读监控。 |
| [`双版本蓝牙设备监测实现总结.md`](./hardware-research/双版本蓝牙设备监测实现总结.md) | 蓝牙 | 总结了沙盒渠道与 Direct 渠道对蓝牙外设电量（IOBluetooth / 辅助接口）的采集方案与降级处理。 |
| [`数据统计功能需求分析与设计报告.md`](./hardware-research/数据统计功能需求分析与设计报告.md) | 历史统计 | SQLite 本地轻量数据库的分层存储设计（分钟级/小时级/日级积分），现已实现在 `HagimiMonitor/Statistics/`。 |

---

## 3. notes/ — 系统与环境参考笔记

| 文档 | 说明 |
|---|---|
| [`Xcode 27.txt`](./notes/Xcode%2027.txt) | Xcode 27 Beta Release Notes 原始发行日志备忘。 |
| [`macos27.txt`](./notes/macos27.txt) | macOS 27 Beta 系统变化与 API 变更备忘。 |
