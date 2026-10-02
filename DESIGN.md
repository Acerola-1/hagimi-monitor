---
version: alpha
name: HagimiMonitor
description: Native macOS system monitoring
omitted:
  - section: colors
    reason: MonitorPalette.swift owns adaptive module and severity colors; system semantic colors own native surfaces.
  - section: spacing
    reason: Native layout values live in their SwiftUI component owners, not a generated web token system.
  - section: rounded
    reason: ReportCardView and system controls own geometry.
typography:
  sans:
    fontFamily: SF Pro, PingFang SC, system-ui
  mono:
    fontFamily: SF Mono, monospace
components:
  report-card: {}
  report-navigation: {}
---

# HagimiMonitor Design System

## Overview

原生系统监测工具，服务在 Mac 上回看资源使用与异常的用户。中文与英文同等支持。视觉参照 macOS 系统设置和活动监视器的工具属性：信息密集但数值突出；不采用宣传页、巨大评分仪表或多层彩色胶囊。

报表范围是原生报表。经典毛玻璃底座保持产品基线，用户明确授权报表导航采用 macOS 27 标签滑块。菜单栏面板材质不随之变更。

## Colors

运行时代码保持唯一所有权：`MonitorPalette.swift` 的 moduleTint 与 severityTint 负责模块和状态颜色；AppKit 的 controlBackgroundColor/windowBackgroundColor 及 SwiftUI primary/secondary 负责表面和文字。历史报表其余图表仍由 ReportUIHelper 配色，后续统一时须同时检查图例与系列，不能只换首页的图例颜色。

## Typography

系统字体支持中英混排。页面标题 largeTitle；主指标 title；组标题 headline；说明 callout。数字使用 monospacedDigit，长应用名称保持正常字体和换行。标注字号不应用于主要读数。

## Layout

概览顺序为时段、异常、紧凑评分与数据完整度、四项核心指标、综合趋势、传输与运行摘要、活动节律。评分带保持辅助信息密度，不做巨大仪表盘；覆盖率来自选定范围的有效采样秒数。模块详情仍各自负责图表和硬件侧栏。ScrollView 负责长内容，明细表保持自己的滚动区域。最小窗口 1100×640，默认 1380×880。四列指标不采用缩放文本；完整值允许换行。

## Elevation & Depth

窗口底座用现有 VisualEffectBlurView；内容卡片只使用浅表面和细描边，不叠加玻璃或重阴影。Liquid Glass 留给系统导航控件，其材质与交互不由自定义拖动动画模拟。

## Shapes

ReportCardView 是卡片形状的所有者；系统 Picker 和 Button 保持系统形状与焦点行为。

## Components

ReportNavigationPicker 统一时间与硬件分类导航，macOS 27 使用大尺寸 tabs 与系统 glassEffect，15/26 使用 segmented。硬件标签过长时横向滚动，不能删去分类。ReportCustomRangePicker 使用起止端点切换和一个 graphical 原生 DatePicker；打开时同步已选范围，取消不提交，应用后以自然日开区间提交完整日期范围。选择中的范围与图表已提交范围分别由视图模型管理；加载时保留旧数据显示其真实日期并提示更新。

核心指标整块是原生 Button，保留键盘访问与鼠标悬停反馈；每个按钮进入对应模块。无样本显示破折号，不以绿色状态代替未知。读数只消费现有聚合模型，评分依据完整保留。

图标来自 SF Symbols 与 MonitorKind.symbol，进程图标使用现有 ReportIconProvider。避免自建符号字库。刷新、打印、导出继续使用原有动作，图标按钮必须有可访问名称。

不引入额外持续动画。系统控件处理减弱动态效果。变化通过内容和文字表达，颜色仅作补充。

## Do's and Don'ts

- 保留完整数据口径、单位、缺失状态及进入明细的路径。
- 通过层级和空间组织信息，不给每一个数字增加彩色徽章。
- 不把统计范围评分描述成实时设备健康诊断。
- 不以静态检查代替真实窗口、拖动与长文本验收。

## Menu Panel Motion

菜单栏负载环使用同一显示值驱动弧长与核心颜色，等级交界连续混色。目标变化采用有限解析运动，幅度和速度续接；稳定目标和指标模式不持续运行。沿用标准系统状态项与原几何，参数由 MonitorConstants 拥有，计算口径与验证边界见 [负载环审计](docs/development/menu-bar-load-ring.md)。

菜单栏面板的内容密度、颜色、原生操作与经典毛玻璃保持现有产品合同。运动迁移复用正式组件，采用固定容量窗口和系统图层播放；文字与指标不缩放，不以精简信息降低成本。自然尺寸、滚动、输入、排序和生命周期的所有权见 [面板运动协议](docs/development/panel-native-motion.md)。

窗口底座为经典 popover，行材质保持 withinWindow；颜色来自 MonitorPalette，几何和运动来自 MonitorConstants。窗口轮廓、圆角、描边与阴影必须在真实浅色、深色和复杂背景下验收，只有窗口截图或构建成功不足以证明可读性。全模块候选统一验收后才切换默认路径。

面板限高时，模块内容拥有滚动区域，底部的监视器、工具和设置独立固定在可见轮廓底部。未限高时保持原有自然高度与间距；固定操作区不遮盖最后一个模块，也不接管模块的滚动、排序或焦点。其位置随同一轮廓轨迹运动，用户滚动不移动这些按钮。

## Statistics Settings

### 统计数据统计的运行时分属（2026-10-01）

设置页与报表的视觉决定按「谁拥有」划分，避免同一数值在两处各写一套：

| 维度 | 所有者 | 统计页的用法 |
|---|---|---|
| 表面与几何 | `SettingsPage` / `SettingsGroup` / `SettingsCard` / `SettingsDivider` | 直接复用，不新建统计专用材质 |
| 模块颜色 | `MonitorPalette.moduleTint(for:)` | 只用于展开详情的指标名称与用量行图标 |
| 严重程度颜色 | `MonitorPalette.severityTint(for:)` | 只用于真实系统压力；普通应用高占用不染红 |
| 字号层级 | 系统字体（body/callout/title3/caption） | 主读数用 body/callout 加等宽数字，不用 caption 承载关键数值 |
| 数值格式 | `StatisticsDisplayFormat` | 容量二进制、速率与总量十进制、占比百分比，全表面同源 |
| 门槛与档位 | `StatisticsMetricDefinition` | 判定与标签都从它生成，调用点不复制数字 |
| 结论与质量 | `ReportPeriodConclusion` / `StatisticsDataQuality` | 结论只描述系统压力；估算与部分覆盖必须显式说明 |

设置视图状态（供后续核对）：范围选择「今日 / 近 7 日 / 近 30 日」为分段控件，与「查看完整统计」同排置顶；暂停记录后范围选择器保留，仍可查看历史；最近应用区默认两行、按身份排序，行内展开独立保存；用量与传输分为两组，键值与单位来自 `StatisticsDisplayFormat`。


设置页沿用 `SettingsPage`、`SettingsGroup`、`SettingsCard`、`SettingsDivider` 的表面、几何与间距，不复制一套统计专用材质。范围选择和完整报表入口并列置顶；历史系统结论、最近应用观测、用量和传输逐层排列，存储管理保持底部设置入口。暂停记录仍可选择历史范围和打开报表。

最近应用区默认最多两行。每行以真实应用图标、名称、主要指标的数值形成阅读顺序，用一个原生 `DisclosureGroup` 展开该应用的全部指标；每行独立保存展开状态。名称保持正常字体，数值用等宽数字，主要读数为 body/callout，不使用 caption 承载。长名称可收窄，但 tooltip 与辅助功能保留全文。

历史系统压力和最近应用占用使用不同标题，不用应用高占用覆盖历史系统结论。模块颜色由 `MonitorPalette.moduleTint` 拥有，仅用于展开详情的指标名称；严重颜色属于真实系统压力，不给普通高占用应用重复增加红色标记。档位分布与零时长图例退出设置默认视图，完整事件和范围语义由 OpenSpec 后续报表任务实现。

当前应用事件模型只提供高值观测次数和首次/最近时间，页面如实显示这些量，不把次数标成连续时长。应用内存使用 GiB/MiB，网络速率使用 MB/s。主指标暂按内存、CPU、GPU、网络选择，应用按身份排序以保留展开位置；容量相关门槛与严重度排序等待共享数据合同实现。DEBUG 示例只生成视图输入，并带明显标注，不注入共享事件或导出输入。
