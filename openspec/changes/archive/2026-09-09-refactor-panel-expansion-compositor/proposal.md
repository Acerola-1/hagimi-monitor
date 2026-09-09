## Why

当前面板展开/收起同时依赖 SwiftUI 布局高度动画与独立窗口弹簧，在 60Hz、低电量模式和高系统负载下会触发整棵视图树重复布局与双执行域相位漂移。需要把动画期几何从 SwiftUI 布局系统移入轻量 AppKit 合成容器，并让真实窗口与全部内容几何由同一时钟、同一解析状态共同驱动。

## What Changes

- 将面板从单一 SwiftUI 纵向布局根树重构为 AppKit 管理的合成容器，每张卡片由独立、固定自然尺寸的 SwiftUI hosting island 渲染。
- 保留真实 `NSPanel` 尺寸、原生窗口阴影和原生事件区域；窗口继续随可见内容逐帧改变，不使用固定透明窗口包络或自绘替代阴影。
- 引入统一的几何快照、静止布局求解器和闭式矢量弹簧；由单一显示帧时钟在每次回调中只采样一次，并共同更新窗口高度、卡片揭示高度、后续卡片位置、滚动揭示与底部按钮位置。
- 动画期的卡片位置与裁剪直接更新轻量 AppKit/CALayer 几何，不通过 `@State`、SwiftUI 隐式动画或动态布局提案传播进视图树。
- 展开内容保持顶部固定并只移动下方裁剪边界，不进行缩放、位图快照或材质栅格化；原生实时材质在整个动画期间保持活跃。
- 支持任意动画时刻反向或重定向，从当前解析位置和速度续接，不重置速度。
- 将 6pt 行间距与 10pt 底边距写成统一几何求解器的不变量；明确区分应用侧单次更新的一致性与公共 API 无法对 WindowServer 内部提交顺序、任意高负载 VSync 产出率作形式化保证的边界。
- 以固定 Header、固定 Footer 和独立卡片 viewport 处理超高内容，把自动滚动揭示纳入同一几何轨迹，移除独立 SwiftUI `scrollTo` 动画。
- 删除现有 `CollapsibleDetail` 布局高度补间、`PanelExpansionDriver` 高度预测/尾部校准，以及内容隐式弹簧与 `PanelWindowSpring` 分离求解的链路。

## Capabilities

### New Capabilities

- 无。

### Modified Capabilities

- `panel-animation-consistency`: 将展开/收起契约改为单时钟矢量几何轨迹，要求实时材质、卷出揭示、布局不变量与中断速度连续。
- `fluid-menu-bar-panel`: 将窗口缩放与内容几何纳入同一显示帧采样，同时保留真实窗口边界、系统阴影、菜单栏顶边锚定、屏幕封顶和点外关闭行为。

## Impact

- 主要影响 `MonitorPanelView.swift`、`DisplaySection.swift`、`CompatibleGlassContainer.swift`、`FluidPanelController.swift`、`PinnedPanelController.swift` 与 `Views/Panel/PanelExpansionDriver.swift`。
- 将新增 AppKit 卡片宿主、面板合成容器、几何求解和矢量弹簧协调组件。
- SwiftUI 模块内容的数据与视觉实现继续复用，但不再负责动画期纵向几何布局。
- 两个分发渠道保持相同动画架构；显示器控制仍遵守现有编译边界。
- 不引入第三方依赖；实现依赖 AppKit、SwiftUI 与 QuartzCore 公共 API。
- 测试将扩展为几何求解单元测试、任意时间采样不变量测试、中断续速测试、双渠道构建测试和真实 60Hz/高负载动画回归。
