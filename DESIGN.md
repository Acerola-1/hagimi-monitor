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

本轮范围是原生报表。经典毛玻璃底座保持产品基线，用户明确授权报表导航采用 macOS 27 标签滑块。菜单栏面板材质不随之变更。

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
