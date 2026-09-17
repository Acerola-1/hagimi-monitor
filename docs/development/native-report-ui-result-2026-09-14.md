# 原生报表 UI 改进与验证

## 已实现

- 概览改为明确的统计日期、异常提示、四项核心指标、综合趋势、传输与运行摘要、评分依据和活动节律。移除大圆环评分，不删评分维度。
- 时间范围与硬件分类共用 ReportNavigationPicker：macOS 27 使用 `.pickerStyle(.tabs)`、`.controlSize(.large)` 及系统 `.glassEffect(.regular.interactive(), in: .capsule)`；macOS 15–26 回退原生 segmented。没有自建拖动或逐帧动画。
- 普通尺寸 tabs 实机仍呈传统小分段外观，大尺寸改为圆润滑块。分别完成时间“近 7 天→近一年”和硬件“设备→GPU”的拖动检查。
- 本机首项改称设备信息，身份信息直接展示，高级硬件属性折叠保留；不删除底层规格字段。本轮没有重写硬件采集模型或彻底消除分类之间的所有重复。
- 首页模块配色接入 MonitorPalette，GPU/电源等图标沿用 MonitorKind；补回侧栏压力告警入口，改正报表窗口名称及图标操作的可访问标签。
- 自定义日期按下一天零点作为右开边界。累计传输量保留真实零值与缺失值区别。中断事件使用中性色，不误标绿色恢复。
- 新增/补齐 37 项中英文文案。既有报表中的其他历史翻译问题不纳入全量通过声明。

## 工具链

机器已安装 `/Applications/Xcode-beta.app`：Xcode 27.0，build 27A5237l，macOS SDK 27.0。默认 xcode-select 仍指向旧版 Xcode；本轮不改系统全局选择。

运行 `scripts/build-native-report.sh` 即以 Xcode 27 构建两个渠道。可通过 DEVELOPER_DIR 指定另一个 SDK 27+ 工具链。产物仍最低部署到 macOS 15；需要用 Xcode 27 编译，不能用旧 SDK 解析新 API。

Apple 资料：
- [TabsPickerStyle](https://developer.apple.com/documentation/swiftui/tabspickerstyle)
- [Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/)

## 本轮验证证据

- 两渠道最终 `BUILD SUCCEEDED`：`tmp/report-build-both.log`。
- 既有 ReportCorrectnessTests、ReportDataAggregatorTests 共 19 项通过：`tmp/report-ui-tests.log`。此测试运行后只继续修改展示、本地化和控件样式，不涉及聚合实现。
- Direct 中文真实历史数据；App Store 英文有数据与无数据状态；深浅外观均在原生窗口截图检查。
- 英文窗口拖动缩窄至窗口最小宽度附近：顶部操作、四列指标、长标签换行与滚动可用。截图未发现主指标截断。
- 英文原生日期浮窗的 From/To/Apply 显示正常；取消未提交。
- 系统可访问树将两个选择器识别为标签页组，而非独立自绘按钮。硬件高级属性默认折叠，设备规格可见。
- `git diff --check` 通过；新增文案中英结构校验通过。
- premium UI strict 静态审计零问题：`tmp/report-ui-audit.json`。该审计器偏向网页，本项目明确使用原生控件所有权；其通过不替代 SwiftUI 实机验证。
- DESIGN.md lint 零错误、零警告：`tmp/report-design-lint.log`。颜色/几何由既有 Swift 运行时代码持有，未复制为第二套网页 token。

## 验证边界

未运行 macOS 15/26 实机、VoiceOver 全流程或 Instruments 性能采集；不宣称所有旧报表问题、内存行为和长范围卡顿已彻底修复。真实系统玻璃观感随活动窗口、系统外观和辅助功能偏好变化，静态截图不能展示完整拖动中的折射动画。

代码保留在 `codex/native-report-polish`，未提交。开始前的报表与本地化快照在 `tmp/report-ui-before/`，保留了原有工作区修改。
