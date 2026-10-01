# 2026-10-01 原始证据索引

各回执保留准确产物路径、SHA256、PID、配置哈希、环境、屏幕与逐秒真实累计资源计数。该目录录像和日志为稳定副本；SHA256 清单供内容校验。

## 最终源码、测试与产物

- [源码 SHA 与构建回执](footer-accepted-build-receipt.json)；[最终源码核对](final-source-receipt.json)，仅分析脚本在构建后补入排除规则。
- [采集工具与确切 Swift 源码快照](candidate-source-and-validation.tar.gz)（不包含资源素材/依赖；完整工程仍使用当前仓库）
- [561 项最终测试摘要](final-test-summary.json)；[原始结果对象](direct-footer-accepted-result.json)
- [Direct Release 构建](direct-footer-accepted-release.log)；[App Store Release 构建](appstore-footer-accepted-release.log)
- [准确独立应用身份](artifacts.json)；应用保留在仓库 `tmp/panel-closeout-2026-10-01/CloseoutDirect.app` 和 `CloseoutAppStore.app`。本体路径均未覆盖 `/Applications`。
- 原始测试包：仓库 `tmp/panel-closeout-2026-10-01/direct-footer-accepted.xcresult`。
- [代码审查覆盖与修正](review-notes.json)；[OCR 最终文件选择](review-final-scope.json)；[底部布局审计](footer-premium-audit.json)。

## 无录屏资源对照

| 条件 | 原版 CPU 中位数 | 最终 CPU 中位数 / P95 | 窗口 frame 原版 / 最终 | 最终隐藏尾部 RSS / footprint (MiB) |
|---|---:|---:|---:|---:|
| 正常 | 37.00% | 9.36% / 13.94% | 504 / 2 | 170.05 / 76.09 |
| CPU 压力 | 24.37% | 6.51% / 13.58% | 530 / 2 | 170.31 / 75.70 |
| CPU＋GPU 压力 | 24.80% | 5.57% / 13.36% | 510 / 2 | 170.09 / 75.94 |

累计 Mach ticks 按实测 timebase 换算，100% 为一核；P95 为最近秩。隐藏为最后五个采样点中位数。单轮同配置对照有背景系统负载扰动，不推导 GPU、能耗或显示掉帧收益。

- 原版：[正常重采](original-menu-normal-repeat.json)、[CPU](original-menu-cpu.json)、[CPU＋GPU](original-menu-both.json)。[基线仪器范围](original-baseline/instrumentation-receipt.json)。
- 最终固定底部：[正常](footer-native-normal-resource.json)、[CPU](footer-native-cpu.json)、[CPU＋GPU](footer-native-both.json)。
- [所有资源摘要](final-resource-summary.json)：只有 `resource_comparison=true` 能用于资源对照，录像和 trace 轮排除；[明确排除原因](analysis-exclusions.json)。早期双屏 120Hz 与后来单屏 60Hz 分组解释，不合并。
- 同候选旧兼容路径及多个宿主对照：`verified-native-*` 与 `verified-legacy-*` 回执，使用各自记录的二进制版本。

## 生命周期与合成侧证据

- [真实六轮、24 个状态检查](verified-lifecycle.json)及同名 `.app.log`；[统计库读回](lifecycle-statistics.json)。这里不是 50 次性能夹具，摘要的性能范围 `valid=false` 不表示生命周期检查失败。
- [无录屏 trace 摘要](trace-summary.json)，同名 XML/trace 日志保留。成功片段仅初始 8 秒，不提供掉帧率分母。三项 Document Missing Template 导出失败保留在摘要，不计通过。
- 原始 `.trace` 包留在仓库 `tmp/panel-closeout-2026-10-01/`；含并行 ScreenCaptureKit 的片段单独见 [hitches-summary](hitches-summary.json)。
- WindowServer 资源读取 -1；未提权探测硬件或修改系统安全设置。

## 录像与截图

全量元数据、产物版本和 PID 见 [final-video-index.json](final-video-index.json)。下表时长仅用于寻找片段；不是显示 FPS 或掉帧率。自动夹具录像不替代用户物理控件验收。

| 录像 | 秒 | 范围 |
|---|---:|---|
| [focus-battery-dark.mp4](focus-battery-dark.mp4) | 34.75 | full-matrix |
| [focus-battery-light.mp4](focus-battery-light.mp4) | 35.12 | full-matrix |
| [focus-display-dark.mp4](focus-display-dark.mp4) | 33.92 | full-matrix |
| [focus-display-light.mp4](focus-display-light.mp4) | 35.14 | full-matrix |
| [focus-reverse-dark.mp4](focus-reverse-dark.mp4) | 33.88 | full-reverse |
| [focus-reverse-light.mp4](focus-reverse-light.mp4) | 33.88 | full-reverse |
| [footer-appstore-smoke.mp4](footer-appstore-smoke.mp4) | 34.98 | full-matrix |
| [footer-compatible-smoke.mp4](footer-compatible-smoke.mp4) | 34.83 | full-matrix |
| [footer-native-normal.mp4](footer-native-normal.mp4) | 34.79 | full-matrix |
| [original-visual-dark-complex.mp4](original-visual-dark-complex.mp4) | 34.37 | full-matrix |
| [original-visual-dark-dark.mp4](original-visual-dark-dark.mp4) | 34.97 | full-matrix |
| [original-visual-dark-white.mp4](original-visual-dark-white.mp4) | 34.71 | full-matrix |
| [original-visual-light-complex.mp4](original-visual-light-complex.mp4) | 33.76 | full-matrix |
| [original-visual-light-dark.mp4](original-visual-light-dark.mp4) | 34.93 | full-matrix |
| [original-visual-light-white.mp4](original-visual-light-white.mp4) | 34.95 | full-matrix |
| [stress-visual-native-both.mp4](stress-visual-native-both.mp4) | 34.79 | full-matrix |
| [stress-visual-native-cpu.mp4](stress-visual-native-cpu.mp4) | 34.13 | full-matrix |
| [visual-dark-balanced-complex.mp4](visual-dark-balanced-complex.mp4) | 34.23 | full-matrix |
| [visual-dark-balanced-dark.mp4](visual-dark-balanced-dark.mp4) | 34.84 | full-matrix |
| [visual-dark-balanced-white.mp4](visual-dark-balanced-white.mp4) | 34.38 | full-matrix |
| [visual-dark-vibrant-complex.mp4](visual-dark-vibrant-complex.mp4) | 34.78 | full-matrix |
| [visual-dark-vibrant-dark.mp4](visual-dark-vibrant-dark.mp4) | 35.12 | full-matrix |
| [visual-dark-vibrant-white.mp4](visual-dark-vibrant-white.mp4) | 34.47 | full-matrix |
| [visual-light-balanced-complex.mp4](visual-light-balanced-complex.mp4) | 34.80 | full-matrix |
| [visual-light-balanced-dark.mp4](visual-light-balanced-dark.mp4) | 34.52 | full-matrix |
| [visual-light-balanced-white.mp4](visual-light-balanced-white.mp4) | 34.75 | full-matrix |
| [visual-light-vibrant-dark.mp4](visual-light-vibrant-dark.mp4) | 35.12 | full-matrix |
| [visual-light-vibrant-white.mp4](visual-light-vibrant-white.mp4) | 33.45 | full-matrix |

| [demo-retry-light.mp4](demo-retry-light.mp4) | 19.88 | Demo 24 operations including rapid reversal |
| [demo-retry-dark.mp4](demo-retry-dark.mp4) | 19.18 | Demo 24 operations including rapid reversal |

固定按钮截图：[原生滚到显示器](footer-qa/footer-native-normal-27.png)、[App Store](footer-qa/footer-appstore-smoke-27.png)、[默认兼容路径](footer-qa/footer-compatible-smoke-27.png)。已核对原生 18/27 秒与两渠道 27 秒：主体位置变化，按钮保持底部。点击和键盘仍待针对新增行为的短时人工确认。

## 失败与边界

- `original-menu-normal` 初次资源轮与视频解码/哈希重叠，原始记录保留，使用 `original-menu-normal-repeat`。
- `demo-rebuilt-light` 冷启动未及时找到窗口，回执和日志保留；`demo-retry-*` 使用有界等待成功，各 24 次。
- `native-normal`、`native-normal2`、早期 pinned/full scope 不满足当前 50 次协议的回执不计资源通过，详见完整摘要。
- 中途失败测试日志/XCResult 仍保留于 `tmp/panel-closeout-2026-10-01/`；离屏宿主测试已修复，最终561全通过。
- 最新候选/固定按钮缺120Hz最终录像；原人工矩阵持续有效，仅新增固定按钮待短时操作确认。默认切换、旧路径清理及切换后回归未实施，change 未归档。

## OpenSpec 状态

[严格校验日志](openspec-final-validate.log)通过；[任务状态](openspec-final-state.json)为 26/30，四项未完成，未归档。

[测试副本退出记录](process-cleanup.json)：有限压力/录制已结束，遗留独立副本已退出。

刷新率解释修正：`refresh_hz` 为 CGDisplayMode 的接口读数，不等同于硬件最高能力或实际显示帧节奏。用户确认内屏支持120Hz；[当前接口复核](display-capabilities.json)仍报告60，两者差异未核实，不将其写成硬件缺失。

## 正式默认路径的最终验证

[最终源码](final-production-source-receipt.json)、[两渠道准确产物](final-production-artifacts.json)、[最终561项测试](final-merged-test-summary.json)、[清理后的review](review-after-default.json)。两渠道在无运动选择开关下各完成50次全模块操作，各2次窗口frame提交。6轮显隐/多宿主回归24项有效，失败0。原始新回执为 `final-production-{direct,appstore,lifecycle}.json`，同名日志及配置保留本地。

原始采集包约859MiB，本目录及 `tmp/panel-closeout-2026-10-01` 的本地文件均保留。按项目验证产物约定，Git只保存索引、哈希、必要源码参考和最终摘要；大体积录像、原始日志/配置不自动提交。`manifest.sha256` 仍覆盖本地原始文件，另一 checkout 重现需取得该原始包或按协议重新采集。

归档后任务为29/30；三份受影响主规范严格校验通过。全仓校验还有无关旧规范错误，见本地 `archive-main-spec-validation.log`。菜单栏清理的正常退出回执见本地 `menu-app-cleanup.json`，系统/网络/鼠标服务保留。
