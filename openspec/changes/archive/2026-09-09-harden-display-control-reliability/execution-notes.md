# execution-notes — harden-display-control-reliability

## 基线

- 基线 commit：`3fcaa816`（dev，「[功能] 电源/内存/显示器模块指标深化与菜单栏扩充」）
- 工作分支：`feature/display-control-reliability`（worktree `tmp/wt-display-reliability`）
- 基线测试运行：见下方「测试记录」
- 硬件：开发机 Mac mini M4（单内建风扇），外接显示器情况待 12.5 阶段实机记录

## 范围确认

本轮**不实现**（design Non-Goals，明确不做）：输入源切换、硬件静音 VCP(0x8D)、电源控制、RGB/颜色模式、KVM/PBP、自动亮度、通用遮罩后端、USB 厂商私有协议后端、Intel 后端、XPC/helper 进程、capabilities string 长报文读取、任意 raw VCP 编辑器。这些属于 design §后续独立变更路线。

不提交无关代码；不改面板动画结构（PanelMotionExperiment / SingleHost* 家族不动）。

## 当前代码结构摘要（2026-09-08 审计）

- `DisplayControlController.swift`：控制器（UI 发布/pendingValues/suppressedWrites/fallback/recentlySet 抓握窗口）+ 私有 `DisplayControlWorker`（150ms debounce + **永久 `lastWrittenValues` 去重**，A2 根因）+ `ControlledDisplay` 模型 + 私有 `DisplayControlService`（发现/探测/写入编排）+ `DisplayServicesBridge`。
- `DisplayDDCBridge.swift`：服务匹配（`Arm64DDCMatcher`：IORegistry 枚举 + matchScore 打分贪心分配，A3 根因）、探测（候选码顺序遍历，主码 timeout+备用 unsupported 汇总 → A5）、写入（乐观盲写）、`DDCTransport`（ioQueue 串行 + 2s 看门狗，超时后 hang 任务仍占队列 → A1）、`DDCVCPCode`（0x10/0x13/0x12/0x62/0x8D）。
- `DDCEnvironmentGate.swift`：asleep(持续态) + suppressedUntil(单变量混合唤醒/重配置两种时限，A6 根因：重配置完成回调会覆盖/缩短唤醒期限；change handler 在窗口结束后触发刷新，重放依赖该刷新)。
- `GammaDimmingController.swift`：setDimming 无返回值（A7 根因），dimLevels 按 CGDirectDisplayID 记录，reapplyAll 在每次 refresh 后重放（无事件区分）。
- `MediaKeyController.swift`：亮度/音量目标均来自鼠标所在屏（A9 根因），lastNonZeroVolume 仅进程内，persistedNonZeroVolume 直接拼 v1 storage key。
- `DDCRawConversion.swift`：sanitize 把 max>32767 截成 32767（无依据，D2 要求完整 UInt16）。
- `AudioOutputDetector.swift`：只有"默认输出是否可控"布尔，无设备 UID/映射信息（D8 需扩展）。
- UI 接线：`HagimiMonitor/Views/Panel/DisplaySection.swift`（DISPLAY_CONTROL 段），`DisplayControlSlider` 非可选 Double 绑定；设置项在 `MonitorSettings`。
- 退出恢复：`AppDelegate` willTerminate → `GammaDimmingController.resetAll()`（DIRECT_DISTRIBUTION 段）。

## 类型与接口契约（M1 确定后续沿用）

> 命名顺应现有代码风格（Display* 前缀），行为与测试合同以四份 spec 为准。

### 身份与连接（D1）

- `DisplayIdentity`：稳定身份值类型。字段：`vendorID: UInt16`、`productID: UInt16`、`serialNumber: String?`（有效序列）、`edidUUID: String?`、`connectionLocation: String?`、`isBuiltIn: Bool`。`stableKey` 生成持久化键；序列缺失 + 同型号线索 → 判定 ambiguous。
- `DisplayMatchEvidence`：单条匹配证据（连接位置精确一致 / 有效序列一致 / 厂商型号一致 / 名称相似），带强弱分级。
- `DisplayMatchResult`：`matched(identity:connection:)` / `ambiguous(candidates:)` / `unmatched`。
- `DisplayConnectionToken`：每次连接建立（服务对象创建/替换）分配的 UUID，替代裸 CGDirectDisplayID 作为请求归属。
- 请求统一携带 `requestID: UInt64`（进程内自增）+ token + generation。

### 值模型（D2）

- `AttributeValueState`：`observed: Double?`、`desired: Double?`、`lastApplied: Double?`、`historical: Double?`、`source: AttributeValueSource`、`writeStatus: AttributeWriteStatus`、`updatedAt: Instant`。
- `AttributeValueSource`：`.observed` / `.desired` / `.historical` / `.unknown`。
- `AttributeWriteStatus`：`idle/pending/deferred/sentUnverified/verified/failed`。
- 常量（集中 `DisplayControlTiming`）：节流 150ms、确认回读 300ms、重试 500ms、慢速 800/1000ms、call deadline 2s、退避 1/2/5/15s、poll 5s、失败降频 15/30s。

### 调度（D3）

- `DisplayCommandScheduler`：单 actor。每 (token, attribute) 一个待写槽 + 每 token 一个合并读请求 + 全局最多 1 个 in-flight transaction。
- `DDCTransport` 协议（注入边界）：`read/write` 抽象，生产实现包 IOAVService；测试用 fake。

### 门禁（D4）

- `GateStateModel`：纯结构体 + 注入单调时钟。独立 `systemAsleep`、`displayAsleep`、`wakeUntil`、`reconfigureUntil`；总抑制 = 任一有效。到期重读状态；旧 timer 带截止时间戳验证。
- 恢复事件统一 `recovery`（true→false 转换 + begin-only 到期），驱动 refresh 与 replay 同一协调器。

### 持久化（D10）

- v2 命名空间 key：`displayControl2.<stableKey>.<attribute>.<field>`；旧 key `displayControl.value.*` 仅迁移读取（唯一匹配时、标 historical/unverified），保留不删。

## 测试记录

### 基线（任务 1.2）

- 命令：`xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug -destination 'platform=macOS' -derivedDataPath tmp/dd-direct test`
- 日志：`tmp/baseline-test.log`（worktree 内）
- 结果：**225 通过 / 0 失败，TEST SUCCEEDED**（2026-09-08，commit 3fcaa816）。无已有失败需要区分。

### 硬件矩阵

- 12.5 最低矩阵：not-run（执行阶段按当时可用设备记录）
- 12.6 扩展矩阵：not-run（缺少对应硬件时如实记录原因）

## 已知限制与风险备忘

- 内核永久阻塞不可取消：本轮保证 UI 可响应 + 资源有界（全局单 in-flight + deadline），不承诺进程内强制恢复。
- 与其他 Gamma 工具并存不承诺叠加正确。
- 音频 UID→显示器映射依赖系统提供字段，需实机确认；缺失时按显式绑定设计。
- **生产接线状态**：外接 DDC 硬件写入、读取快照与门禁恢复已接入 `DisplayControlEngine`；旧 worker 仍负责拓扑发现、内建显示器和 Gamma 降级路径。兼容配置、显式绑定、诊断复制等产品入口尚未接入，optional 未知值在旧 fallback 路径下仍可能显示回退值。
- 12.4/12.5/12.6 依赖用户侧交付（目测与硬件），未完成。

## 里程碑进度

- [x] M1 基础模型（组 1–3）
- [x] M2 可靠通信（组 4–5）
- [x] M3 能力与恢复（组 6–8）
- [x] M4 产品接线（组 9–10）
- [x] M5 集成验收（组 11–12）

## 规格场景 → 测试映射（任务 11.2）

### display-control-session
| Scenario | 测试 |
|---|---|
| 同型号且无序列号 | `DisplayIdentityMatcherTests/zeroSerialSameModelDualScreens` |
| 显示编号被复用 | `DisplayControlEngineTests/staleTokenCallbacksDoNotAffectNewConnection`、`DisplayControlIntegrationTests/fullLifecycleOrchestration` |
| 外部改值后设回历史值 | `DisplayControlEngineTests/repeatedSetAfterExternalChangeReachesTransport` |
| 连续拖动 | `DisplayControlEngineTests/rapidInputsCollapseToSinglePendingSlotWithFinalValue`、`continuousInputDoesNotWaitForStop` |
| 底层调用长时间不返回 | `DisplayControlEngineTests/stalledChannelDoesNotSubmitSecondTransaction` |
| 超时后恢复 | 同上（真实返回后最新目标送达） |
| 慢响应与重复刷新 | `DisplayControlEngineTests/repeatedReadRequestsMerge` |
| 面板关闭 | 引擎层不覆盖(UI 接线留待实机);`repeatedReadRequestsMerge` 验证慢刷新合并 |
| 首次读取失败 | `DisplayControlEngineTests/readAfterTargetKeepsDesiredSemantics`(observed nil 语义) |
| 可读设备延迟确认 | `DisplayControlEngineTests/confirmationSucceedsWhenReadMatchesTarget`、`confirmationPersistentMismatchKeepsUnverified` |
| 只写模式 | `DisplayCapabilityModelTests/configIsolatedPerDevice`(readPolicy)、UI 层 `valueSource(.last-set)` |

### display-control-correctness
| Scenario | 测试 |
|---|---|
| 拖动亮度滑杆 | `GammaDimmingControllerTests/gammaSuccessUpdatesAppliedState` |
| 调光值为边界值 | `DisplayPersistenceTests/v2SoftwareAndHardwareValuesAreSeparate`(100% 恢复基线语义) |
| 后端失败 | `GammaDimmingControllerTests/gammaFailureDoesNotUpdateAppliedState` |
| 重启恢复 | `DisplayPersistenceTests/softwareModeRestartRecoverySignal` |
| 切回硬件控制和退出 | `GammaDimmingControllerTests/baselineUnavailableFallsBackToIdentityRestore` |
| 唤醒抑制窗口内调节亮度 | `DisplayControlEngineTests/suppressedWriteReplaysAfterGateRecovery` |
| 抑制窗口内多次调节 | 同上(只重放最新 60) |
| 分辨率重配置且面板关闭 | `reconfigureGateDefersThenReplays` |
| 重配置完成通知缺失 | `beginOnlySafetyExpiryTriggersReplay`、`GateStateModelTests/beginOnlySafetyExpiryReleases` |
| 睡眠与重配置重叠 | `GateStateModelTests/shorterReconfigureDoesNotShortenWakeSuppression` |
| 待写设备已断开 | `DisplayControlIntegrationTests/fullLifecycleOrchestration`(断开后不写入) |
| 重启后解除静音 | `MediaKeyTargetSelectorTests/unmuteAfterRestartRestoresPersisted` |
| 无持久化记录 | `unmuteWithNoHistoryUsesFallback` |
| 显示器按钮改变音量 | `unmuteRestoresCapturedCurrentOverStalePersisted` |

### display-control-compatibility
| Scenario | 测试 |
|---|---|
| 亮度不支持但音量支持 | `DisplayCapabilityModelTests/brightnessGammaDoesNotDisableVolumeAndContrast` |
| 原生亮度后端 | `builtInUsesAppleNativeForBrightness` |
| 主码超时备用码不支持 | `mainCodeTimeoutBackupUnsupportedKeepsMainEvidence` |
| 不正确能力声明 | `singlePacketLossKeepsValidSupportEvidence`(诊断保留声明与实测区别,见 D9) |
| 存在服务但硬件无应答 | `unknownCandidateKeepsUnknown`(UI 引导软件模式) |
| 范围覆盖 | `DisplayCompatibilityConfigTests`(validate rangeOverride)、`DisplayPersistenceTests/compatibilityConfigPersistsAcrossRestart` |
| 控制码覆盖 | `MCDP29XXAndLegacyTests/defaultBrightnessMappingIsLuminanceOnly`(0x13 仅显式) |
| 双屏音频输出与鼠标不一致 | `MediaKeyTargetSelectorTests/volumeTargetUsesExplicitBinding` |
| 输出可由系统调节 | `controllableOutputHandedBackToSystem` |
| 目标不支持或匹配未知 | `volumeTargetsAudioDisplayNotMouse`(nil 交还系统)、`shouldAcceptRequiresTargetAndBaseline` |
| 亮度键策略保留 | `brightnessUsesMouseExternalDisplay`、`brightnessFallsBackToSingleExternalWhenMouseNotOnExternal` |

### display-control-diagnostics
| Scenario | 测试 |
|---|---|
| 软件调光 | 10.1 原型 + `DisplayControlSlider` valueSource |
| 持续通信异常 | 10.1 原型(通信异常屏 + 重新检测) |
| 导出失败控制 | `DisplayDiagnosticsLogTests/exportContainsKeyFields` |
| 记录有界 | `ringBufferKeepsLatest100` |
| 两渠道构建 | 12.2(App Store)+12.3(Direct)构建命令 |
| 辅助功能访问 | 10.5 滑块 accessibilityLabel/Value/Hint + 两语文案 |

### 最终验证(组 12)

- 12.1 Direct 全量测试:`tmp/final-test.log`,`** TEST SUCCEEDED **` **315 通过 / 0 失败**(基线 225 + 新增 90)。
- 12.2 App Store 构建:`** BUILD SUCCEEDED **`(tmp/dd-appstore)。
- 12.3 Direct 构建:`** BUILD SUCCEEDED **`(tmp/dd-direct)。
- 12.7 `openspec validate --strict`:`Change is valid`。
- 严格并发检查:双渠道构建与 Direct 全量测试通过；编译仍报告 Swift 6 并发告警，包含 `DisplayControlEngine`/`DDCEnvironmentGate` 的队列闭包捕获和 `DimmingMode` 隔离告警，4.6 保持未完成，未用 `@unchecked Sendable` 抑制。

### 硬件矩阵

- 12.5 最低矩阵:**not-run**。本次自动化会话的命令行环境未能访问用户桌面的 WindowServer/外接显示器 DDC 会话；自动测试已覆盖逻辑流程，画面/OSD 验证需在用户现场实机执行。
- 12.6 扩展矩阵:**not-run**。本次会话未取得 USB-C/DP/HDMI/MCDP29XX/扩展坞/双同型号/只写/Gamma不支持/HDR 的实机观测；这些项目需结合用户的 Dell S2725QC 和实际连接方式逐项记录，不能由 fake 测试代替。

## 交付说明

- 自动测试:新增 7 个测试文件(身份/能力/协议/MCDP/门禁/媒体键/诊断/持久化/Gamma/集成),Direct 全量通过;
- 硬件:12.5/12.6 not-run(本次自动化会话未能访问用户现场的外接显示器 DDC/WindowServer,需在用户现场执行);

## 修复复验（2026-09-09）

- 在 `tmp/dd-direct-review` 重新运行 Direct 全量测试：通过，包含新增 `removedConnectionRejectsOldTokenWrites`、`failedWriteIsRetriedAfterBackoff`、`blockedReadReachesStalledStateUntilRealReturn`。
- `tmp/dd-direct-review` Direct Debug build：通过。
- `tmp/dd-appstore-review` App Store Debug build：通过。
- `openspec validate harden-display-control-reliability --strict`：通过。
- 本轮修复重点：旧连接拒写、物理 in-flight 保持、读/确认 deadline、失败写退避重试、统一门禁恢复、Gamma 基线恢复与失败结果、独立属性后端、真实 optional 值、v2 覆盖持久化、Direct 外接 DDC engine adapter，以及 controller 诊断环形缓冲。
- 删除无效的原生 OSD 提示开关及私有框架调用后，Direct 全量测试和双渠道构建仍通过。
- 仍未完成：0x13 显式兼容配置的生产应用、兼容设置/绑定的用户设置页、诊断生产收集与复制按钮、Swift 6 并发告警收敛；旧 worker 仍保留用于拓扑发现和降级路径；12.4–12.6 目测与硬件矩阵尚未在用户现场执行。
