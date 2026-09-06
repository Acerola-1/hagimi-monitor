# 原生实验进度与证据

更新：2026-09-06。分支 `codex/panel-expansion-single-host`，基线提交 `756b1975`，未提交代码。

## 当前结论

候选由 `HAGIMI_PANEL_SINGLE_HOST=1` 选择，现已保留用户配置的全部指标模块，并接入显示器主行及逐设备档案。性能夹具仍固定 CPU/GPU/内存三卡以保持可比性。默认入口保留原链路；第 6 组的代码接入已推进，完整原生验收尚未完成。

已定位并处理的递归路径包括窗口变化使 Layout 缓存失效、默认对齐查询下探内容、LazyVGrid 随视口变化重新估算内容。候选指标区使用固定两列布局，测量失效键覆盖宽度、结构、语言和字体；显示帧只更新揭示、位置与真实窗口。

**整体门槛未通过。** 性能局部收益不等于完成 60Hz、负载、实际呈现同步和事件/内存验收。早期 `tmp/panel-single-host/prototype-gate-evaluation.md` 等文档中的“全部通过”结论缺少原始证据，已明确标记无效。

测试交接步骤见 [testing-handoff.md](testing-handoff.md)，交回报告的证据边界见 [handoff-review.md](handoff-review.md)。下文各轮记录对应当轮源码，不能跨修复复用性能结论。

## 零揭示边界修复

2026-09-06：新增真实协调器测试，修复前过零反转、跳过负相位区间、几何换版三项均失败（`zero-boundary-red-tests.log`）；首轮测试源码的类型推断编译错误另存 `zero-boundary-red.log`，不作为行为失败证据。

修复将解析轨迹与可见零边界分离：内部带符号位置和速度持续衰减，到达收起边界后保持零揭示；该轮采用内部速度续接；最新边界策略已调整为：零揭示保持态重开从可见位置/速度均为零启动，边界前反转保留速度。尺寸换版保留内部点数/速度，关闭的子分区不向父级传递隐藏高度。测试包括 60/120Hz 采样、0.22/0.24/0.30/0.53s 反转、跨越整个负相位区间、不同自然高度、同目标重定向及嵌套换版。

- `zero-boundary-green.log`：协调器与几何定向测试通过。
- `nested-final-tests.log`：显示器父子拓扑、替换高度、惯性滚动和全量回归通过；官方 xcresult 为 **196 passed / 0 failed / 0 skipped**，路径为 `tmp/dd-review-single-host/Logs/Test/Test-HagimiMonitorDirect-2026.09.06_20-08-08-+0800.xcresult`。
- `nested-accessibility-tests.log`：辅助功能隐藏/命中门控相关布局测试通过；`nested-accessibility-appstore-build.log`：App Store Debug 构建成功。
- `zero-boundary-appstore-build.log`、`zero-boundary-direct-build.log`：两个 Debug 渠道构建成功。
- `zero-boundary-release-build.log`：Direct Release 构建成功。

修复后紧邻采集 `zero-boundary-baseline-normal-60` / `zero-boundary-candidate-normal-60`，两轮均完成 50 次操作且每次起点 `unoccluded=1`。公开显示模式查询记录于 `zero-boundary-refresh-rate.txt`：内屏 1512×982 逻辑尺寸、3024×1964 像素、2×、60.0Hz。舍弃前 10 次后，40 次操作的首 550ms 累计 inclusive CPU 样本如下：

| 指标 | 基线 | 边界修复候选 |
| --- | ---: | ---: |
| StackLayout.placeChildren | 298ms | 28ms |
| sizeThatFits | 436ms | 151ms |
| 主线程 | 7603ms | 5819ms |
| 含 setFrame 的栈 | 2733ms | 2903ms |

递归放置样本降低约 90.6%，主线程样本降低约 23.5%，窗口提交开销未改善。逐操作数据见 `zero-boundary-operation-comparison.json` 及同名前缀 trace/XML/log。这一轮仅复测正常负载单行场景，不覆盖修复后的完整负载/反转矩阵。

两个 Debug 版本已用 `HAGIMI_PANEL_SINGLE_HOST=1` 重启。原生工具分别检查 Direct 英文与 App Store 中文的 CPU 展开/收起端点：收起后行头完整，截图中无明细露出，进程条目从 AX 树移除；截图和 AX 输出保留在当前任务记录中。工具曾出现窗口超时/读数元素 ID 失效，重新获取窗口并使用稳定图标后完成端点操作。尚未取得连续高密度录像，不将端点检查视为实际逐帧同步验收。

以上证明边界状态与几何回归通过，不证明原生屏幕底边已无顿挫。实际画面同步、原始 40–50ms 阻塞归因和完整事件门槛仍待验收。

## 已取得的证据

测试机器：Apple M4，macOS 27.0（26A5425a），主屏 DELL S2725QC，3840×2160、1920×1080 逻辑分辨率、120Hz。当前记录不能充当 macOS 15/26 或真实 60Hz 的结果。

性能使用 Direct Release、同一份从真实采样捕获的 CPU/GPU/内存与进程数据。私有夹具只保存在 `tmp/panel-single-host/real-fixture.json`，由显式环境变量加载，不影响正常监控，也不提交。

第一组有效对照：各 50 次单行切换，舍弃前 10 次操作，保留 20 次展开和 20 次收起。每次操作按日志时间对齐 Instruments 的首 550ms，统计主线程 inclusive 样本。

| 样本指标 | 基线 | 固定列候选 |
| --- | ---: | ---: |
| StackLayout.placeChildren 累计采样 | 361ms | 44ms |
| sizeThatFits 累计采样 | 588ms | 208ms |
| 每次操作主线程 p50 | 253.5ms | 160.5ms |
| 每次操作主线程 p95 | 275ms | 218.75ms |
| 每次操作主线程 p99 | 275.61ms | 294.18ms |

递归栈样本降低约 87.8%；总主线程尾部并未全面改善。以上是操作窗口中的 CPU 样本，**不是屏幕帧耗时**。两次采集不相邻，仍需紧邻交替复测与负载对照。

原始数据在 `tmp/panel-single-host/`：

- `baseline-frozen-120.trace`、对应 `.log`、`-toc.xml`、`-time-profile.xml`。
- `candidate-grid-120.trace`、对应 `.log`、`-toc.xml`、`-time-profile.xml`。
- `analyze_operations.py`、`grid-120-operation-comparison.json`：逐操作区间、每次样本及 p50/p95/p99。
- `candidate-grid-120.log`：预热后的每次 checkpoint 未新增自有自然尺寸测量。
- `geometry-motion-tests.log`、`scroll-lifecycle-tests.log`：原生 hosting 提议测试、固定列与原 LazyVGrid 像素对照、弹簧与 SwiftUI Spring 对照、反转、滚动接管、隐藏后迟到回调隔离。
- `full-direct-tests.log`：Direct 全量 182 个测试通过，包含五项 MetricWidthAuditTests 和父子分区同时换版的可见位置/速度回归。

原生截图观察：340pt 面板收起时高度约 192.5pt，三张完整行头、6pt 侧边/底边和行距、原 Footer；300pt 封顶场景中 Header 固定、Footer 随文档滚动，捕获到部分揭示和完全收起画面。截图采样密度不足以证明不存在一帧呈现先后。

### 紧邻运行的 120Hz 初步对照

2026-09-06 08:00–08:03 串行完成四轮：`baseline-paired-normal-120`、`candidate-paired-normal-120`、`baseline-paired-load8-120`、`candidate-paired-load8-120`。每轮保留 40 次操作的首 550ms，使用同一真实夹具。负载为 8 个 worker，实测约 6.4 核当量。

| 累计 inclusive CPU 样本 | 正常基线 → 候选 | 负载基线 → 候选 |
| --- | ---: | ---: |
| 主线程 | 11214 → 6416ms | 14586 → 8460ms |
| StackLayout.placeChildren | 434 → 59ms | 707 → 34ms |
| sizeThatFits | 653 → 193ms | 1004 → 234ms |
| 窗口 setFrame 栈 | 3604 → 3716ms | 3500 → 4954ms |

递归放置样本分别降低约 86.4% / 95.2%，窗口提交栈并未改善。分析见 `paired-operation-comparison.json`，各运行同名前缀的 `.trace`、`.log`、`-toc.xml`、`-time-profile.xml` 均保存在 `tmp/panel-single-host/`。

`paired-main-queue-gaps.json` 中正常基线/候选最大记录间隔为 19.8/15.7ms，负载为 22.3/13.0ms，均未复现 40–50ms。后续三行同时切换、12 worker 对照也没有记录到大于 40ms 的主队列间隔，证据见 `all-load12-operation-comparison.json` 及 `*-paired-all-load12-120*`。这些是主队列探针与 CPU 样本，不能替代显示帧验证。

**呈现有效性仍待复测：** 上述运行没有同时记录窗口遮挡状态；08:20 原生采集工具报告 Mac 已锁定且无法自动解锁。不能据此确定此前锁定时刻，也不能将这些 CPU 对照当成已验证可见呈现的结果。最新基准入口增加操作开始时的可见性检查，需在解锁、无遮挡环境重新采集。

## 无效和未完成采集

- `baseline-single.trace`：签名导致 Sparkle 加载失败，没有可用动画数据。
- `baseline-repeat-120.trace`：窗口在操作序列开始前失焦隐藏，未完成 40 次有效操作，不纳入比较。基准入口已增加仅对性能运行生效的保持可见条件；正常面板的点外/失焦行为保持原实现。
- `candidate-repeat-120.trace`：操作完整，但缺少同时段有效基线，暂不用于验收结论。
- `scroll-visual.log`：300pt 封顶原生运行，仅用于画面和逻辑检查，不与非封顶基线作性能比较。
- `baseline-stable-120` 与 `candidate-stable-120` 相隔约五小时，不属于紧邻对照。
- `window-sequence.log`：连续画面采集被锁屏阻断，未取得密集画面证据。

## 尚需验收

- 真实 60Hz、可复现 CPU 负载及低电量模式；macOS 15/26 环境。
- 独立、高密度的窗口/内容画面序列，以及 `display: true/false` 的提交对照。
- 原生滚轮/触控板并发接管、部分揭示命中、键盘和 VoiceOver。
- 双渠道、菜单栏/钉住窗口尺寸与原生阴影；两实例并存、重开和切屏。
- 可见/隐藏内存、真实采样、设备与内容结构换版。
- 零揭示边界修复后的原生反转/收尾画面、首次几何准备路径的交互、焦点转移与钉住屏幕封顶。
- 第 6 组完整模块与显示器嵌套的原生验收，以及最终旧链路清理。

上述缺项补齐前不宣告动画问题解决，不移除原生产入口。
