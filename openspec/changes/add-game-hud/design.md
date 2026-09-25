# Design

## Context

见 proposal.md - Why。本设计只描述「怎么做」，动机与范围以 proposal 为准。

以下事实来自本轮实测与代码核对，是本设计的前提。**实现者应以这些为准，不要凭推测修改**：

| 事实 | 来源 |
|---|---|
| 独立进程的 borderless `NSPanel` 可覆盖另一进程的原生全屏 | 原生探针实测，`tmp/game-hud-probe/verification.json` |
| 真正开启 App Sandbox 后，该浮窗仍可跨进程覆盖全屏 | `tmp/game-hud-probe/sandbox-validation/verification.json` |
| 沙盒下实测可读：CPU/GPU 占用、内存、压缩内存、Swap、驱动聚合 GPU 内存、系统功耗、电池百分比、热压力 | 同上，`system_metrics` |
| 沙盒下 `AppleSMC` `IOServiceOpen` 返回 `kIOReturnNotPermitted (0xe00002e2)`，CPU 温度不可读 | 同上，`capability_limits.cpu_temperature` |
| 沙盒下无可用数据源实现 CPU/GPU 分项功耗 | 同上，`capability_limits.cpu_gpu_component_power` |
| 统一日志中的 Metal HUD 逐帧明细被隐藏为 `<private>` | 同上，`limitations`；本轮已复现确认 |
| 通过 `NSWorkspace` 传递的启动参数与环境字典被忽略 | 同上，`sandbox_launch_filter.observed`；本轮已复现确认 |
| 项目内已有跨进程浮窗、点击穿透与全屏辅助的先例代码 | `prototypes/game-hud-probe/` |

**Phase 1 门槛已跑完，结论见 `tmp/game-hud-probe/gate-conclusions/conclusions.json`：**

| 门槛 | 结论 |
|---|---|
| 窗口档位 | `.floating` 已足够压住原生全屏，无需 `.statusBar` |
| 物理点击穿透 | 成立：浮窗正中心点击穿透到下层游戏，且未夺焦 |
| 帧率通路 | 受控进程 stderr 完整可用（60FPS 目标实测算出 59.92 FPS）；**对已运行游戏不可用** |
| 官方 HUD 按游戏启用 | `NSWorkspace` 传环境变量被丢弃；实现须走「受控启动」或「仅手动提示」 |

结论：**浮窗能力与数据采集范围已实测确认；帧率只能覆盖由我们启动的游戏，这属于产品范围问题，需用户拍板。**

## Goals / Non-Goals

**Goals:**

- 用一次性探针把两个未知项（帧率采集通路、官方 HUD 启用通路）验证到可下结论，再决定产品接入范围。
- 复用既有采样通道与既有指标 ID，不新建采样器、不改动面板既有布局规则。
- 两渠道能力差异以**运行时可读性**为准落地，而不是以编译条件一刀切。

**Non-Goals:**

- 不实现游戏进程注入、私有图形接口 Hook、SIP 关闭。
- 不承诺兼容任意游戏；不覆盖转译/虚拟化宿主内部的具体游戏。
- 不实现每游戏独立配置。
- 不在本 change 内改动主面板材质或引入 Liquid Glass 实验。

## Decisions

### 决策 1：能力门槛已通过，帧率范围受限

Phase 1 已执行完毕（见 `tmp/game-hud-probe/gate-conclusions/conclusions.json`）。已确认：

1. **窗口档位**：`.floating` 足够，需保留 `ignoresMouseEvents = true` 与 `collectionBehavior` 含 `.canJoinAllApplications`、`.fullScreenAuxiliary`。
2. **点击穿透**：成立，浮窗不夺焦。
3. **帧率通路**：受控进程的 stderr 完整可用；统一日志明细被 `<private>` 隐去；**对已在运行的游戏无法取得**。因此帧率曲线只覆盖「由我们启动的游戏」。
4. **官方 HUD 启用**：`NSWorkspace` 传递环境变量被系统丢弃，须走受控启动或仅手动提示。

**帧率范围是待用户拍板的产品决策**（见 Open Questions 第 1 条），不是技术未知项。在此之前：Phase 2/3 可正常推进；Phase 6.3 的帧率曲线按「受控启动」设计，若无此交互则只做 CPU/GPU 占用曲线。

### 决策 2：数据适配层读 `MonitorStore.modules`，不新建采样

**选择**：新建 `GameHUDMetricsAdapter`，从既有 `MonitorStore` 的发布数据读取指标，按勾选与渠道可用性过滤后输出给悬浮层。

- `MonitorStore` 的公开形态是 `@Published private(set) var modules: [MonitorModule]`，**数组**，按 `kind` 查找；不存在 `[MonitorKind: [MonitorMetric]]` 字典。
- `MonitorModule.metrics: [MonitorMetric]`，其中 `MonitorMetric` 为 `{name, value, numericValue?, unit?}`。

**理由**：AGENTS.md 要求复用既有采样与发布通道，且不得额外增加每秒硬件查询。

**替代方案**：为 HUD 单独采样。已否决——会重复硬件轮询，且与面板数据不同口径。

### 决策 3：渠道差异按「运行时可读性」过滤，不按编译条件过滤

**选择**：指标目录的渠道过滤以实际取值是否成功为准，`#if` 仅用于决定是否**呈现**官网专属能力，不作为目录能否出现的唯一判据。

**理由（关键，易错）**：实测发现 `DISPLAY_CONTROL` 在**两个 target 上都定义**（App Store target 亦有），只有 `DIRECT_DISTRIBUTION` 是官网独有。SMC 读取代码在两个渠道都被编译；沙盒版读不到 CPU 温度是**运行时沙盒拒绝**，不是代码不存在。

**替代方案**：用 `#if DIRECT_DISTRIBUTION` 决定目录。已否决——会把「渠道差异」与「编译差异」混为一谈，正是上一版计划的错误来源。

### 决策 4：申请用户名单存储，不持久化空名单

**选择**：应用名单与排除名单只存用户显式添加/排除的 bundle ID；自动识别候选由内置名单提供，不把「识别结果」写入用户设置。

**理由**：避免把运行时判定固化成用户配置；也避免有版本升级时内置名单变化被旧快照覆盖。

### 决策 5：悬浮层保持固定尺寸契约，不随勾选数量变化

**选择**：悬浮层尺寸由布局契约决定（行数上限/滚动），勾选数量变化不改变窗口高度。

**理由**：spec 要求布局不抖动；实测中已勾选项目暂时无读数时保留行显示 `—`，同样是为了避免高度跳变。

### 决策 6：GPU 内存项的展示语义限制为「驱动聚合」

**选择**：`gpu-memory` 与 `allocated` 在 HUD 中的文案标注为驱动聚合内存。

**理由**：探针实测确认其数据源是 IOAccelerator 驱动聚合字节数，**不是**游戏专属显存、也不是显存容量。按「显存占用」呈现即违反「不伪造数值」。

## Risks / Trade-offs

- **[帧率只能覆盖受控启动的游戏]** → 实测已确认无法对已运行游戏取帧率。若用户不接受「由我们启动游戏」的交互，则本 change 只交付硬件 HUD，帧率曲线移出范围。**不得**用刷新率/录屏帧率替代。
- **[点击穿透未在真实游戏验收]** → 已在探针场景的原生全屏下验证成立；真实商业游戏仍需复验。
- **[官方 HUD 无法按游戏启用]** → 已实测确认 `NSWorkspace` 的环境与参数传递被丢弃；实现只保留手动说明或受控启动，不写全局偏好。Spec 已把「不写全局偏好」设为硬约束。
- **[沙盒指标可用性随系统版本变化]** → 现有结论来自 macOS 27.0 单一版本；`gpu-memory` 等驱动字段的长期稳定性未被验证。实现时应容忍字段缺失而不是崩溃。
- **[GPU 内存读数与用户预期不符]** → 用户可能把驱动聚合值理解为显存占用。以决策 6 的文案限制缓解。
- **[候选名单难以维护]** → 内置名单必然滞后于新游戏。以「用户手动添加」为主路径，名单为便利而非门槛。

## Open Questions

Phase 1 已关闭原先 5 条中的 4 条（结论见 `tmp/game-hud-probe/gate-conclusions/conclusions.json`）。剩余问题：

1. **帧率是否接受「由我们启动游戏」的交互？**（需用户拍板）
   实测确认帧率只能从受控进程的 stderr 取得，对已在运行的游戏无效。可选：不做帧率、只做硬件指标；或提供「由我们启动游戏」的入口。**这是产品范围决策，在用户答复前不得自行选择以实现来回避。**
2. 候选游戏内置名单的首批内容与维护方式？
3. 真实商业游戏（Steam 原生）下的浮窗与指标一致性——属 Phase 1.5，需实机复验。

已关闭：窗口档位（`.floating` 足够）、物理点击穿透（成立）、官方 HUD `NSWorkspace` 通路（不可用，改走受控启动或手动提示）。
