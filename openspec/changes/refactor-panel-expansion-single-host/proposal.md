## Why

面板展开与收起在 60Hz 和 CPU 高负载下出现 40–50ms 慢帧，现有明细高度动画会向父栈及兄弟内容传播布局提议，独立窗口弹簧还需要预测与收尾校准。需要在完整保留现有视觉、材质和真实窗口行为的前提下，隔离昂贵内容的尺寸协商，并统一窗口与面板内部的运动状态。

## What Changes

- 每个面板保留一个 `NSHostingView`、现有 `CompatibleGlassContainer` 和实时材质层级；通过轻量 SwiftUI 自定义布局读取已知几何，给行头与明细内容稳定的尺寸提议。
- 将自然尺寸与揭示尺寸分离：内容按自然尺寸排版，只有卡片外壳、明细局部视口和后续卡片位置随动画变化。允许轻量外壳逐帧定位，不以“SwiftUI 完全不布局”作为实现前提。
- 将 340pt 面板 / 328pt 卡片、左右 6pt、顶部 8pt、底部 6pt、行距 6pt、卡片 continuous 14pt 和外框 continuous 20pt 纳入视觉验收；行头按实际自然高度完整展示，收起时没有任何明细像素或隐藏控件命中。
- 保留 response 0.32 / dampingFraction 0.82，由面板实例私有的单一显示帧时钟生成几何样本，统一驱动揭示高度、卡片位置、滚动揭示与真实 `NSPanel` 尺寸。反向点击继承当前运动位置和速度。
- 移除展开链上的独立窗口弹簧、隐式几何弹簧及常规收尾高度补偿；尺寸变化、嵌套显示器展开和屏幕封顶通过版本化几何与统一求解处理。
- 保留 Header 固定、底部按钮随主体滚动的现有结构，以及原生窗口阴影、点外关闭、钉住窗口定位和两个分发渠道的能力边界。
- 先验证使用真实生产组件的三卡片原生样机。应用侧同一逻辑样本可以由代码保证；WindowServer 实际呈现同步、布局隔离收益和材质保真必须由样机与性能记录证明，失败时不继续迁移生产面板。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `panel-animation-consistency`: 将版本统一的展开契约明确为稳定内容提议、单一运动状态、可中断弹簧、确定性滚动揭示，以及视觉和性能验收。
- `fluid-menu-bar-panel`: 将窗口独立动画改为统一几何样本驱动的真实尺寸贴合，并明确单宿主材质层级、精确留白圆角、封顶滚动和原生事件区域的约束。

## Impact

- 影响 `MonitorPanelView.swift`、`Views/Panel/DisplaySection.swift`、`PanelExpansionDriver.swift`、`FluidPanelController.swift`、`PinnedPanelController.swift` 和展开期间的刷新门控。
- 增加轻量布局、自然尺寸登记、运动求解和帧提交适配；复用现有指标内容、`MonitorPalette`、`StaticMetricSizing`、玻璃 modifier 和窗口底材质，不新增第三方依赖或私有 API。
- 验证覆盖 Direct scheme 测试、两个 scheme 的隔离构建、菜单栏与钉住面板、macOS 15 / 26+、60Hz / 高刷新率、低电量模式及可复现 CPU 负载。
- 本计划是旧 `refactor-panel-expansion-compositor` 方案的替代方向，实施本计划时不执行旧计划中的拆分 hosting 岛、AppKit 逐卡裁剪、10pt 底边距或固定 Footer 任务。旧计划目录保留供对照；本次只创建新计划，不更改应用代码或主规格。
