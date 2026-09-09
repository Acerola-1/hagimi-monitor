# harden-display-control-reliability 验收报告

日期：2026-09-09。对象：`tmp/wt-display-reliability` 工作树中未提交的实现，分支 `feature/display-control-reliability`。本报告是验收发现，不是新需求或执行完成记录。

## 结论

**不通过验收。不能将此状态描述为“54/57 完成，只剩用户侧目测与硬件”。**

实现提供了若干模型与独立测试，但生产 controller 仍使用旧 service/worker/packet transport。多数新能力没有进入真实交互路径，且新引擎存在可复现的生命周期及故障处理缺陷。design Migration Plan 的逐步替换是本 change 的实施步骤，不是将生产接线移到后续 change 的许可；本次验收不改变原有范围。

输入源、硬件静音、RGB/KVM 等本来不属于本轮，缺少这些不扣验收。本轮已承诺的兼容设置、绑定、诊断和可靠通信仍必须交付。

## 验证方法与限制

- 对照原 proposal/design/四份 specs：实施工作树中的这些文档与原计划内容一致。
- 检查生产调用及所有新增模型的使用点；工作树自身没有 `.codegraph/`，使用该工作树当前文件，不以主工作区索引冒充待审代码。
- 阅读提交者现有日志：final-test.log 有315条通过、0条失败并含 TEST SUCCEEDED；final-test2.log 有313条通过、0条失败并含 TEST SUCCEEDED。两个数字来自不同日志，不能混称为同次运行。
- 编译当前源文件的隔离副本，注入 fake transport 并使用实际调度时钟，复现引擎与门禁缺陷。不修改生产源码，不调用真实 DDC/Gamma 接口，不改变用户显示器。
- 本次未重新运行全量 Xcode 测试或双构建；现有测试成功不能证明生产路径覆盖。读取 xcresult 摘要时工具自身遇到 TestReport 写权限错误，因此日志证据不冒充独立重跑。
- 本次未启动候选版本或做真机画面/VoiceOver 验收；代码交付门槛已经失败，硬件效果继续标记未验证。不能把未实现的 UI 推给用户目测补齐。

## 关键发现

### R1 — P1：核心实现未接入生产路径

位置：`HagimiMonitorDirectOnly/DisplayControlController.swift:16`，`DisplayDDCBridge.swift:215`。

controller 仍创建旧 DisplayControlService/DisplayControlWorker。生产代码没有创建 DisplayControlEngine，也没有 DDCTransport 协议的真实 IOAVService 适配实现；新增身份匹配、持久化、媒体键选择器和诊断缓冲没有接入实际调用链。旧 packet transport 超时后继续入队的行为仍存在。

后果：用户拖动滑块时得不到新的有界调度、连接代次、终态确认、只写配置、v2 状态恢复。原音频输出检测与 MediaKeyController 未改，媒体键仍按旧目标策略执行。不能用新引擎 fake 测试证明生产已修复。

返工：在本 change 内完成 controller→调度器→真实适配器和系统事件的接线；废弃重复状态。增加从实际 controller 入口使用可替换适配器的集成测试，证明 UI 使用的路径触发新后端。

### R2 — P1：逐屏设置、绑定和诊断没有产品入口

位置：`HagimiMonitor/Views/Panel/DisplaySection.swift:1458`；新增配置/诊断类型的生产引用检查。

Swift UI 改动仅为原有滑块新增 optional 包装、来源标签和 accessibility。DisplayCompatibilityConfig 仅在持久化模型内使用，DisplayDiagnosticsLog 无生产实例，MediaKeyTargetSelector 无生产调用；没有兼容设置页、绑定页或复制诊断操作。HTML 原型不是应用接线。

返工：实现任务10.3/10.4及相关9.x生产配置流，配置实际改变当前控制后端、读策略与范围；诊断必须收集真实事件并可由用户复制。只定义枚举和存取函数不算交付选项。

### R3 — P1：replaceConnections 不移除已断开的连接

位置：`HagimiMonitorDirectOnly/DisplayControlEngine.swift:104–113`。

oldTokens.subtracting(newTokens) 只调用 clearTransientState，未从 connections 删除对应项。replaceConnections([]) 后旧 token 仍通过 enqueueWrite 的连接存在检查。

隔离复现：连接一台→replaceConnections([])→向旧 token 提交25%；快照仍有1条连接，fake后端收到1次旧屏写入（预期均为0）。

返工：替换集合时真正移除过期连接，清除会话数据；补充“旧 token 再次提交被拒绝”的断言，不能仅检查 states[token] == nil。

### R4 — P1：断开连接会提前释放仍在执行的事务

位置：`HagimiMonitorDirectOnly/DisplayControlEngine.swift:144–146`。

clearTransientState 把 inFlight 设为 nil，但物理调用仍未返回。未超时时移除连接后，另一屏可以再次向底层提交。若先超时再移除，channelStalled 留存而旧回调因 flight 缺失被忽略，还可能无法恢复。

隔离复现：阻塞屏A写入、不释放回调→移除A→写屏B；释放任何回调前，fake已收到2个写调用（全局单in-flight要求最多1）。

返工：全局物理事务占用与设备逻辑状态分开管理，设备失效只禁止结果发布，不提前释放执行占用；真实返回统一清理并恢复调度。测试覆盖超时前后两种断开时序。

### R5 — P1：读取与确认读取没有 deadline

位置：`HagimiMonitorDirectOnly/DisplayControlEngine.swift:349–372`、`performConfirmation`。

只有 attemptWrite 安排了 callDeadline；普通读取和确认读取设置 inFlight 后直接等回调。读调用不返回会一直占住调度器，却不发布 stalled 状态。

隔离复现：callDeadline=50ms，阻塞读取200ms，readCount=1且channelStalled=false（应为true）。

返工：让读、写、确认统一进入事务超时与真实返回流程。测试分别阻塞三个事务类型并检查有界缓冲、可见异常和迟到恢复。

### R6 — P1：失败退避并未重新发送目标

位置：`HagimiMonitorDirectOnly/DisplayControlEngine.swift:281`、`340–346`、`487–498`。

发送前移除 pendingWrite；失败时仅安排 timer，timer调用 drain，但失败目标已不在槽中，没有恢复工作可做。新请求也能经末尾 drain 立即发送，退避状态没有真正约束执行。

隔离复现：后端返回写失败；等待首次1秒退避期限后，writeCount仍为1（应至少有第一次恢复发送）。

返工：恢复对象保存该连接最新有效目标或必要恢复探测，保留后续新目标优先级；为backoff设置真正的调度条件，次数上限后进入可恢复异常。测试验证实际调用次数/时间，而不是仅存在常量或timer。

### R7 — P1：生产门禁仍漏发恢复，并可能提前通知

位置：`HagimiMonitorDirectOnly/DDCEnvironmentGate.swift:152–158`、`174–180`。

通知仍只在structural事件安排，setMode和begin-only没有恢复timer。唤醒与structural重叠时，较短的重配置timer还会取消唤醒timer；fireChangeHandlers不检查当前是否仍抑制。

隔离运行当前生产门禁（关闭系统观察者）：
- setMode完成后suppressed=false、回调0。
- begin-only安全期限后suppressed=false、回调仍0。
- 唤醒500ms+重配置10ms：唯一回调执行时isSuppressed=true，最终解除后没有新回调。

返工：按所有原因的有效截止时间统一安排恢复；回调前重验状态，未到期重新安排，true→false后再核验连接并重放。纯GateStateModel测试不能替代真实观察者适配层测试。

### R8 — P1：Gamma恢复与失败结果不满足合同

位置：`GammaDimmingController.swift:126–148`、`165–175`、`208–230`；`DisplayControlController.swift:480–484`。

- controller 忽略 setDimming 的新返回值，仍保存设置并返回 written；失败在产品层仍是假成功。
- setDimming(percent:100)仍调用线性identity公式，不恢复缓存的非identity基线；调光也没有以基线缩放。
- resetAll直接清除baselines再逐屏调用identity恢复；正常退出不恢复原始校色。
- reset在确认恢复成功前删除状态，失败后丢失重试依据。
- restoreBaseline绕过GammaAPI直接调用系统函数，使所谓fake测试会进入真实Gamma API。
- service.displays仍在每次刷新末尾reapplyAll，与事件驱动要求相反。

返工：所有Gamma操作走同一注入接口，正确应用/恢复基线，100%、退出、切后端路径统一；失败不发布成功、不丢失待恢复状态、不覆盖成功持久化。补非identity基线、恢复失败和普通轮询零Gamma调用测试。

### R9 — P2：未知值包装永远非空，还将默认数值标为上次设置

位置：`HagimiMonitor/Views/Panel/DisplaySection.swift:1458–1463`；`DisplayControlController.swift:445–456`。

Optional(controller.value(...))始终非nil，controller仍以50/40/75兜底。新`--`分支在生产不可达；首次无读数/无历史时还可能显示“上次设置40%”，但用户从未设置。

另一个待接线问题：nil分支画的是不可交互矩形；直接接上新值模型后，只写设备没有初始值时将无法首次通过滑块设值。

返工：真实optional状态贯穿controller→view，提供未知状态下的明确绝对值输入能力，区分无记录与历史值。验证首次只写设备可以设值，且之前不显示伪造百分比。

### R10 — P1：亮度软件模式仍禁用音量和对比度

位置：`HagimiMonitorDirectOnly/DisplayControlController.swift:436–438`、`480–481`。

生产model继续按useGammaDimming将volume/contrast置false，写路径也将整台屏导向仅亮度Gamma分支。BackendSelection的独立测试没有改变该行为。

返工：每属性选择并执行后端，使用生产controller测试“软件亮度+DDC音量+DDC对比度”三项真实适配调用，不只测试枚举返回值。

### R11 — P2：新媒体键选择器仍会猜测未关联的输出

位置：`HagimiMonitorDirectOnly/MediaKeyTargetSelector.swift:40–43`。

没有绑定时只要一台屏支持音量就返回该屏，并未证明当前不可控音频设备对应它。音频可能是另一个不可控输出，不能把“唯一可控屏”当作“音频映射唯一”。且当前该选择器尚未接入生产。

返工：使用有效系统映射证据或显式绑定；未知输出交还系统。补充“不可控外部音频设备+一台无关显示器”场景。

### R12 — P2：测试断言与勾选的验收语义不一致

位置：`HagimiMonitorTests/DisplayControlIntegrationTests.swift`、`GammaDimmingControllerTests.swift:101–104`、execution-notes中的场景映射。

- 生命周期测试只检查旧states被清理，不断言旧connections被移除，也不实际提交旧token，漏掉R3。
- 所谓基线恢复测试只检查取过基线和isDimming=false，不检查恢复参数/结果，漏掉R8，且调用了非fake系统API。
- “只写零读”映射到配置值存储测试；“普通轮询不施加Gamma”测试只直接调用reapplyAll，未走生产refresh。
- “资源有界”只断言固定50次操作产生的写入不超过100，没检查真实执行占用或缓冲上限。

返工：以spec场景的可观察结果为断言，从实际controller/observer入口验证到fake硬件边界；任何真实系统API泄漏到fake测试必须修正。不要通过放宽断言消除回归失败。

## 已有可保留成果

删除旧永久去重是有效改进；UInt16范围转换、部分协议解析和模型、门禁独立原因状态、部分滑块辅助功能与软件模式标识可作为后续基础。可复用不等于里程碑已验收。

## 里程碑判断与任务修正

| 里程碑 | 本次验收 |
|---|---|
| M1 基础模型 | 部分完成；生产身份/值接线未完成，模型仍有缺陷 |
| M2 可靠通信 | 不通过；生产旧路径、in-flight/读取deadline/重放问题 |
| M3 能力与恢复 | 部分模型完成；生产混合后端、迁移、Gamma恢复未完成 |
| M4 产品接线 | 不通过；配置/绑定/诊断入口缺失，媒体键未接入 |
| M5 集成验收 | 不通过；测试未覆盖生产合同，真机尚未验收 |

tasks.md 至少需重新核对并重开以下已勾选项：2.2/2.3、3.1/3.3、4.1–4.5、5.2/5.3、6.5/6.6、7.1–7.4、8.2–8.5、9.1–9.4、10.2–10.4、11.1/11.2/11.3、12.7。其他勾选不因本清单未列出而自动通过，应按各自验收逐项补证据。

本次不擅自改实施者的tasks勾选；执行者应依据报告修正，不继续引用54/57作为已验收完成比例。

## 建议返工顺序

1. 先将R3–R7及R8的fake边界补为会失败的真实回归测试，修复新引擎和门禁本身。
2. 在原change内完成真实传输适配及controller接线，删除旧重复编排；身份/兼容/持久化同步贯穿，不能只替换一个调用点。
3. 完成混合后端、媒体键、未知值/设置/绑定/诊断入口。
4. 从生产入口复测全部spec场景，再运行双构建和完整测试。
5. 完成可获得硬件矩阵，记录not-run与限制，再提交下一轮验收。

## 隔离复现文件

审查临时文件位于仓库根目录的 `tmp/review-display-control/`，不纳入发布或提交：ReviewMain.swift（引擎）、GateMain.swift（生产门禁），其余为待审源文件的原样副本与实施者fake transport。

从仓库根运行已编译结果：

```sh
./tmp/review-display-control/review
./tmp/review-display-control/gate-review
```

本次输出：

```text
REMOVAL: after replaceConnections([]), connections=1, old-token writes=1 [expected 0,0]
INFLIGHT: blocked calls submitted before releasing any = 2 [expected 1]
READ TIMEOUT: reads=1, stalled=false [expected stalled true]
RETRY: writes after first retry deadline = 1 [expected at least 2]
MODE CHANGE: suppressed=false, callbacks=0 [expected callbacks 1]
BEGIN ONLY: suppressed=false, callbacks=0 [expected callbacks 2]
OVERLAP: suppression seen by callbacks=[true], final suppressed=false [expected recovery callback only after suppression false]
```

临时副本反映本次审查时的源码；实施修复后正式测试应直接使用修复后的生产类型，不能运行旧临时二进制当成最新验收。

## 修复后复核（2026-09-09）

上述 R1–R12 是修复前结论。随后在同一工作树完成了以下修正：

- R3–R6：连接集合真正移除旧 token；断开不释放物理 in-flight；读/确认读纳入 deadline；失败写入保留最新目标并按退避重试。
- R7：生产 `DDCEnvironmentGate` 改用 `DDCGateRuntime`，begin-only、非结构重配置和唤醒重叠均由统一截止时间驱动恢复回调。
- R8/R10：Gamma 以基线缩放和恢复，失败不报告成功；每属性独立选择后端，亮度 Gamma 不再关闭音量/对比度；普通刷新不再重施加 Gamma，恢复事件才重放。
- R1/R11：Direct controller 的外接 DDC 写入经过 `DisplayControlEngine` 和真实 `DisplayDDCTransport`；媒体键音量目标经过 `MediaKeyTargetSelector`，多候选时交还系统。
- R9：控制器和 SwiftUI 使用真实 optional 值；未知值显示 `--` 但滑杆仍可首次设值，不再把默认值当作历史设置。
- 持久化：兼容配置的范围覆盖和 VCP 覆盖可往返读写，v2 数据存在性不再只看软件因子。
- OSD 提示：当前系统的 `OSD.framework` 不包含可加载的二进制，原生 OSD 调用始终不可用；已删除无效开关、私有 API 包装和相关持久化逻辑，不影响 DDC 或媒体键调节。

新增回归覆盖旧 token 拒写、阻塞读 stalled/迟到恢复和失败写退避重试。验证结果：Direct scheme 全量测试通过（包含新增用例），Direct Debug build 通过，App Store Debug build 通过，`openspec validate --strict` 通过。本次自动化会话的命令行环境未能访问用户桌面的 WindowServer/外接显示器 DDC 会话，因此硬件矩阵、目测和真机 DDC 尚未执行；这不表示用户现场没有外接显示器，fake 测试也不能替代实机验证。

仍需后续产品接线：兼容设置/连接绑定尚未有面向用户的设置页，诊断已在 controller 内形成环形缓冲和导出方法但尚未放入复制按钮；发现阶段仍保留旧 worker 作为拓扑探测，不能把本次接线描述成旧路径已完全删除；音频 UID 到显示器的真实 CoreAudio 映射仍需在用户的 Dell S2725QC（以及其他连接方式）上确认。因而代码级回归已通过，产品验收仍需完成 12.4–12.6 及上述 UI 接线。

## 最终清理复核（2026-09-09）

- 删除未使用的门禁 debounce work item、引擎请求归属字段、恢复事件类型和重复身份辅助；移除已删除 OSD 私有 API 后残留的 `OSD` 链接参数。
- 生产引擎初始化补上 `DDCEnvironmentGate` provider 与恢复回调；诊断导出的显示器数量改为真实插值。
- 清理本轮新增代码中的过程性/历史性注释，使注释只描述当前状态与设计原因。
- Direct 全量测试、App Store/Direct Debug 构建、`openspec validate --strict` 与 `git diff --check` 均通过。构建仍有 Swift 6 并发告警，相关任务 4.6 已重开；未用 `@unchecked Sendable` 隐藏告警。
- 兼容配置生产应用、连接绑定设置页、诊断复制入口和硬件矩阵仍保持未完成，tasks.md 已按实际接线状态标记。
